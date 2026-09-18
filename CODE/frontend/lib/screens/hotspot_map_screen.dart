import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/disease_kb.dart';
import '../model/district_stat.dart';
import '../services/hotspot_service.dart';
import '../services/location_service.dart';
import '../utils/colors.dart';
import '../utils/risk_colors.dart';

/// District-level outbreak map for Maharashtra.
///
/// Uses OpenStreetMap tiles through flutter_map rather than Google Maps: no
/// API key, no billing account, and no per-load cost, which keeps the whole
/// feature inside the free tier.
///
/// Everything drawn here is aggregated to district level. Individual farm
/// coordinates are rounded before upload and are never plotted, so the map
/// cannot be used to locate a specific farmer's field.
class HotspotMapScreen extends StatefulWidget {
  const HotspotMapScreen({super.key});

  @override
  State<HotspotMapScreen> createState() => _HotspotMapScreenState();
}

class _HotspotMapScreenState extends State<HotspotMapScreen> {
  final MapController _map = MapController();

  /// Centre of Maharashtra, framed so the whole state fits at zoom 6.3.
  static const LatLng _stateCentre = LatLng(19.4, 76.2);

  String? _speciesFilter;
  DistrictStat? _selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Outbreak Map',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'My district',
            icon: const Icon(Icons.my_location_rounded),
            onPressed: _goToMyDistrict,
          ),
        ],
      ),
      body: StreamBuilder<List<DistrictStat>>(
        stream: HotspotService.instance.watchDistricts(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _errorState(snap.error.toString());
          }

          final all = snap.data ?? const <DistrictStat>[];
          final stats = _applyFilter(all);

          return Column(
            children: [
              _filterBar(all),
              Expanded(
                child: Stack(
                  children: [
                    _buildMap(stats),
                    if (stats.isEmpty) _emptyOverlay(),
                    _legend(),
                  ],
                ),
              ),
              if (_selected != null) _detailSheet(_selected!),
            ],
          );
        },
      ),
    );
  }

  List<DistrictStat> _applyFilter(List<DistrictStat> stats) {
    if (_speciesFilter == null) return stats;
    return stats
        .where((s) => (s.bySpecies[_speciesFilter] ?? 0) > 0)
        .toList();
  }

  // --------------------------------------------------------------- map

  Widget _buildMap(List<DistrictStat> stats) {
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _stateCentre,
        initialZoom: 6.3,
        minZoom: 5,
        maxZoom: 11,
        // Keep the viewport on Maharashtra - panning to the Pacific helps
        // nobody and makes the map feel broken.
        cameraConstraint: CameraConstraint.contain(
          bounds: LatLngBounds(
            const LatLng(15.2, 72.2),
            const LatLng(22.5, 81.3),
          ),
        ),
        onTap: (_, __) => setState(() => _selected = null),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.shivam.greenguard',
          maxZoom: 19,
        ),

        // Proportional circles rather than a true choropleth: district
        // boundary polygons would need a GeoJSON topology shipped in assets,
        // and at state zoom a graduated circle reads just as clearly.
        CircleLayer(
          circles: [
            for (final s in stats)
              if (s.hotspotScore > 0)
                CircleMarker(
                  point: LatLng(s.lat, s.lng),
                  // Radius scales with score, floored so a single case is
                  // still visible and tappable.
                  radius: 12 + (s.hotspotScore / 100) * 26,
                  color: RiskColors.forScore(
                    s.hotspotScore,
                  ).withValues(alpha: 0.35),
                  borderColor: RiskColors.forScore(s.hotspotScore),
                  borderStrokeWidth: 2,
                ),
          ],
        ),

        MarkerLayer(
          markers: [
            for (final s in stats)
              Marker(
                point: LatLng(s.lat, s.lng),
                width: 92,
                height: 46,
                child: GestureDetector(
                  onTap: () => setState(() => _selected = s),
                  child: _districtPin(s),
                ),
              ),
          ],
        ),

        // OSM's tile usage policy requires visible attribution.
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }

  Widget _districtPin(DistrictStat s) {
    final color = RiskColors.forScore(s.hotspotScore);
    final selected = _selected?.district == s.district;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color, width: 1.4),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (s.hasNotifiableDisease) ...[
                Icon(
                  Icons.priority_high_rounded,
                  size: 11,
                  color: selected ? Colors.white : color,
                ),
                const SizedBox(width: 1),
              ],
              Text(
                '${s.diseaseCases}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
        Text(
          s.district,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
            shadows: const [
              Shadow(color: Colors.white, blurRadius: 3),
              Shadow(color: Colors.white, blurRadius: 3),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ chrome

  Widget _filterBar(List<DistrictStat> all) {
    final species = <String>{};
    for (final s in all) {
      species.addAll(s.bySpecies.keys);
    }
    final sorted = species.toList()..sort();

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        children: [
          _chip('All crops', _speciesFilter == null, () {
            setState(() => _speciesFilter = null);
          }),
          for (final sp in sorted)
            _chip(sp, _speciesFilter == sp, () {
              setState(
                () => _speciesFilter = _speciesFilter == sp ? null : sp,
              );
            }),
        ],
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 7),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    ),
  );

  Widget _legend() => Positioned(
    left: 12,
    bottom: 12,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'OUTBREAK LEVEL',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          _legendRow(RiskColors.severe, 'Severe'),
          _legendRow(RiskColors.high, 'High'),
          _legendRow(RiskColors.moderate, 'Moderate'),
          _legendRow(RiskColors.low, 'Low'),
          const SizedBox(height: 4),
          const Row(
            children: [
              Icon(Icons.priority_high_rounded, size: 11, color: Colors.black54),
              SizedBox(width: 3),
              Text(
                'Notifiable disease',
                style: TextStyle(fontSize: 9.5, color: Colors.black54),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _legendRow(Color c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    ),
  );

  // ------------------------------------------------------- detail sheet

  Widget _detailSheet(DistrictStat s) {
    final ranked = s.byDisease.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 290),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Color(0x1A000000), blurRadius: 14, offset: Offset(0, -3)),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.district,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text(
                        s.region,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _selected = null),
                ),
              ],
            ),
            const SizedBox(height: 6),

            Row(
              children: [
                _stat('${s.diseaseCases}', 'cases'),
                _stat('${s.totalScans}', 'scans'),
                _stat(
                  '${(s.infectionRate * 100).round()}%',
                  'infection rate',
                ),
              ],
            ),
            const SizedBox(height: 14),

            // An officer must be able to tell "no disease" from "nobody has
            // scanned here recently".
            Row(
              children: [
                Icon(
                  s.isActive ? Icons.schedule_rounded : Icons.history_toggle_off,
                  size: 14,
                  color: AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    s.lastReportedAt == null
                        ? 'No reports from this district yet'
                        : s.daysSinceLastReport == 0
                        ? 'Last report today'
                        : 'Last report ${s.daysSinceLastReport} '
                              '${s.daysSinceLastReport == 1 ? "day" : "days"} ago'
                              '${s.isActive ? "" : " - data may be stale"}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),

            if (s.isDemo) ...[
              const SizedBox(height: 10),
              _demoTag(),
            ],

            const SizedBox(height: 14),
            if (ranked.isNotEmpty) ...[
              const Text(
                'REPORTED DISEASES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              ...ranked.map((e) => _diseaseRow(e.key, e.value, s.diseaseCases)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _diseaseRow(String key, int count, int total) {
    DiseaseInfo? info;
    for (final d in DiseaseKb.all) {
      if (d.key == key) {
        info = d;
        break;
      }
    }
    final share = total == 0 ? 0.0 : count / total;
    final color = info == null
        ? RiskColors.unknown
        : RiskColors.forThreat(info.threat);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        info?.commonName ?? key,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    if (info?.notifiable == true) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: RiskColors.surfaceFor(RiskColors.severe),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'NOTIFIABLE',
                          style: TextStyle(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w800,
                            color: RiskColors.severe,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 5,
              backgroundColor: AppColors.surfaceContainer,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  /// Demo rows are labelled wherever they surface. An officer should never
  /// have to wonder whether a number on screen came from a real farmer.
  Widget _demoTag() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: RiskColors.surfaceFor(AppColors.tertiary),
      borderRadius: BorderRadius.circular(7),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.info_outline_rounded, size: 13, color: AppColors.tertiary),
        SizedBox(width: 5),
        Text(
          'Demonstration data, not real reports',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.tertiary,
          ),
        ),
      ],
    ),
  );

  Widget _emptyOverlay() => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.travel_explore_rounded,
              size: 34, color: AppColors.onSurfaceVariant),
          SizedBox(height: 10),
          Text(
            'No reports yet',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 5),
          Text(
            'This map fills in as farmers scan. Every scan you run adds a '
            'point to your district.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _errorState(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 34, color: AppColors.onSurfaceVariant),
          const SizedBox(height: 10),
          const Text(
            'Could not load the outbreak map',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _goToMyDistrict() async {
    final loc = await LocationService.instance.resolve();
    if (loc == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not find your location'),
        ),
      );
      return;
    }
    _map.move(LatLng(loc.district.lat, loc.district.lng), 8.5);
  }
}
