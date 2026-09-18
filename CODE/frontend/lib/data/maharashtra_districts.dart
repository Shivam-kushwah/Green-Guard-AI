/// Maharashtra district reference data.
///
/// Used for three things:
///   * snapping a GPS fix to a district when reverse geocoding is unavailable
///     (offline, or the plugin returns an empty subAdministrativeArea)
///   * placing aggregated hotspot markers on the map
///   * the officer dashboard district filter
///
/// Coordinates are district headquarters / approximate centroids - accurate
/// enough to place a marker, not a survey reference.
library;

import 'dart:math' as math;

/// Maharashtra's six recognised agro-administrative divisions.
enum Region { konkan, westernMaharashtra, northMaharashtra, marathwada, vidarbha }

extension RegionX on Region {
  String get label => switch (this) {
    Region.konkan => 'Konkan',
    Region.westernMaharashtra => 'Western Maharashtra',
    Region.northMaharashtra => 'North Maharashtra',
    Region.marathwada => 'Marathwada',
    Region.vidarbha => 'Vidarbha',
  };
}

class District {
  final String name;
  final double lat;
  final double lng;
  final Region region;

  /// Crops from our supported set that are actually grown here in quantity.
  /// Lets the dashboard flag a report that looks out of place, and lets the
  /// weather screen default to a sensible crop.
  final List<String> majorCrops;

  const District({
    required this.name,
    required this.lat,
    required this.lng,
    required this.region,
    required this.majorCrops,
  });
}

class MaharashtraDistricts {
  MaharashtraDistricts._();

  static const List<District> all = [
    // ----------------------------- Konkan -----------------------------
    District(
      name: 'Mumbai City',
      lat: 18.9388,
      lng: 72.8354,
      region: Region.konkan,
      majorCrops: [],
    ),
    District(
      name: 'Mumbai Suburban',
      lat: 19.1136,
      lng: 72.8697,
      region: Region.konkan,
      majorCrops: [],
    ),
    District(
      name: 'Thane',
      lat: 19.2183,
      lng: 72.9781,
      region: Region.konkan,
      majorCrops: ['SugarCane'],
    ),
    District(
      name: 'Palghar',
      lat: 19.6967,
      lng: 72.7699,
      region: Region.konkan,
      majorCrops: ['SugarCane'],
    ),
    District(
      name: 'Raigad',
      lat: 18.5158,
      lng: 73.1822,
      region: Region.konkan,
      majorCrops: ['SugarCane'],
    ),
    District(
      name: 'Ratnagiri',
      lat: 16.9902,
      lng: 73.3120,
      region: Region.konkan,
      majorCrops: [],
    ),
    District(
      name: 'Sindhudurg',
      lat: 16.1300,
      lng: 73.6800,
      region: Region.konkan,
      majorCrops: [],
    ),

    // ---------------------- Western Maharashtra -----------------------
    // The sugarcane belt - red rot reports here matter most.
    District(
      name: 'Pune',
      lat: 18.5204,
      lng: 73.8567,
      region: Region.westernMaharashtra,
      majorCrops: ['SugarCane', 'Wheat', 'Potato', 'CORN'],
    ),
    District(
      name: 'Satara',
      lat: 17.6805,
      lng: 74.0183,
      region: Region.westernMaharashtra,
      majorCrops: ['SugarCane', 'Wheat', 'CORN'],
    ),
    District(
      name: 'Sangli',
      lat: 16.8524,
      lng: 74.5815,
      region: Region.westernMaharashtra,
      majorCrops: ['SugarCane', 'Wheat', 'CORN'],
    ),
    District(
      name: 'Kolhapur',
      lat: 16.7050,
      lng: 74.2433,
      region: Region.westernMaharashtra,
      majorCrops: ['SugarCane', 'CORN'],
    ),
    District(
      name: 'Solapur',
      lat: 17.6599,
      lng: 75.9064,
      region: Region.westernMaharashtra,
      majorCrops: ['SugarCane', 'Wheat', 'CORN'],
    ),
    District(
      name: 'Ahmednagar',
      lat: 19.0952,
      lng: 74.7496,
      region: Region.westernMaharashtra,
      majorCrops: ['SugarCane', 'Wheat', 'CORN', 'Potato'],
    ),

    // ---------------------- North Maharashtra -------------------------
    District(
      name: 'Nashik',
      lat: 19.9975,
      lng: 73.7898,
      region: Region.northMaharashtra,
      majorCrops: ['Wheat', 'CORN', 'SugarCane', 'Potato'],
    ),
    District(
      name: 'Dhule',
      lat: 20.9042,
      lng: 74.7749,
      region: Region.northMaharashtra,
      majorCrops: ['CORN', 'Wheat'],
    ),
    District(
      name: 'Nandurbar',
      lat: 21.3667,
      lng: 74.2400,
      region: Region.northMaharashtra,
      majorCrops: ['CORN', 'Wheat'],
    ),
    District(
      name: 'Jalgaon',
      lat: 21.0077,
      lng: 75.5626,
      region: Region.northMaharashtra,
      majorCrops: ['CORN', 'Wheat', 'SugarCane'],
    ),

    // ------------------------- Marathwada -----------------------------
    District(
      name: 'Chhatrapati Sambhajinagar',
      lat: 19.8762,
      lng: 75.3433,
      region: Region.marathwada,
      majorCrops: ['CORN', 'Wheat', 'SugarCane'],
    ),
    District(
      name: 'Jalna',
      lat: 19.8410,
      lng: 75.8864,
      region: Region.marathwada,
      majorCrops: ['CORN', 'Wheat'],
    ),
    District(
      name: 'Beed',
      lat: 18.9891,
      lng: 75.7601,
      region: Region.marathwada,
      majorCrops: ['SugarCane', 'Wheat', 'CORN'],
    ),
    District(
      name: 'Latur',
      lat: 18.4088,
      lng: 76.5604,
      region: Region.marathwada,
      majorCrops: ['SugarCane', 'Wheat', 'CORN'],
    ),
    District(
      name: 'Dharashiv',
      lat: 18.1860,
      lng: 76.0419,
      region: Region.marathwada,
      majorCrops: ['SugarCane', 'Wheat'],
    ),
    District(
      name: 'Nanded',
      lat: 19.1383,
      lng: 77.3210,
      region: Region.marathwada,
      majorCrops: ['SugarCane', 'Wheat', 'CORN'],
    ),
    District(
      name: 'Parbhani',
      lat: 19.2704,
      lng: 76.7601,
      region: Region.marathwada,
      majorCrops: ['SugarCane', 'Wheat'],
    ),
    District(
      name: 'Hingoli',
      lat: 19.7173,
      lng: 77.1490,
      region: Region.marathwada,
      majorCrops: ['SugarCane', 'Wheat'],
    ),

    // -------------------------- Vidarbha ------------------------------
    District(
      name: 'Nagpur',
      lat: 21.1458,
      lng: 79.0882,
      region: Region.vidarbha,
      majorCrops: ['CORN', 'Wheat'],
    ),
    District(
      name: 'Wardha',
      lat: 20.7453,
      lng: 78.6022,
      region: Region.vidarbha,
      majorCrops: ['CORN', 'Wheat'],
    ),
    District(
      name: 'Bhandara',
      lat: 21.1666,
      lng: 79.6500,
      region: Region.vidarbha,
      majorCrops: ['Wheat', 'CORN'],
    ),
    District(
      name: 'Gondia',
      lat: 21.4624,
      lng: 80.1961,
      region: Region.vidarbha,
      majorCrops: ['Wheat', 'CORN'],
    ),
    District(
      name: 'Chandrapur',
      lat: 19.9615,
      lng: 79.2961,
      region: Region.vidarbha,
      majorCrops: ['Wheat', 'CORN'],
    ),
    District(
      name: 'Gadchiroli',
      lat: 20.1809,
      lng: 80.0035,
      region: Region.vidarbha,
      majorCrops: ['Wheat'],
    ),
    District(
      name: 'Amravati',
      lat: 20.9374,
      lng: 77.7796,
      region: Region.vidarbha,
      majorCrops: ['Wheat', 'CORN'],
    ),
    District(
      name: 'Akola',
      lat: 20.7096,
      lng: 77.0021,
      region: Region.vidarbha,
      majorCrops: ['Wheat', 'CORN'],
    ),
    District(
      name: 'Washim',
      lat: 20.1112,
      lng: 77.1330,
      region: Region.vidarbha,
      majorCrops: ['Wheat', 'CORN'],
    ),
    District(
      name: 'Buldhana',
      lat: 20.5292,
      lng: 76.1842,
      region: Region.vidarbha,
      majorCrops: ['Wheat', 'CORN'],
    ),
    District(
      name: 'Yavatmal',
      lat: 20.3888,
      lng: 78.1204,
      region: Region.vidarbha,
      majorCrops: ['Wheat', 'CORN'],
    ),
  ];

