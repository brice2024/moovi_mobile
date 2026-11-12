import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────────────────────────────────────

const Color kPrimary = Color(0xFF1E5EFF); // ← remplace par la couleur MOOVI

/// Libellés et ordre d'affichage des documents.
/// La clé = id du document Firestore dans drivers/{uid}/documents/{clé}.
const Map<String, String> kDocumentLabels = {
  'permis': 'Permis de conduire',
  'carte_grise': 'Carte grise',
  'photo_face': 'Voiture – face',
  'photo_profil_gauche': 'Voiture – profil gauche',
  'photo_profil_droit': 'Voiture – profil droit',
  'photo_arriere': 'Voiture – arrière',
  'photo_interieur': 'Voiture – intérieur',
  'photo_plaque': 'Plaque d\'immatriculation',
};
 
// ─────────────────────────────────────────────────────────────────────────────
// Modèle
// ─────────────────────────────────────────────────────────────────────────────

enum DocumentStatus {
  pending('En cours de traitement', 'En cours', Color(0xFFF59E0B), Icons.hourglass_top_rounded),
  approved('Validé', 'Validés', Color(0xFF16A34A), Icons.check_circle_rounded),
  rejected('Rejeté', 'Rejetés', Color(0xFFDC2626), Icons.cancel_rounded);

  const DocumentStatus(this.label, this.pluralLabel, this.color, this.icon);

  final String label;
  final String pluralLabel;
  final Color color;
  final IconData icon;

  static DocumentStatus fromString(String? value) => DocumentStatus.values
      .firstWhere((s) => s.name == value, orElse: () => DocumentStatus.pending);
}

class DriverDocument {
  const DriverDocument({
    required this.type,
    required this.title,
    required this.status,
    this.url,
    this.rejectionReason,
    this.submittedAt,
    this.reviewedAt,
  });

