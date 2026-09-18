import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../model/weather.dart';

/// Why a weather fetch failed, so the UI can say something useful instead of
/// a generic error.
enum WeatherError { noApiKey, offline, rateLimited, badKey, serverError }

class WeatherException implements Exception {
  final WeatherError kind;
  final String message;
  const WeatherException(this.kind, this.message);

  @override
  String toString() => message;
}

/// OpenWeatherMap client.
///
/// Uses the two endpoints that are genuinely free and need no card on file:
/// `/weather` (current conditions) and `/forecast` (5 days at 3-hour steps).
/// One Call 3.0 would give hourly data and would be a better fit for the risk
/// engine, but it requires a payment method even inside its free allowance.
///
/// Results are cached on disk. That is not a performance nicety - a farmer
/// standing in a field with no signal should still see this morning's advisory
/// rather than an error screen.
class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  static const _kCache = 'gg_weather_cache';
  static const _kCacheAt = 'gg_weather_cache_at';
  static const _kCacheLat = 'gg_weather_cache_lat';
  static const _kCacheLng = 'gg_weather_cache_lng';

  /// Below this age we reuse the cache rather than calling out again. The
  /// forecast itself only refreshes every few hours upstream, so a shorter TTL
  /// would burn quota without telling the farmer anything new.
  static const Duration cacheTtl = Duration(hours: 1);

  /// Distance beyond which a cached bundle is treated as being for somewhere
  /// else. Roughly 10 km.
  static const double _cacheRadiusDeg = 0.1;

  WeatherBundle? _memory;

  /// Coordinates the in-memory bundle was fetched for. Without these the
  /// memory cache would happily serve one farm's forecast to another.
  double? _memoryLat;
  double? _memoryLng;

  /// Fetch current + forecast for a coordinate.
  ///
  /// Falls back to cache on any network failure, and only throws when there is
  /// no cache to fall back on.
  Future<WeatherBundle> fetch({
    required double lat,
    required double lng,
    bool forceRefresh = false,
  }) async {
    if (!AppConfig.hasWeatherKey) {
      final cached = await _readCache(lat, lng, ignoreTtl: true);
      if (cached != null) return cached;
      throw const WeatherException(
        WeatherError.noApiKey,
        'No OpenWeatherMap key in this build. Rebuild with '
        '--dart-define=OWM_API_KEY=your_key',
      );
    }

    if (!forceRefresh) {
      if (_memory != null && _memory!.age < cacheTtl && _isNear(lat, lng)) {
        return _memory!;
      }
      final disk = await _readCache(lat, lng);
      if (disk != null) {
        _remember(disk, lat, lng);
        return disk;
      }
    }

    try {
      final results = await Future.wait([
        _get('/weather', lat, lng),
        _get('/forecast', lat, lng),
      ]);

      final current = CurrentWeather.fromJson(results[0]);
      final forecast = ((results[1]['list'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ForecastSlice.fromJson)
          .toList();

      final bundle = WeatherBundle(
        current: current,
        forecast: forecast,
        fetchedAt: DateTime.now(),
      );

      _remember(bundle, lat, lng);
      await _writeCache(bundle, lat, lng);
      return bundle;
    } on WeatherException {
      // A bad key or a quota breach is a real problem the farmer cannot fix,
      // but stale data still beats a blank screen.
      final cached = await _readCache(lat, lng, ignoreTtl: true);
      if (cached != null) return cached;
      rethrow;
    } catch (e) {
      debugPrint('WeatherService network failure: $e');
      final cached = await _readCache(lat, lng, ignoreTtl: true);
      if (cached != null) return cached;
      throw const WeatherException(
        WeatherError.offline,
        'No internet connection and no saved forecast for this area yet.',
      );
    }
  }

  Future<Map<String, dynamic>> _get(
    String path,
    double lat,
    double lng,
  ) async {
    final uri = Uri.parse('${AppConfig.owmBase}$path').replace(
      queryParameters: {
        'lat': lat.toStringAsFixed(4),
        'lon': lng.toStringAsFixed(4),
        'appid': AppConfig.owmApiKey,
        'units': 'metric',
      },
    );

    final res = await http
        .get(uri)
        .timeout(const Duration(seconds: 12));

    switch (res.statusCode) {
      case 200:
        return json.decode(res.body) as Map<String, dynamic>;
      case 401:
        throw const WeatherException(
          WeatherError.badKey,
          'Weather key rejected. A new OpenWeatherMap key can take a couple '
          'of hours to activate.',
        );
      case 429:
        throw const WeatherException(
          WeatherError.rateLimited,
          'Weather service call limit reached. Showing the last saved '
          'forecast.',
        );
      default:
        throw WeatherException(
          WeatherError.serverError,
          'Weather service returned ${res.statusCode}.',
        );
    }
  }

  void _remember(WeatherBundle bundle, double lat, double lng) {
    _memory = bundle;
    _memoryLat = lat;
    _memoryLng = lng;
  }

  /// True when the in-memory bundle was fetched close enough to [lat]/[lng]
  /// to still apply. Weather varies over tens of kilometres, so reusing a
  /// bundle from the next district would quietly give wrong advice.
  bool _isNear(double lat, double lng) {
    if (_memoryLat == null || _memoryLng == null) return false;
    return (_memoryLat! - lat).abs() <= _cacheRadiusDeg &&
        (_memoryLng! - lng).abs() <= _cacheRadiusDeg;
  }

  Future<void> _writeCache(
    WeatherBundle bundle,
    double lat,
    double lng,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kCache,
        json.encode({
          'current': bundle.current.toCache(),
          'forecast': bundle.forecast.map((s) => s.toCache()).toList(),
        }),
      );
      await prefs.setInt(_kCacheAt, DateTime.now().millisecondsSinceEpoch);
      await prefs.setDouble(_kCacheLat, lat);
      await prefs.setDouble(_kCacheLng, lng);
    } catch (e) {
      debugPrint('WeatherService cache write failed: $e');
    }
  }

  Future<WeatherBundle?> _readCache(
    double lat,
    double lng, {
    bool ignoreTtl = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCache);
      final at = prefs.getInt(_kCacheAt);
      if (raw == null || at == null) return null;

      final fetchedAt = DateTime.fromMillisecondsSinceEpoch(at);
      if (!ignoreTtl &&
          DateTime.now().difference(fetchedAt) > cacheTtl) {
        return null;
      }

      // Cached weather for a farm 200 km away is worse than none.
      final cLat = prefs.getDouble(_kCacheLat);
      final cLng = prefs.getDouble(_kCacheLng);
      if (cLat != null && cLng != null) {
        if ((cLat - lat).abs() > _cacheRadiusDeg ||
            (cLng - lng).abs() > _cacheRadiusDeg) {
          return null;
        }
      }

      final map = json.decode(raw) as Map<String, dynamic>;
      return WeatherBundle(
        current: CurrentWeather.fromJson(
          (map['current'] as Map).cast<String, dynamic>(),
        ),
        forecast: ((map['forecast'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ForecastSlice.fromJson)
            .toList(),
        fetchedAt: fetchedAt,
        fromCache: true,
      );
    } catch (e) {
      debugPrint('WeatherService cache read failed: $e');
      return null;
    }
  }
}
