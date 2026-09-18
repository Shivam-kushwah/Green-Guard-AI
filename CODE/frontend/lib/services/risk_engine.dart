import '../data/disease_kb.dart';
import '../model/weather.dart';

/// How the risk reads to a farmer.
enum RiskBand { low, moderate, high, severe }

extension RiskBandX on RiskBand {
  String get label => switch (this) {
    RiskBand.low => 'Low',
    RiskBand.moderate => 'Moderate',
    RiskBand.high => 'High',
    RiskBand.severe => 'Severe',
  };

  String get action => switch (this) {
    RiskBand.low => 'Routine scouting is enough.',
    RiskBand.moderate => 'Scout twice this week and keep inputs ready.',
    RiskBand.high => 'Apply protectant cover before the wet spell arrives.',
    RiskBand.severe =>
      'Act now. Conditions are ideal for infection over the next few days.',
  };

  static RiskBand fromScore(double s) {
    if (s >= 70) return RiskBand.severe;
    if (s >= 45) return RiskBand.high;
    if (s >= 20) return RiskBand.moderate;
    return RiskBand.low;
  }
}

/// A stretch of forecast during which a pathogen could establish.
class InfectionEvent {
  final DateTime start;
  final DateTime end;
  final double hours;
  final double meanTemp;
  final double meanHumidity;

  const InfectionEvent({
    required this.start,
    required this.end,
    required this.hours,
    required this.meanTemp,
    required this.meanHumidity,
  });
}

/// Forecast risk for one disease on one crop.
class DiseaseRisk {
  final DiseaseInfo disease;

  /// 0-100. See [RiskEngine.assess] for exactly how this is composed - the
  /// weighting is deliberately simple and inspectable rather than a black box,
  /// because an extension officer has to be able to challenge it.
  final double score;

  final RiskBand band;

  /// Stretches long enough to satisfy the pathogen's sustained-hours need.
  final List<InfectionEvent> events;

  /// Longest favourable stretch found, even if it fell short of the threshold.
  final double peakFavourableHours;

  final double totalRainMm;

  /// Plain-language reasons, for a farmer who wants to know why.
  final List<String> drivers;

  /// Set only for potato late blight, where the Hutton Criteria are the
  /// recognised standard rather than our generic heuristic.
  final bool? huttonCriteriaMet;

  const DiseaseRisk({
    required this.disease,
    required this.score,
    required this.band,
    required this.events,
    required this.peakFavourableHours,
    required this.totalRainMm,
    required this.drivers,
    this.huttonCriteriaMet,
  });

  DateTime? get firstEventStart =>
      events.isEmpty ? null : events.first.start;
}

/// Turns a weather forecast into per-disease outbreak risk.
///
/// HOW THIS WORKS, and what it is not:
///
/// Each disease in the knowledge base carries an [InfectionWindow] - the
/// temperature band, humidity threshold and sustained duration that published
/// extension thresholds say the pathogen needs. We walk the 3-hourly forecast,
/// mark every slice that falls inside the window, and look for unbroken runs
/// long enough to matter. The score combines how many such runs occur, how
/// long the longest one is, how close temperatures sit to the pathogen's
/// optimum, and rainfall.
///
/// The honest limitation: infection is really driven by *leaf wetness*, and no
/// free weather API reports it. We approximate it from relative humidity at or
/// above the pathogen's threshold, which is the standard substitution in
/// extension tools but is an approximation, not a measurement. It will miss
/// dew forming on a clear cold night at moderate RH, and it will overcall a
/// humid but windy day where leaves actually stay dry.
///
/// This is therefore an advisory that tells a farmer when to go and look, not
/// a prediction that disease will occur.
class RiskEngine {
  RiskEngine._();

  /// Weightings. They sum to 1.0 and are stated here rather than buried in the
  /// arithmetic so they can be argued with and tuned against real outbreaks.
  static const double _wEvents = 0.40; // did full infection windows occur
  static const double _wDuration = 0.25; // how long the wettest stretch ran
  static const double _wTemp = 0.20; // how close to the pathogen optimum
  static const double _wRain = 0.15; // free water / splash dispersal

  /// Risk for every disease that affects [species], highest first.
  static List<DiseaseRisk> assessCrop(
    String species,
    List<ForecastSlice> forecast,
  ) {
    final risks = DiseaseKb.forSpecies(species)
        .map((d) => assess(d, forecast))
        .whereType<DiseaseRisk>()
        .toList();
    risks.sort((a, b) => b.score.compareTo(a.score));
    return risks;
  }

