/// Central configuration for Green Guard AI.
///
/// Secrets are injected at build time, never committed:
///   flutter run --dart-define=OWM_API_KEY=xxxxxxxx
///
/// NOTE: a key compiled into an APK is extractable by anyone who unzips it.
/// That is acceptable for a demo build; before public release the weather
/// call should move behind a proxy so the key never ships to the device.
class AppConfig {
  static const String owmApiKey = String.fromEnvironment(
    'OWM_API_KEY',
    defaultValue: '',
  );

  static bool get hasWeatherKey => owmApiKey.isNotEmpty;

  /// OpenWeatherMap free-tier endpoints (no credit card required).
  static const String owmBase = 'https://api.openweathermap.org/data/2.5';

  /// Public hotspot coordinates are rounded to this many decimal places
  /// before they ever leave the device. 2 dp ~= 1.1 km, which is enough to
  /// place a case in the right taluka but not enough to identify a farm.
  static const int publicCoordPrecision = 2;

  /// Expert review service-level target.
  static const Duration expertSlaWindow = Duration(hours: 24);

  /// Below this model certainty we actively nudge the farmer toward an
  /// expert review instead of presenting the result as settled.
  static const double lowCertaintyThreshold = 70.0;

  /// Longest image edge (px) before upload. A 640px JPEG at q70 lands around
  /// 60-90 KB, which fits inside Firestore's 1 MB document limit as base64
  /// with room to spare. This is what lets us stay on the free Spark plan.
  static const int uploadMaxEdge = 640;
  static const int uploadJpegQuality = 70;
}
