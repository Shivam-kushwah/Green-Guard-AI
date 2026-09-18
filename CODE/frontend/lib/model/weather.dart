/// One point in the forecast - OpenWeatherMap's free endpoint gives these in
/// 3-hour steps over 5 days (40 slices).
class ForecastSlice {
  final DateTime time;
  final double tempC;
  final double humidity;

  /// Rain volume for this 3-hour block, in mm.
  final double rainMm;

  final double windMs;

  /// Probability of precipitation, 0-1.
  final double pop;

  final String condition;
  final String icon;

  const ForecastSlice({
    required this.time,
    required this.tempC,
    required this.humidity,
    required this.rainMm,
    required this.windMs,
    required this.pop,
    required this.condition,
    required this.icon,
  });

  /// Each slice covers a 3-hour block.
  static const int hoursCovered = 3;

  factory ForecastSlice.fromJson(Map<String, dynamic> j) {
    final main = (j['main'] as Map).cast<String, dynamic>();
    final weather = (j['weather'] as List?)?.cast<Map>() ?? const [];
    final rain = (j['rain'] as Map?)?.cast<String, dynamic>();
    final wind = (j['wind'] as Map?)?.cast<String, dynamic>();

    return ForecastSlice(
      time: DateTime.fromMillisecondsSinceEpoch(
        ((j['dt'] as num).toInt()) * 1000,
      ),
      tempC: (main['temp'] as num).toDouble(),
      humidity: (main['humidity'] as num).toDouble(),
      rainMm: (rain?['3h'] as num?)?.toDouble() ?? 0,
      windMs: (wind?['speed'] as num?)?.toDouble() ?? 0,
      pop: (j['pop'] as num?)?.toDouble() ?? 0,
      condition: weather.isEmpty ? '' : (weather.first['main'] as String? ?? ''),
      icon: weather.isEmpty ? '' : (weather.first['icon'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toCache() => {
    'dt': time.millisecondsSinceEpoch ~/ 1000,
    'main': {'temp': tempC, 'humidity': humidity},
    'rain': {'3h': rainMm},
    'wind': {'speed': windMs},
    'pop': pop,
    'weather': [
      {'main': condition, 'icon': icon},
    ],
  };
}

/// Conditions right now.
class CurrentWeather {
  final double tempC;
  final double feelsLikeC;
  final double humidity;
  final double windMs;
  final String condition;
  final String description;
  final String icon;
  final String placeName;
  final DateTime observedAt;

  const CurrentWeather({
    required this.tempC,
    required this.feelsLikeC,
    required this.humidity,
    required this.windMs,
    required this.condition,
    required this.description,
    required this.icon,
    required this.placeName,
    required this.observedAt,
  });

  factory CurrentWeather.fromJson(Map<String, dynamic> j) {
    final main = (j['main'] as Map).cast<String, dynamic>();
    final weather = (j['weather'] as List?)?.cast<Map>() ?? const [];
    final wind = (j['wind'] as Map?)?.cast<String, dynamic>();

    return CurrentWeather(
      tempC: (main['temp'] as num).toDouble(),
      feelsLikeC: (main['feels_like'] as num?)?.toDouble() ??
          (main['temp'] as num).toDouble(),
      humidity: (main['humidity'] as num).toDouble(),
      windMs: (wind?['speed'] as num?)?.toDouble() ?? 0,
      condition: weather.isEmpty ? '' : (weather.first['main'] as String? ?? ''),
      description: weather.isEmpty
          ? ''
          : (weather.first['description'] as String? ?? ''),
      icon: weather.isEmpty ? '' : (weather.first['icon'] as String? ?? ''),
      placeName: (j['name'] as String?) ?? '',
      observedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toCache() => {
    'main': {'temp': tempC, 'feels_like': feelsLikeC, 'humidity': humidity},
    'wind': {'speed': windMs},
    'weather': [
      {'main': condition, 'description': description, 'icon': icon},
    ],
    'name': placeName,
  };
}

/// Everything the risk engine needs, plus provenance so the UI can be honest
/// about whether the farmer is looking at live or stale data.
class WeatherBundle {
  final CurrentWeather current;
  final List<ForecastSlice> forecast;
  final DateTime fetchedAt;

  /// True when served from disk because the network was unavailable.
  final bool fromCache;

  const WeatherBundle({
    required this.current,
    required this.forecast,
    required this.fetchedAt,
    this.fromCache = false,
  });

  Duration get age => DateTime.now().difference(fetchedAt);

  /// Stale enough that the UI should say so rather than present it as current.
  bool get isStale => age > const Duration(hours: 3);
}