  /// Risk across every crop the farmer grows.
  static List<DiseaseRisk> assessCrops(
    List<String> speciesList,
    List<ForecastSlice> forecast,
  ) {
    final all = <DiseaseRisk>[];
    for (final s in speciesList) {
      all.addAll(assessCrop(s, forecast));
    }
    all.sort((a, b) => b.score.compareTo(a.score));
    return all;
  }

  /// Returns null for diseases with no infection window (healthy classes and
  /// anything not yet catalogued).
  static DiseaseRisk? assess(DiseaseInfo disease, List<ForecastSlice> forecast) {
    final window = disease.window;
    if (window == null || forecast.isEmpty) return null;

    // --- mark favourable slices -------------------------------------------
    final favourable = <bool>[];
    final suitability = <double>[];
    for (final s in forecast) {
      final tempFit = window.tempSuitability(s.tempC);
      final humidOk = s.humidity >= window.humidityThreshold;
      favourable.add(tempFit > 0 && humidOk);
      suitability.add(tempFit);
    }

    // --- find unbroken runs -----------------------------------------------
    final events = <InfectionEvent>[];
    var peakHours = 0.0;

    var i = 0;
    while (i < favourable.length) {
      if (!favourable[i]) {
        i++;
        continue;
      }
      final start = i;
      while (i < favourable.length && favourable[i]) {
        i++;
      }
      final runLength = i - start;
      final hours = runLength * ForecastSlice.hoursCovered.toDouble();
      if (hours > peakHours) peakHours = hours;

      if (hours >= window.sustainedHoursNeeded) {
        final slice = forecast.sublist(start, i);
        events.add(
          InfectionEvent(
            start: slice.first.time,
            end: slice.last.time,
            hours: hours,
            meanTemp: _mean(slice.map((s) => s.tempC)),
            meanHumidity: _mean(slice.map((s) => s.humidity)),
          ),
        );
      }
    }

    // --- components --------------------------------------------------------
    // Three or more separate infection windows inside five days is as bad as
    // this scale goes; beyond that the advice does not change.
    final eventScore = (events.length / 3.0).clamp(0.0, 1.0);

    // Twice the required duration is treated as the ceiling - a pathogen
    // needing 6 h saturates at 12 h of continuous favourable conditions.
    final durationScore =
        (peakHours / (window.sustainedHoursNeeded * 2)).clamp(0.0, 1.0);

    // Average temperature fit, counted only over favourable slices so a cold
    // dry week does not dilute a genuinely dangerous warm humid spell.
    final favIdx = [
      for (var k = 0; k < favourable.length; k++)
        if (favourable[k]) k,
    ];
    final tempScore = favIdx.isEmpty
        ? 0.0
        : _mean(favIdx.map((k) => suitability[k]));

    final totalRain = forecast.fold<double>(0, (sum, s) => sum + s.rainMm);
    final double rainScore;
    if (window.rainFavours) {
      // 25 mm across the window is plenty for splash dispersal.
      rainScore = (totalRain / 25.0).clamp(0.0, 1.0);
    } else {
      // Powdery mildews are suppressed by rain - heavy rain lowers the risk.
      rainScore = (1.0 - totalRain / 10.0).clamp(0.0, 1.0);
    }

    var score =
        100 *
        (_wEvents * eventScore +
            _wDuration * durationScore +
            _wTemp * tempScore +
            _wRain * rainScore);

    // No complete infection window means conditions were never sustained
    // enough for establishment, whatever the other components say. Cap it so
    // we never shout "severe" off rainfall and temperature alone.
    if (events.isEmpty) score = score.clamp(0.0, 35.0);

    // Nothing in range at all - the pathogen simply cannot work this week.
    if (favIdx.isEmpty) score = 0;

    final hutton = _isLateBlight(disease)
        ? _huttonCriteriaMet(forecast)
        : null;

    // The Hutton Criteria are the published standard for late blight in a way
    // our generic heuristic is not, so when they are met we honour them.
    if (hutton == true && score < 70) score = 70;

    return DiseaseRisk(
      disease: disease,
      score: double.parse(score.toStringAsFixed(1)),
      band: RiskBandX.fromScore(score),
      events: events,
      peakFavourableHours: peakHours,
      totalRainMm: double.parse(totalRain.toStringAsFixed(1)),
      drivers: _explain(
        disease: disease,
        events: events,
        peakHours: peakHours,
        totalRain: totalRain,
        tempScore: tempScore,
        hutton: hutton,
      ),
      huttonCriteriaMet: hutton,
    );
  }

