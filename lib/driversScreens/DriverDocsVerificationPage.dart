import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'test/offers_page.dart';

const _monoFont = 'monospace';
const _green = Color(0xFF1FA45B);
const _amber = Color(0xFFFF8F00);

enum DocStatus { verified, pending, rejected, missing }

/// Les 4 cartes affichées. `keys` = clés des fichiers dans `drivers/{uid}.documents`
/// (celles écrites par l'écran Carinfos).
enum DriverDoc {
  vehiclePhotos(
    'Photo du véhicule',
    Icons.directions_car_filled_rounded,
    true,
    ['front', 'left', 'right', 'back', 'interior'],
  ),
  plate("Plaque d'immatriculation", Icons.pin_rounded, true, ['plate']),
  registration('Carte grise', Icons.description_rounded, false, ['registration']),
  license('Permis de conduire', Icons.badge_rounded, false, ['license']);

  const DriverDoc(this.title, this.icon, this.isPhoto, this.keys);
  final String title;
  final IconData icon;
  final bool isPhoto;
  final List<String> keys;
}

/// Statut d'une carte à partir de `documents` dans Firestore.
/// Chaque fichier peut avoir un champ `status` : "verified" | "rejected" | (autre = en attente).
/// Il est à renseigner côté back-office lors de la validation.
DocStatus _statusFor(DriverDoc doc, Map<String, dynamic> documents) {
  final statuses = doc.keys.map((k) {
    final entry = documents[k];
    if (entry is! Map) return DocStatus.missing;
    final s = entry['status'];
    if (s == 'verified') return DocStatus.verified;
    if (s == 'rejected') return DocStatus.rejected;
    return DocStatus.pending;
  }).toList();

  if (statuses.contains(DocStatus.missing)) return DocStatus.missing;
  if (statuses.contains(DocStatus.rejected)) return DocStatus.rejected;
  if (statuses.every((s) => s == DocStatus.verified)) return DocStatus.verified;
  return DocStatus.pending;
}

class DriverVerificationPage extends StatelessWidget {
  const DriverVerificationPage({
    super.key,
    this.onImport,
    this.onContinue,
  });

  /// Appelé quand le chauffeur veut (ré)envoyer un document.
  final ValueChanged<DriverDoc>? onImport;

  /// Appelé au clic sur « Vérification Chauffeur ».
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: Text('Vous devez être connecté.')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('drivers')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Impossible de charger les documents.'));
            }
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            final data = snapshot.data!.data() ?? const <String, dynamic>{};
            final documents =
                (data['documents'] as Map?)?.cast<String, dynamic>() ?? const {};

            final statuses = {
              for (final d in DriverDoc.values) d: _statusFor(d, documents),
            };

            // « complété » = envoyé (vérifié ou en attente de vérification)
            final done = statuses.values
                .where((s) => s == DocStatus.verified || s == DocStatus.pending)
                .length;

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      children: [
                        _ProgressCard(done: done, total: statuses.length),
                        const SizedBox(height: 16),
                        for (final entry in statuses.entries) ...[
                          _DocCard(
                            doc: entry.key,
                            status: entry.value,
                            onImport: onImport == null
                                ? null
                                : () => onImport!(entry.key),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: _VerifyButton(
                    onPressed: onContinue ??
                        () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const OffersPage(),
                            ),
                          );
                        },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Carte de progression
// -----------------------------------------------------------------------------

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : done / total;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cream.withOpacity(0.55),
        borderRadius: BorderRadius.circular(28),
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
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.background,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${(ratio * 100).round()}%',
                  style: const TextStyle(
                    fontFamily: _monoFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: Colors.white,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Icon(Icons.history_rounded, size: 15, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Validation sous 24h',
                style: TextStyle(fontSize: 12.5, color: AppColors.darkBrown),
              ),
            ],
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
    this.onImport,
  });

  final DriverDoc doc;
  final DocStatus status;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final missing = status == DocStatus.missing || status == DocStatus.rejected;
    final pending = status == DocStatus.pending;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: missing ? Colors.transparent : AppColors.cream.withOpacity(0.55),
        borderRadius: BorderRadius.circular(24),
        border: pending
            ? Border.all(color: AppColors.cream, width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: missing ? AppColors.cream.withOpacity(0.7) : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(doc.icon, size: 25, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.title,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppColors.background,
                  ),
                ),
                const SizedBox(height: 6),
                _StatusLabel(status: status),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _ActionButton(doc: doc, status: status, onPressed: onImport),
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});
  final DocStatus status;

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final Color color;
    late final String label;

    switch (status) {
      case DocStatus.verified:
        icon = Icons.check_circle_rounded;
        color = _green;
        label = 'VÉRIFIÉ';
      case DocStatus.pending:
        icon = Icons.schedule_rounded;
        color = AppColors.primary;
        label = 'EN ATTENTE';
      case DocStatus.rejected:
        icon = Icons.error_rounded;
        color = Colors.red;
        label = 'REFUSÉ';
      case DocStatus.missing:
        icon = Icons.radio_button_checked_rounded;
        color = AppColors.grey;
        label = 'NON TÉLÉCHARGÉ';
    }

    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: _monoFont,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.doc,
    required this.status,
    this.onPressed,
  });

  final DriverDoc doc;
  final DocStatus status;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = doc.isPhoto ? 'Ajouter une\nphoto' : 'Importer\ndocument';
    final verified = status == DocStatus.verified;
    final pending = status == DocStatus.pending;

    final Color bg;
    final Color fg;
    if (verified) {
      bg = Colors.white.withOpacity(0.55);
      fg = AppColors.grey;
    } else if (pending) {
      bg = Colors.white;
      fg = AppColors.background;
    } else {
      bg = _amber;
      fg = Colors.white;
    }

    final button = ElevatedButton(
      // Un document vérifié ne peut plus être remplacé
      onPressed: verified ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg,
        disabledForegroundColor: fg,
        elevation: 0,
        fixedSize: const Size(112, 46),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: _monoFont,
          fontSize: 11,
          height: 1.25,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (verified || pending) return button;

    // Ombre orange pour l'action principale
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: _amber.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: button,
    );
  }
}

// -----------------------------------------------------------------------------
// Bouton du bas
// -----------------------------------------------------------------------------

class _VerifyButton extends StatelessWidget {
  const _VerifyButton({this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(31),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const StadiumBorder(),
        ),
        child: const Text(
          'Vérification Chauffeur',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}