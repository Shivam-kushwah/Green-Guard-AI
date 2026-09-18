import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../data/maharashtra_districts.dart';

/// A resolved farm location.
class FarmLocation {
  /// Full-precision coordinates. Stay on the device - used for the weather
  /// lookup only, never written to a public document.
  final double lat;
  final double lng;

  final District district;

  /// True when this came from a live GPS fix rather than a cached value or a
  /// manual district pick. The UI should say so rather than imply precision
  /// it does not have.
  final bool isLiveFix;

  const FarmLocation({
    required this.lat,
    required this.lng,
    required this.district,
    required this.isLiveFix,
  });

  /// Coordinates coarsened for anything that will be publicly readable.
  /// 2 decimal places is roughly 1.1 km - enough to place a case in the right
  /// taluka, not enough to identify whose field it is.
  double get publicLat => _round(lat);
  double get publicLng => _round(lng);

  static double _round(double v) {
    final f = _pow10(AppConfig.publicCoordPrecision);
    return (v * f).roundToDouble() / f;
  }

  static double _pow10(int n) {
    var r = 1.0;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }
}

/// Why a location request failed, so the UI can offer the right remedy
/// (open settings vs. pick a district manually) instead of a generic error.
enum LocationFailure { serviceDisabled, permissionDenied, permanentlyDenied, timeout, outsideState }

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  static const _kLat = 'gg_last_lat';
  static const _kLng = 'gg_last_lng';
  static const _kDistrict = 'gg_last_district';

  FarmLocation? _cached;
  LocationFailure? lastFailure;

  /// Best-effort location.
  ///
  /// Order of preference: live GPS fix -> value cached from a previous
  /// session -> null. Returning a cached fix matters because a farmer standing
  /// in a field with no signal should still get a weather advisory for roughly
  /// the right place rather than a blank screen.
  Future<FarmLocation?> resolve({bool forceRefresh = false}) async {
    if (_cached != null && !forceRefresh) return _cached;

    final live = await _tryLiveFix();
    if (live != null) {
      _cached = live;
      await _persist(live);
      return live;
    }

    final stored = await _loadCached();
    if (stored != null) _cached = stored;
    return stored;
  }

  Future<FarmLocation?> _tryLiveFix() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        lastFailure = LocationFailure.serviceDisabled;
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        lastFailure = LocationFailure.permanentlyDenied;
        return null;
      }
      if (permission == LocationPermission.denied) {
        lastFailure = LocationFailure.permissionDenied;
        return null;
      }

      // Medium accuracy is plenty for a district-level product and gets a fix
      // far faster under tree cover than best-accuracy would.
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );

      if (!MaharashtraDistricts.isWithinState(pos.latitude, pos.longitude)) {
        // Still usable for weather, but we must not file it as a Maharashtra
        // case and skew the state dashboard.
        lastFailure = LocationFailure.outsideState;
      }

      final district = await _resolveDistrict(pos.latitude, pos.longitude);
      lastFailure = null;
      return FarmLocation(
        lat: pos.latitude,
        lng: pos.longitude,
        district: district,
        isLiveFix: true,
      );
    } catch (_) {
      lastFailure = LocationFailure.timeout;
      return null;
    }
  }

  /// Reverse geocode to a district, falling back to nearest-centroid.
  ///
  /// The plugin call needs network and frequently returns an empty
  /// subAdministrativeArea in rural India, so the geometric fallback is the
  /// common path rather than the exceptional one.
  Future<District> _resolveDistrict(double lat, double lng) async {
    try {
      final places = await placemarkFromCoordinates(lat, lng);
      for (final p in places) {
        final match =
            MaharashtraDistricts.byName(p.subAdministrativeArea) ??
            MaharashtraDistricts.byName(p.locality);
        if (match != null) return match;
      }
    } catch (_) {
      // Fall through to the geometric match.
    }
    return MaharashtraDistricts.nearest(lat, lng);
  }

  /// Manual override for farmers who deny location or have no GPS fix.
  Future<FarmLocation> setDistrictManually(District district) async {
    final loc = FarmLocation(
      lat: district.lat,
      lng: district.lng,
      district: district,
      isLiveFix: false,
    );
    _cached = loc;
    await _persist(loc);
    return loc;
  }

  Future<void> _persist(FarmLocation loc) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kLat, loc.lat);
    await prefs.setDouble(_kLng, loc.lng);
    await prefs.setString(_kDistrict, loc.district.name);
  }

  Future<FarmLocation?> _loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_kLat);
    final lng = prefs.getDouble(_kLng);
    final name = prefs.getString(_kDistrict);
    if (lat == null || lng == null) return null;

    return FarmLocation(
      lat: lat,
      lng: lng,
      district:
          MaharashtraDistricts.byName(name) ??
          MaharashtraDistricts.nearest(lat, lng),
      isLiveFix: false,
    );
  }

  Future<void> openSettings() => Geolocator.openLocationSettings();
}