  static bool _isLateBlight(DiseaseInfo d) =>
      d.species == 'Potato' && d.disease == 'Late Blight';

  /// The Hutton Criteria, as used by UK/EU blight warning services:
  /// two consecutive days, each with a minimum temperature of at least 10 C
  /// and at least six hours at relative humidity of 90% or above.
  ///
  /// Implemented against 3-hourly data, so "six hours" means two consecutive
  /// qualifying slices within the same day.
  static bool _huttonCriteriaMet(List<ForecastSlice> forecast) {
    final byDay = <String, List<ForecastSlice>>{};
    for (final s in forecast) {
      final key = '${s.time.year}-${s.time.month}-${s.time.day}';
      byDay.putIfAbsent(key, () => []).add(s);
    }

    final days = byDay.keys.toList()..sort();
    var consecutive = 0;

    for (final key in days) {
      final slices = byDay[key]!;
      // A partial first or last day would produce a false negative, so skip
      // days the forecast does not cover properly.
      if (slices.length < 4) {
        consecutive = 0;
        continue;
      }

      final minTemp = slices
          .map((s) => s.tempC)
          .reduce((a, b) => a < b ? a : b);
      final humidHours =
          slices.where((s) => s.humidity >= 90).length *
          ForecastSlice.hoursCovered;

      if (minTemp >= 10 && humidHours >= 6) {
        consecutive++;
        if (consecutive >= 2) return true;
      } else {
        consecutive = 0;
      }
    }
    return false;
  }

  static List<String> _explain({
    required DiseaseInfo disease,
    required List<InfectionEvent> events,
    required double peakHours,
    required double totalRain,
    required double tempScore,
    required bool? hutton,
  }) {
    final w = disease.window!;
    final out = <String>[];

    if (hutton == true) {
      out.add(
        'Hutton Criteria met - two days running with mild nights and six or '
        'more humid hours. This is the official late blight warning trigger.',
      );
    }

    if (events.isEmpty) {
      out.add(
        peakHours > 0
            ? 'Longest humid spell is about ${peakHours.toStringAsFixed(0)} h, '
                  'short of the ${w.sustainedHoursNeeded} h this disease needs '
                  'to establish.'
            : 'Conditions stay outside this pathogen\'s range all week.',
      );
    } else {
      final first = events.first;
      out.add(
        '${events.length} infection ${events.length == 1 ? "window" : "windows"} '
        'in the next five days - the first on '
        '${_dayName(first.start)} lasting about '
        '${first.hours.toStringAsFixed(0)} h at '
        '${first.meanTemp.toStringAsFixed(0)} C and '
        '${first.meanHumidity.toStringAsFixed(0)}% humidity.',
      );
    }

    if (tempScore >= 0.85) {
      out.add(
        'Temperatures sit right in the ${w.tempOptLow.toStringAsFixed(0)}-'
        '${w.tempOptHigh.toStringAsFixed(0)} C band this pathogen prefers.',
      );
    } else if (tempScore > 0 && tempScore < 0.4) {
      out.add('Temperatures are at the edge of its range, slowing it down.');
    }

    if (w.rainFavours && totalRain >= 10) {
      out.add(
        '${totalRain.toStringAsFixed(0)} mm of rain forecast - free water '
        'spreads spores between plants.',
      );
    } else if (!w.rainFavours && totalRain >= 10) {
      out.add(
        '${totalRain.toStringAsFixed(0)} mm of rain actually suppresses this '
        'one - rain washes the spores off the leaf.',
      );
    }

    return out;
  }

  static String _dayName(DateTime d) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final today = DateTime.now();
    if (d.day == today.day && d.month == today.month) return 'today';
    if (d.difference(today).inHours < 48) return 'tomorrow';
    return names[d.weekday - 1];
  }

  static double _mean(Iterable<double> xs) {
    if (xs.isEmpty) return 0;
    return xs.reduce((a, b) => a + b) / xs.length;
  }
}
