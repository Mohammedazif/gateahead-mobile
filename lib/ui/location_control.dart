import "package:flutter/material.dart";

import "../rail_controller.dart";
import "../theme.dart";
import "city_search.dart";

Future<void> showLocationSearch(
  BuildContext context,
  RailController rail,
  VoidCallback onLocate,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: RailColors.of(context).sheet,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        0,
        22,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Find a crossing",
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: "Close search",
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                "Search a city, use your location, or tap a point on the map.",
              ),
              const SizedBox(height: 20),
              CitySearch(
                api: rail.api,
                onPick: (city) {
                  Navigator.pop(context);
                  rail.openCity(
                    "${city.name}, ${city.state}",
                    city.lat,
                    city.lon,
                  );
                },
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: rail.locating
                    ? null
                    : () {
                        Navigator.pop(context);
                        onLocate();
                      },
                icon: const Icon(Icons.my_location, size: 18),
                label: const Text("Use my location"),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class LocationControl extends StatelessWidget {
  const LocationControl({
    super.key,
    required this.rail,
    required this.onLocate,
  });
  final RailController rail;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    final colors = RailColors.of(context);
    return Material(
      color: colors.sheet,
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => showLocationSearch(context, rail, onLocate),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                child: Row(
                  children: [
                    Icon(Icons.search, color: colors.accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        rail.placeLabel ?? "Choose a place",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right, color: colors.muted, size: 18),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: rail.locating
                ? "Finding your location"
                : "Use my location",
            onPressed: rail.locating ? null : onLocate,
            icon: const Icon(Icons.my_location, size: 20),
          ),
        ],
      ),
    );
  }
}