  static List<String> get names => all.map((d) => d.name).toList();

  static District? byName(String? name) {
    if (name == null || name.isEmpty) return null;
    final needle = _normalise(name);
    for (final d in all) {
      if (_normalise(d.name) == needle) return d;
    }
    // Reverse geocoding often returns decorated forms such as
    // "Pune District" or the pre-rename "Aurangabad".
    for (final d in all) {
      final n = _normalise(d.name);
      if (needle.contains(n) || n.contains(needle)) return d;
    }
    return _renamed[needle];
  }

  /// Districts renamed in 2023 still come back under their old names from
  /// most geocoding providers.
  static final Map<String, District> _renamed = {
    'aurangabad': all.firstWhere(
      (d) => d.name == 'Chhatrapati Sambhajinagar',
    ),
    'osmanabad': all.firstWhere((d) => d.name == 'Dharashiv'),
  };

  /// Nearest district to a coordinate. The fallback when reverse geocoding is
  /// unavailable, which in rural areas is often.
  static District nearest(double lat, double lng) {
    District best = all.first;
    double bestDist = double.infinity;
    for (final d in all) {
      final dist = _haversineKm(lat, lng, d.lat, d.lng);
      if (dist < bestDist) {
        bestDist = dist;
        best = d;
      }
    }
    return best;
  }

  /// True when the point is roughly inside Maharashtra's bounding box. Used to
  /// avoid silently labelling a Gujarat or Karnataka scan as Maharashtra.
  static bool isWithinState(double lat, double lng) =>
      lat >= 15.6 && lat <= 22.1 && lng >= 72.6 && lng <= 80.9;

  static String _normalise(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * math.pi / 180.0;
}
