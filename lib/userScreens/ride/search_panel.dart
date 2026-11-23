import 'dart:async';

import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/material.dart';

import '../place_search_controller.dart';
import '../places_service.dart';
import 'ride_style.dart';
import 'saved_places_service.dart';

/// Carte de recherche (maquette 10) : départ / destination reliés par un
/// pointillé, bouton « choisir sur la carte », lieux enregistrés, récents.
class RideSearchPanel extends StatefulWidget {
  const RideSearchPanel({
    super.key,
    required this.search,
    required this.onSuggestionTap,
    required this.onKnownPlaceTap,
    required this.onPickOnMap,
    required this.onClear,
  });

  final PlaceSearchController search;
  final ValueChanged<PlaceSuggestion> onSuggestionTap;
  final ValueChanged<KnownPlace> onKnownPlaceTap;
  final ValueChanged<SearchField> onPickOnMap;
  final ValueChanged<SearchField> onClear;

  @override
  State<RideSearchPanel> createState() => _RideSearchPanelState();
}

class _RideSearchPanelState extends State<RideSearchPanel> {
  static const _fieldHeight = 44.0;
  static const _fieldGap = 18.0;

  bool _savedExpanded = false;
  List<KnownPlace> _saved = const [];
  List<KnownPlace> _recents = const [];
  StreamSubscription<List<KnownPlace>>? _savedSub;
  StreamSubscription<List<KnownPlace>>? _recentSub;

  @override
  void initState() {
    super.initState();
    _savedSub = SavedPlacesService.instance.savedPlaces().listen(
          (v) => mounted ? setState(() => _saved = v) : null,
          onError: (e) => debugPrint('Lieux enregistrés : $e'),
        );
    _recentSub = SavedPlacesService.instance.recentDestinations().listen(
          (v) => mounted ? setState(() => _recents = v) : null,
          onError: (e) => debugPrint('Destinations récentes : $e'),
        );
  }

  @override
  void dispose() {
    _savedSub?.cancel();
    _recentSub?.cancel();
    super.dispose();
  }

  PlaceSearchController get _search => widget.search;

  KnownPlace? get _savedMatchForDestination {
    final dest = _search.destination;
    if (dest == null) return null;
    for (final p in _saved) {
      if (p.isNear(dest)) return p;
    }
    return null;
  }

