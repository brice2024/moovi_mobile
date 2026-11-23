import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';

import 'test/offers_page.dart';

const _ink = Color(0xFF3A2208);
const _green = Color(0xFF1FA45B);
const _amber = Color(0xFFE07B00);
const _salmon = Color(0xFFD9826B);
const _red = Color(0xFFC62828);

enum DocStatus { verified, pending, rejected, missing }

/// Les 5 pièces demandées (maquettes 18-19).
/// `key` = clé dans la map `drivers/{uid}.documents` et nom du fichier Storage
/// `drivers/{uid}/docs/{key}.jpg`. `legacyKeys` = anciennes clés écrites par
/// l'ancienne version de CarInfos / MotoInfos (encore prises en compte).
enum DriverDoc {
  vehicle(
    'Photo du véhicule',
    Icons.directions_car_rounded,
    Icons.add_a_photo_outlined,
    true,
    ['front', 'left', 'right', 'back', 'interior'],
  ),
  plate("Plaque d'immatriculation", Icons.workspace_premium_outlined,
      Icons.camera_rounded, true, []),
  registration('Carte grise', Icons.description_outlined,
      Icons.upload_file_rounded, false, []),
  license('Permis de conduire', Icons.badge_outlined,
      Icons.upload_file_rounded, false, []),
  idCard("Carte d'identité", Icons.contact_mail_outlined,
      Icons.upload_file_rounded, false, []);

  const DriverDoc(
      this.title, this.icon, this.actionIcon, this.isPhoto, this.legacyKeys);

  final String title;
  final IconData icon;
  final IconData actionIcon;
  final bool isPhoto;
  final List<String> legacyKeys;

  String get key => name;
  String get actionLabel => isPhoto ? 'Ajouter une photo' : 'Importer document';
}

DocStatus _entryStatus(Object? entry) {
  if (entry is! Map) return DocStatus.missing;
  final s = entry['status'];
  if (s == 'verified' || s == 'approved') return DocStatus.verified;
  if (s == 'rejected') return DocStatus.rejected;
  return DocStatus.pending; // 'pending' ou absent = envoyé, en attente
}

/// Statut d'une pièce. Les champs `status` (« verified » | « rejected ») sont
/// renseignés côté back-office lors de la validation.
DocStatus _statusFor(DriverDoc doc, Map<String, dynamic> documents) {
  final current = _entryStatus(documents[doc.key]);
  if (current != DocStatus.missing) return current;

  // Compatibilité : anciennes photos multiples (front, left, ...).
  final legacy = doc.legacyKeys
      .map((k) => _entryStatus(documents[k]))
      .where((s) => s != DocStatus.missing)
      .toList();
  if (legacy.isEmpty) return DocStatus.missing;
  if (legacy.contains(DocStatus.rejected)) return DocStatus.rejected;
  if (legacy.every((s) => s == DocStatus.verified)) return DocStatus.verified;
  return DocStatus.pending;
}

String? _rejectionReason(DriverDoc doc, Map<String, dynamic> documents) {
  final entry = documents[doc.key];
  if (entry is Map && entry['rejectionReason'] is String) {
    return entry['rejectionReason'] as String;
  }
  return null;
}

/// Vérification chauffeur : envoi des 5 pièces puis soumission du dossier.
/// `drivers/{uid}.verificationStatus` : pending | approved | rejected ;
/// `submittedAt` est posé lors de la soumission.
class DriverVerificationPage extends StatefulWidget {
  const DriverVerificationPage({super.key});

  @override
  State<DriverVerificationPage> createState() => _DriverVerificationPageState();
}