  final String type;
  final String title;
  final DocumentStatus status;
  final String? url;
  final String? rejectionReason;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  factory DriverDocument.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? {};
    return DriverDocument(
      type: snap.id,
      title: data['title'] as String? ?? kDocumentLabels[snap.id] ?? snap.id,
      status: DocumentStatus.fromString(data['status'] as String?),
      url: data['url'] as String?,
      rejectionReason: data['rejectionReason'] as String?,
      submittedAt: (data['submittedAt'] as Timestamp?)?.toDate(),
      reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lecture Firestore
// ─────────────────────────────────────────────────────────────────────────────

class DriverDocumentRepository {
  DriverDocumentRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  /// Flux temps réel des documents du chauffeur connecté.
  Stream<List<DriverDocument>> watchDocuments() {
    final uid = _auth.currentUser!.uid;
    final order = kDocumentLabels.keys.toList();

    return _db
        .collection('drivers')
        .doc(uid)
        .collection('documents')
        .snapshots()
        .map((snap) {
      final docs = snap.docs.map(DriverDocument.fromFirestore).toList();
      int rank(String type) {
        final i = order.indexOf(type);
        return i == -1 ? order.length : i;
      }

      docs.sort((a, b) => rank(a.type).compareTo(rank(b.type)));
      return docs;
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class DocumentStatusPage extends StatefulWidget {
  const DocumentStatusPage({super.key, this.repository});

  final DriverDocumentRepository? repository;

  @override
  State<DocumentStatusPage> createState() => _DocumentStatusPageState();
}

class _DocumentStatusPageState extends State<DocumentStatusPage> {
  late final Stream<List<DriverDocument>> _stream =
  (widget.repository ?? DriverDocumentRepository()).watchDocuments();

  DocumentStatus? _filter; // null = Tous

  void _openPreview(DriverDocument doc) {
    if (doc.url == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _DocumentPreview(title: doc.title, url: doc.url!),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Mes documents', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<List<DriverDocument>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _CenteredMessage(
              icon: Icons.error_outline,
              text: 'Impossible de charger tes documents.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: kPrimary));
          }

          final docs = snapshot.data!;
          if (docs.isEmpty) {
            return const _CenteredMessage(
              icon: Icons.folder_open_outlined,
              text: 'Aucun document trouvé.',
            );
          }

          final counts = {
            for (final s in DocumentStatus.values) s: docs.where((d) => d.status == s).length,
          };
          final visible = _filter == null ? docs : docs.where((d) => d.status == _filter).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _SummaryCard(counts: counts, total: docs.length),
              const SizedBox(height: 20),
              _FilterBar(
                selected: _filter,
                counts: counts,
                total: docs.length,
                onChanged: (s) => setState(() => _filter = s),
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: _CenteredMessage(
                    icon: Icons.folder_open_outlined,
                    text: 'Aucun document dans cette catégorie.',
                  ),
                )
              else
                ...visible.map((doc) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DocumentCard(doc: doc, onPreview: () => _openPreview(doc)),
                )),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte de synthèse
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.counts, required this.total});

  final Map<DocumentStatus, int> counts;
  final int total;

  @override
  Widget build(BuildContext context) {
    final approved = counts[DocumentStatus.approved]!;
    final rejected = counts[DocumentStatus.rejected]!;

    final (String title, String subtitle, Color color, IconData icon) = switch (true) {
      _ when approved == total => (
      'Compte vérifié',
      'Tous tes documents ont été validés.',
      DocumentStatus.approved.color,
      Icons.verified_rounded,
      ),
      _ when rejected > 0 => (
      'Documents rejetés',
      '$rejected document${rejected > 1 ? 's ont' : ' a'} été rejeté${rejected > 1 ? 's' : ''}. Consulte le motif ci-dessous.',
      DocumentStatus.rejected.color,
      Icons.error_rounded,
      ),
      _ => (
      'Vérification en cours',
      'Nos équipes examinent tes documents, généralement sous 24 à 48 h.',
      DocumentStatus.pending.color,
      Icons.hourglass_top_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Progression', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              Text('$approved / $total validés',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: total == 0 ? 0 : approved / total),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (_, value, __) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                color: DocumentStatus.approved.color,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final s in DocumentStatus.values) ...[
                Expanded(child: _StatTile(status: s, count: counts[s]!)),
                if (s != DocumentStatus.values.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.status, required this.count});

  final DocumentStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text('$count',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: status.color)),
          const SizedBox(height: 2),
          Text(status.pluralLabel, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filtres
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.counts,
    required this.total,
    required this.onChanged,
  });

  final DocumentStatus? selected;
  final Map<DocumentStatus, int> counts;
  final int total;
  final ValueChanged<DocumentStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <(DocumentStatus?, String, int)>[
      (null, 'Tous', total),
      for (final s in DocumentStatus.values) (s, s.pluralLabel, counts[s]!),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (status, label, count) = options[i];
          final isSelected = status == selected;
          return ChoiceChip(
            label: Text('$label ($count)'),
            selected: isSelected,
            showCheckmark: false,
            onSelected: (_) => onChanged(status),
            selectedColor: kPrimary,
            backgroundColor: Colors.white,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            side: BorderSide(color: isSelected ? kPrimary : Colors.grey.shade300),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte document
// ─────────────────────────────────────────────────────────────────────────────

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.doc, required this.onPreview});

  final DriverDocument doc;
  final VoidCallback onPreview;

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String? get _subtitle => switch (doc.status) {
    DocumentStatus.approved when doc.reviewedAt != null => 'Validé le ${_formatDate(doc.reviewedAt!)}',
    DocumentStatus.rejected when doc.reviewedAt != null => 'Rejeté le ${_formatDate(doc.reviewedAt!)}',
    _ when doc.submittedAt != null => 'Envoyé le ${_formatDate(doc.submittedAt!)}',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitle;
    final hasReason =
        doc.status == DocumentStatus.rejected && (doc.rejectionReason?.isNotEmpty ?? false);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: doc.status == DocumentStatus.rejected
              ? doc.status.color.withValues(alpha: 0.4)
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Thumbnail(url: doc.url, onTap: onPreview),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                    const SizedBox(height: 8),
                    _StatusBadge(status: doc.status),
                  ],
                ),
              ),
            ],
          ),
          if (hasReason) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: doc.status.color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: doc.status.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      doc.rejectionReason!,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade800, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final DocumentStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 14, color: status.color),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: status.color),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url, required this.onTap});

  final String? url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.description_outlined, color: Colors.grey.shade400),
    );

    if (url == null) return placeholder;

    return GestureDetector(
      onTap: onTap,
      child: Hero(
        tag: url!,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url!,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) => progress == null ? child : placeholder,
            errorBuilder: (_, __, ___) => placeholder,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Aperçu plein écran
// ─────────────────────────────────────────────────────────────────────────────

class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({required this.title, required this.url});

  final String title;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Hero(tag: url, child: Image.network(url)),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}