  Future<void> _toggleSaveDestination() async {
    final dest = _search.destination;
    final messenger = ScaffoldMessenger.of(context);
    if (dest == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Choisissez d\'abord une destination à enregistrer.'),
      ));
      return;
    }
    final existing = _savedMatchForDestination;
    try {
      if (existing?.id != null) {
        await SavedPlacesService.instance.deletePlace(existing!.id!);
        messenger.showSnackBar(const SnackBar(
          content: Text('Lieu retiré de vos lieux enregistrés.'),
        ));
        return;
      }
      final address = _search.destinationText.text.trim();
      final label = await _askLabel(shortAddress(address));
      if (label == null) return;
      await SavedPlacesService.instance.savePlace(
        label: label,
        address: address,
        position: dest,
      );
      if (!mounted) return;
      setState(() => _savedExpanded = true);
      messenger.showSnackBar(const SnackBar(content: Text('Lieu enregistré.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Impossible d\'enregistrer ce lieu : $e'),
      ));
    }
  }

  Future<String?> _askLabel(String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enregistrer ce lieu'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom (ex. Maison, Travail)',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? initial : v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              final v = ctrl.text.trim();
              Navigator.pop(ctx, v.isEmpty ? initial : v);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: ListenableBuilder(
          listenable: _search,
          builder: (_, __) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFields(),
              const SizedBox(height: 14),
              const Divider(height: 1, thickness: 1.5, color: RideColors.orange),
              _buildSavedHeader(),
              const Divider(height: 1, thickness: 1.5, color: RideColors.orange),
              Flexible(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFields() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 18,
          height: _fieldHeight * 2 + _fieldGap,
          child: Column(
            children: [
              SizedBox(
                height: _fieldHeight,
                child: Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: RideColors.orange, width: 2),
                    ),
                    child: Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Expanded(
                child: DottedLine(
                  direction: Axis.vertical,
                  lineThickness: 1.5,
                  dashLength: 3,
                  dashGapLength: 3,
                  dashColor: Colors.grey,
                ),
              ),
              const SizedBox(
                height: _fieldHeight,
                child: Center(
                  child: Icon(Icons.location_on, size: 20, color: RideColors.brown),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            children: [
              _field(SearchField.origin, 'Point de départ'),
              const SizedBox(height: _fieldGap),
              _field(SearchField.destination, 'Où allez-vous ?'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(SearchField field, String hint) {
    final text = _search.textFor(field);
    final isDestination = field == SearchField.destination;

    return Container(
      height: _fieldHeight,
      decoration: BoxDecoration(
        color: RideColors.orange,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: RideColors.orange.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: text,
              focusNode: _search.focusFor(field),
              onChanged: (t) => _search.onQueryChanged(field, t),
              textInputAction: TextInputAction.search,
              cursorColor: Colors.white,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                ),
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: text,
            builder: (_, value, __) => value.text.isEmpty
                ? const SizedBox.shrink()
                : GestureDetector(
                    onTap: () => widget.onClear(field),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.close_rounded, color: Colors.white, size: 18),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(4),
            child: Tooltip(
              message: 'Choisir sur la carte',
              child: InkWell(
                onTap: () => widget.onPickOnMap(field),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDestination
                        ? const Color(0xFFF07A00)
                        : Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: Icon(
                    isDestination ? Icons.location_on : Icons.location_on_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedHeader() {
    final saved = _savedMatchForDestination != null;
    final hasDestination = _search.destination != null;
    return InkWell(
      onTap: () => setState(() => _savedExpanded = !_savedExpanded),
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            const Icon(Icons.bookmark_border_rounded, color: RideColors.orange, size: 26),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Lieux enregistrés',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
            ),
            if (hasDestination)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: saved
                    ? 'Retirer des lieux enregistrés'
                    : 'Enregistrer la destination',
                onPressed: _toggleSaveDestination,
                icon: Icon(
                  saved ? Icons.star_rounded : Icons.star_border_rounded,
                  color: RideColors.orange,
                ),
              ),
            AnimatedRotation(
              turns: _savedExpanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_search.error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(_search.error!, style: const TextStyle(color: Colors.red)),
      );
    }

    final suggestions = _search.suggestions;
    if (suggestions.isNotEmpty) {
      return ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.only(top: 6),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder: (_, i) {
          final s = suggestions[i];
          return _PlaceRow(
            icon: Icons.location_on_outlined,
            title: s.mainText,
            subtitle: s.secondaryText,
            onTap: () => widget.onSuggestionTap(s),
          );
        },
      );
    }

    if (_search.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: RideColors.orange),
          ),
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(top: 6),
      children: [
        if (_savedExpanded) ...[
          if (_saved.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Aucun lieu enregistré. Choisissez une destination puis touchez l\'étoile.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
            ),
          for (final p in _saved)
            _PlaceRow(
              icon: Icons.bookmark_rounded,
              title: p.label,
              subtitle: p.address == p.label ? '' : p.address,
              onTap: () => widget.onKnownPlaceTap(p),
              onLongPress: p.id == null
                  ? null
                  : () => _confirmDelete(p),
            ),
          const Divider(height: 16),
        ],
        if (_recents.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              'Récents',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          for (final p in _recents)
            _PlaceRow(
              icon: Icons.access_time_rounded,
              title: p.label,
              subtitle: p.address == p.label ? '' : p.address,
              onTap: () => widget.onKnownPlaceTap(p),
            ),
        ],
      ],
    );
  }

  Future<void> _confirmDelete(KnownPlace p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce lieu ?'),
        content: Text(p.label),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true && p.id != null) {
      await SavedPlacesService.instance.deletePlace(p.id!);
    }
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 24, color: Colors.black87),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      color: RideColors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