class _DriverVerificationPageState extends State<DriverVerificationPage> {
  final _picker = ImagePicker();
  final Set<DriverDoc> _uploading = {};
  bool _submitting = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _driverRef(String uid) =>
      FirebaseFirestore.instance.collection('drivers').doc(uid);

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? _red : null,
      ));
  }

  // ---------------------------------------------------------------------------
  // Envoi d'une pièce
  // ---------------------------------------------------------------------------

  Future<ImageSource?> _chooseSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded,
                    color: MooviGradient.end),
                title: const Text('Prendre une photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded,
                    color: MooviGradient.end),
                title: const Text('Choisir dans la galerie'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _upload(DriverDoc doc) async {
    final uid = _uid;
    if (uid == null || _uploading.contains(doc)) return;

    final source = await _chooseSource();
    if (source == null || !mounted) return;

    XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
    } catch (e) {
      debugPrint('Sélection image impossible : $e');
      _snack("Impossible d'accéder à l'appareil photo ou à la galerie.",
          error: true);
      return;
    }
    if (file == null || !mounted) return;

    setState(() => _uploading.add(doc));
    try {
      final path = 'drivers/$uid/docs/${doc.key}.jpg';
      final ref = FirebaseStorage.instance.ref(path);
      final task = ref.putFile(
        File(file.path),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      await task.timeout(const Duration(seconds: 60), onTimeout: () async {
        await task.cancel();
        throw TimeoutException('upload');
      });
      final url = await ref.getDownloadURL();

      final entry = {
        'url': url,
        'path': path,
        'status': 'pending',
        'uploadedAt': FieldValue.serverTimestamp(),
      };
      try {
        // update() remplace toute l'entrée (efface un ancien motif de refus).
        await _driverRef(uid).update({
          'documents.${doc.key}': entry,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (e) {
        if (e.code != 'not-found') rethrow;
        await _driverRef(uid).set({
          'documents': {doc.key: entry},
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      _snack('${doc.title} envoyé(e) avec succès.');
    } on TimeoutException {
      _snack("L'envoi a pris trop de temps. Vérifiez votre connexion et réessayez.",
          error: true);
    } on FirebaseException catch (e) {
      debugPrint('Envoi ${doc.key} : ${e.plugin} ${e.code} ${e.message}');
      _snack(
        e.plugin == 'firebase_storage'
            ? "Échec de l'envoi du document : le stockage n'est pas disponible "
                'pour le moment. Réessayez plus tard.'
            : "Le document n'a pas pu être enregistré. Réessayez.",
        error: true,
      );
    } catch (e) {
      debugPrint('Envoi ${doc.key} : $e');
      _snack("Échec de l'envoi du document. Réessayez.", error: true);
    } finally {
      if (mounted) setState(() => _uploading.remove(doc));
    }
  }

  // ---------------------------------------------------------------------------
  // Soumission du dossier
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    final uid = _uid;
    if (uid == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await _driverRef(uid).set({
        'verificationStatus': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _snack('Dossier envoyé ! Il sera vérifié sous 24h.');
    } catch (e) {
      debugPrint('Soumission dossier : $e');
      _snack("Impossible d'envoyer le dossier. Réessayez.", error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openDriverMode() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const OffersPage()),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return Scaffold(
      backgroundColor: MooviGradient.start,
      body: MooviGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              const MooviHeader(title: 'Vérification Chauffeur'),
              Expanded(
                child: uid == null
                    ? const Center(
                        child: Text('Vous devez être connecté.',
                            style: TextStyle(color: Colors.white)),
                      )
                    : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: _driverRef(uid).snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const Center(
                              child: Text('Impossible de charger les documents.',
                                  style: TextStyle(color: Colors.white)),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                              child:
                                  CircularProgressIndicator(color: Colors.white),
                            );
                          }
                          return _buildBody(snapshot.data!.data() ?? const {});
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> data) {
    // Documents de la racine + anciens documents rangés sous « moto ».
    final moto = data['moto'];
    final documents = <String, dynamic>{
      if (moto is Map && moto['documents'] is Map)
        ...(moto['documents'] as Map).cast<String, dynamic>(),
      if (data['documents'] is Map)
        ...(data['documents'] as Map).cast<String, dynamic>(),
    };

    final statuses = {
      for (final d in DriverDoc.values) d: _statusFor(d, documents),
    };
    final done = statuses.values
        .where((s) => s == DocStatus.verified || s == DocStatus.pending)
        .length;
    final total = statuses.length;
    final anyRejected = statuses.values.contains(DocStatus.rejected);

    final status = data['verificationStatus']?.toString();
    final approved = status == 'approved';
    final submitted = !approved &&
        status == 'pending' &&
        data['submittedAt'] != null &&
        done == total &&
        !anyRejected;
    final dossierRejected = !approved && (status == 'rejected' || anyRejected);

    // Mise en page « vide » (maquette 18) tant qu'aucune pièce n'est envoyée.
    final emptyLayout = done == 0 && !anyRejected;

    final _Phase phase;
    if (approved) {
      phase = _Phase.approved;
    } else if (submitted) {
      phase = _Phase.submitted;
    } else if (dossierRejected) {
      phase = _Phase.rejected;
    } else {
      phase = _Phase.collecting;
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: [
              Text(
                'Veuillez compléter les informations pour activer votre compte chauffeur',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
              const SizedBox(height: 16),
              _ProgressCard(done: done, total: total, phase: phase),
              const SizedBox(height: 16),
              for (final doc in DriverDoc.values) ...[
                _DocCard(
                  doc: doc,
                  status: statuses[doc]!,
                  reason: _rejectionReason(doc, documents),
                  expanded: emptyLayout ||
                      statuses[doc] == DocStatus.rejected,
                  uploading: _uploading.contains(doc),
                  onPressed: () => _upload(doc),
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: switch (phase) {
            _Phase.approved => _BottomButton(
                label: 'Accéder au mode chauffeur',
                icon: Icons.arrow_forward_rounded,
                onPressed: _openDriverMode,
              ),
            _Phase.submitted => const _BottomButton(
                label: 'En cours de validation · sous 24h',
                icon: Icons.hourglass_top_rounded,
                onPressed: null,
              ),
            _ => _BottomButton(
                label: 'Soumettre pour validation',
                icon: Icons.send_rounded,
                loading: _submitting,
                onPressed: done == total && !anyRejected ? _submit : null,
              ),
          },
        ),
      ],
    );
  }
}

enum _Phase { collecting, submitted, approved, rejected }

// -----------------------------------------------------------------------------
// Carte de progression
// -----------------------------------------------------------------------------

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.done,
    required this.total,
    required this.phase,
  });

  final int done;
  final int total;
  final _Phase phase;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : done / total;

    final (IconData chipIcon, String chipText, Color chipBg, Color chipFg) =
        switch (phase) {
      _Phase.approved => (
          Icons.verified_rounded,
          'Compte chauffeur validé',
          const Color(0xFFD6F2E1),
          _green
        ),
      _Phase.submitted => (
          Icons.hourglass_top_rounded,
          'En cours de validation · sous 24h',
          const Color(0xFFFFE28A),
          const Color(0xFF5C4A00)
        ),
      _Phase.rejected => (
          Icons.error_rounded,
          'Pièces refusées : renvoyez-les',
          const Color(0xFFFFD9D6),
          _red
        ),
      _Phase.collecting => (
          Icons.check_circle_rounded,
          'Validation sous 24h',
          const Color(0xFFFFE28A),
          const Color(0xFF5C4A00)
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MooviGradient.card,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$done/$total documents complétés',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD4AE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${(ratio * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: MooviGradient.brownCard,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) => Container(
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD4AE),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.centerLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: c.maxWidth * ratio,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [MooviGradient.brownCard, MooviGradient.start],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(chipIcon, size: 15, color: chipFg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    chipText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: chipFg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Carte document
// -----------------------------------------------------------------------------

class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.doc,
    required this.status,
    required this.expanded,
    required this.uploading,
    required this.onPressed,
    this.reason,
  });

  final DriverDoc doc;
  final DocStatus status;
  final String? reason;

  /// true = disposition de la maquette 18 (bouton pleine largeur sous le titre).
  final bool expanded;
  final bool uploading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final sent = status == DocStatus.verified || status == DocStatus.pending;

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          doc.title,
          style: const TextStyle(
            fontSize: 16,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: _ink,
          ),
        ),
        const SizedBox(height: 4),
        _StatusLabel(status: status),
        if (reason != null && status == DocStatus.rejected) ...[
          const SizedBox(height: 4),
          Text(
            reason!,
            style: const TextStyle(fontSize: 12, color: _red),
          ),
        ],
      ],
    );

    final iconBox = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: sent ? Colors.white : MooviGradient.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(doc.icon, size: 24, color: _ink),
    );

    if (expanded) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                iconBox,
                const SizedBox(width: 14),
                Expanded(child: title),
                const SizedBox(width: 8),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: MooviGradient.end,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(doc.actionIcon, color: Colors.white, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: TextButton(
                onPressed: uploading ? null : onPressed,
                style: TextButton.styleFrom(
                  backgroundColor: MooviGradient.card,
                  disabledBackgroundColor: MooviGradient.card,
                  foregroundColor: _ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _ButtonContent(
                  label: doc.actionLabel,
                  uploading: uploading,
                  color: _ink,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Disposition compacte (maquette 19)
    final verified = status == DocStatus.verified;
    final missing = status == DocStatus.missing;

    final Color bg;
    final Color fg;
    if (verified) {
      bg = Colors.white.withValues(alpha: 0.5);
      fg = _ink.withValues(alpha: 0.35);
    } else if (missing) {
      bg = MooviGradient.end;
      fg = Colors.white;
    } else {
      bg = Colors.white;
      fg = _ink;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: missing ? Colors.white : MooviGradient.card,
        borderRadius: BorderRadius.circular(26),
        border: status == DocStatus.pending
            ? Border.all(color: const Color(0xFFFFD4AE), width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          iconBox,
          const SizedBox(width: 14),
          Expanded(child: title),
          const SizedBox(width: 10),
          SizedBox(
            width: 124,
            height: 48,
            child: TextButton(
              // Une pièce vérifiée ne peut plus être remplacée.
              onPressed: verified || uploading ? null : onPressed,
              style: TextButton.styleFrom(
                backgroundColor: bg,
                disabledBackgroundColor: bg,
                foregroundColor: fg,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _ButtonContent(
                label: doc.actionLabel,
                uploading: uploading,
                color: fg,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.uploading,
    required this.color,
    required this.fontSize,
  });

  final String label;
  final bool uploading;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (uploading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          const SizedBox(width: 8),
          Text('Envoi…',
              style: TextStyle(
                  fontSize: fontSize, fontWeight: FontWeight.w600, color: color)),
        ],
      );
    }
    return Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: fontSize,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});
  final DocStatus status;

  @override
  Widget build(BuildContext context) {
    final (IconData? icon, Color color, String label) = switch (status) {
      DocStatus.verified => (Icons.check_circle_rounded, _green, 'VÉRIFIÉ'),
      DocStatus.pending => (Icons.schedule_rounded, _amber, 'EN ATTENTE'),
      DocStatus.rejected => (Icons.error_rounded, _red, 'REFUSÉ'),
      DocStatus.missing => (null, _salmon, 'NON TÉLÉCHARGÉ'),
    };

    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Bouton du bas
// -----------------------------------------------------------------------------

class _BottomButton extends StatelessWidget {
  const _BottomButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final fg = enabled ? MooviGradient.end : Colors.white.withValues(alpha: 0.75);

    return SizedBox(
      width: double.infinity,
      height: 62,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.35),
          foregroundColor: fg,
          disabledForegroundColor: fg,
          elevation: enabled ? 6 : 0,
          shadowColor: Colors.black26,
          shape: const StadiumBorder(),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: MooviGradient.end),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(icon, size: 22),
                ],
              ),
      ),
    );
  }
}
