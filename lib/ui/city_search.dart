import "dart:async";

import "package:flutter/material.dart";

import "../api.dart";
import "../theme.dart";

class CitySearch extends StatefulWidget {
  const CitySearch({super.key, required this.api, required this.onPick});

  final RailApi api;
  final ValueChanged<CityHit> onPick;

  @override
  State<CitySearch> createState() => _CitySearchState();
}

class _CitySearchState extends State<CitySearch> {
  final TextEditingController _query = TextEditingController();
  Timer? _timer;
  int _ticket = 0;
  List<CityHit> _hits = const [];
  String? _note;
  bool _failed = false;

  @override
  void dispose() {
    _timer?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _timer?.cancel();
    final trimmed = value.trim();
    final ticket = ++_ticket;
    setState(() {
      _hits = const [];
      _note = trimmed.length < 2 ? null : "Searching cities…";
      _failed = false;
    });
    if (trimmed.length < 2) return;
    _timer = Timer(const Duration(milliseconds: 160), () {
      unawaited(_lookup(trimmed, ticket));
    });
  }

  Future<void> _lookup(String query, int ticket) async {
    try {
      final hits = await widget.api.cities(query);
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _hits = hits;
        _failed = false;
        _note = hits.isEmpty ? "No Indian city matches that." : null;
      });
    } catch (_) {
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _hits = const [];
        _failed = true;
        _note = "City search did not load.";
      });
    }
  }

  void _submit(String raw) {
    final query = raw.trim();
    if (query.length < 2) return;
    if (_hits.length == 1) {
      _pick(_hits.single);
      return;
    }
    final exact = _hits.where(
      (city) => city.name.toLowerCase() == query.toLowerCase(),
    );
    if (exact.length == 1) {
      _pick(exact.single);
    } else if (_timer?.isActive == true || _failed) {
      _timer?.cancel();
      final ticket = ++_ticket;
      setState(() {
        _failed = false;
        _note = "Searching cities…";
      });
      unawaited(_lookup(query, ticket));
    }
  }

  void _pick(CityHit city) {
    if (!_hits.contains(city)) return;
    _timer?.cancel();
    _ticket += 1;
    _query.clear();
    setState(() {
      _hits = const [];
      _note = null;
      _failed = false;
    });
    widget.onPick(city);
  }

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _query,
          onChanged: _changed,
          onSubmitted: _submit,
          style: text.bodyLarge,
          cursorColor: colors.amber,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: "Search an Indian city",
            hintStyle: text.bodyLarge?.copyWith(color: colors.muted),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide(color: colors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide(color: colors.amber, width: 1.5),
            ),
          ),
        ),
        if (_hits.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final city in _hits)
            TextButton(
              onPressed: () => _pick(city),
              style: TextButton.styleFrom(
                foregroundColor: colors.ink,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(city.name, style: text.bodyLarge),
                  if (city.state.isNotEmpty)
                    Text(
                      city.state,
                      style: text.bodyMedium?.copyWith(color: colors.muted),
                    ),
                ],
              ),
            ),
        ],
        if (_note != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _note!,
              style: text.bodyMedium?.copyWith(
                color: _failed ? colors.warn : colors.muted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
