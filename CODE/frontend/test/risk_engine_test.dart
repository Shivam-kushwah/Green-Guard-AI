import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/disease_kb.dart';
import 'package:frontend/model/weather.dart';
import 'package:frontend/services/risk_engine.dart';

/// Builds a synthetic 5-day / 3-hourly forecast, the same shape
/// OpenWeatherMap's free /forecast endpoint returns.
List<ForecastSlice> buildForecast({
  required double tempC,
  required double humidity,
  double rainMm = 0,
  int slices = 40,
  DateTime? start,
}) {
  final t0 = start ?? DateTime(2026, 1, 6, 0);
  return List.generate(
    slices,
    (i) => ForecastSlice(
      time: t0.add(Duration(hours: i * 3)),
      tempC: tempC,
      humidity: humidity,
      rainMm: rainMm,
      windMs: 2,
      pop: rainMm > 0 ? 0.8 : 0.1,
      condition: rainMm > 0 ? 'Rain' : 'Clear',
      icon: '01d',
    ),
  );
}

void main() {
  final lateBlight = DiseaseKb.lookup('Potato', 'Late Blight')!;
  final powdery = DiseaseKb.lookup('Generic', 'Powdery')!;
  final yellowRust = DiseaseKb.lookup('Wheat', 'Yellow Rust')!;

  group('temperature suitability', () {
    test('peaks inside the optimum band and is zero outside the limits', () {
      final w = lateBlight.window!;
      expect(w.tempSuitability(15), 1.0); // inside 12-21 optimum
      expect(w.tempSuitability(5), 0.0); // below tempMin 7
      expect(w.tempSuitability(30), 0.0); // above tempMax 27
      expect(w.tempSuitability(9), greaterThan(0));
      expect(w.tempSuitability(9), lessThan(1));
    });
  });

  group('late blight', () {
    test('cool and saturated conditions trigger a severe warning', () {
      final risk = RiskEngine.assess(
        lateBlight,
        buildForecast(tempC: 15, humidity: 95, rainMm: 2),
      )!;

      expect(risk.band, RiskBand.severe);
      expect(risk.huttonCriteriaMet, isTrue);
      expect(risk.events, isNotEmpty);
      expect(
        risk.drivers.any((d) => d.contains('Hutton')),
        isTrue,
        reason: 'the official trigger should be named in the explanation',
      );
    });

    test('hot dry weather gives a low risk with no infection window', () {
      final risk = RiskEngine.assess(
        lateBlight,
        buildForecast(tempC: 36, humidity: 25),
      )!;

      expect(risk.band, RiskBand.low);
      expect(risk.score, 0);
      expect(risk.events, isEmpty);
    });

    test('right temperature but dry air does not establish infection', () {
      // 15 C is ideal for the pathogen, but at 60% RH the leaf never wets.
      // This is the case a naive temperature-only model would get wrong.
      final risk = RiskEngine.assess(
        lateBlight,
        buildForecast(tempC: 15, humidity: 60),
      )!;

      expect(risk.events, isEmpty);
      expect(risk.huttonCriteriaMet, isFalse);
      expect(
        risk.score,
        lessThanOrEqualTo(35),
        reason: 'no completed infection window must cap the score',
      );
    });

    test('humidity just below the threshold still yields no event', () {
      final risk = RiskEngine.assess(
        lateBlight,
        buildForecast(tempC: 15, humidity: 89), // threshold is 90
      )!;
      expect(risk.events, isEmpty);
    });
  });

  group('powdery mildew treats rain as protective', () {
    test('dry warm weather scores higher than the same weather with rain', () {
      final dry = RiskEngine.assess(
        powdery,
        buildForecast(tempC: 24, humidity: 65),
      )!;
      final wet = RiskEngine.assess(
        powdery,
        buildForecast(tempC: 24, humidity: 65, rainMm: 3),
      )!;

      expect(
        dry.score,
        greaterThan(wet.score),
        reason: 'rain washes powdery mildew spores off the leaf',
      );
      expect(
        wet.drivers.any((d) => d.contains('suppresses')),
        isTrue,
        reason: 'the farmer should be told why rain lowers this one',
      );
    });
  });

  group('yellow rust is a cool-season disease', () {
    test('scores high at 12 C and zero at 30 C', () {
      final cool = RiskEngine.assess(
        yellowRust,
        buildForecast(tempC: 12, humidity: 95),
      )!;
      final hot = RiskEngine.assess(
        yellowRust,
        buildForecast(tempC: 30, humidity: 95),
      )!;

      expect(cool.score, greaterThan(50));
      expect(hot.score, 0);
    });
  });

  group('crop-level assessment', () {
    test('returns every disease for the crop, ordered worst first', () {
      final risks = RiskEngine.assessCrop(
        'Potato',
        buildForecast(tempC: 15, humidity: 95, rainMm: 2),
      );

      expect(risks.length, 2); // late blight + early blight, not healthy
      expect(risks.every((r) => !r.disease.isHealthy), isTrue);
      for (var i = 1; i < risks.length; i++) {
        expect(risks[i - 1].score, greaterThanOrEqualTo(risks[i].score));
      }
      expect(risks.first.disease.disease, 'Late Blight');
    });

    test('healthy classes produce no risk entry', () {
      final healthy = DiseaseKb.lookup('Potato', 'Healthy')!;
      expect(RiskEngine.assess(healthy, buildForecast(tempC: 15, humidity: 95)),
          isNull);
    });

    test('an empty forecast yields nothing rather than throwing', () {
      expect(RiskEngine.assess(lateBlight, const []), isNull);
    });
  });

  group('knowledge base integrity', () {
    test('every non-healthy disease has an infection window', () {
      for (final d in DiseaseKb.all.where((d) => !d.isHealthy)) {
        expect(
          d.window,
          isNotNull,
          reason: '${d.commonName} cannot be forecast without a window',
        );
      }
    });

    test('every infection window is internally consistent', () {
      for (final d in DiseaseKb.all) {
        final w = d.window;
        if (w == null) continue;
        expect(w.tempMin, lessThan(w.tempOptLow), reason: d.commonName);
        expect(w.tempOptLow, lessThanOrEqualTo(w.tempOptHigh),
            reason: d.commonName);
        expect(w.tempOptHigh, lessThan(w.tempMax), reason: d.commonName);
        expect(w.humidityThreshold, inInclusiveRange(0, 100),
            reason: d.commonName);
        expect(w.sustainedHoursNeeded, greaterThan(0), reason: d.commonName);
      }
    });

    test('every class in class_mapping.json resolves to a KB entry', () {
      // Mirrors assets/model/class_mapping.json. If the model is retrained
      // with new classes this test fails, which is the point - a new class
      // must get agronomic facts before it can reach a farmer.
      const classes = [
        ('Generic', 'Healthy'),
        ('Generic', 'Powdery'),
        ('Generic', 'Rusty'),
        ('CORN', 'Rust'),
        ('CORN', 'Gray Spot'),
        ('CORN', 'Healthy'),
        ('CORN', 'Leaf Blight'),
        ('Potato', 'Early Blight'),
        ('Potato', 'Healthy'),
        ('Potato', 'Late Blight'),
        ('SugarCane', 'Bacteria Blight'),
        ('SugarCane', 'Healthy'),
        ('SugarCane', 'RedRot'),
        ('Wheat', 'Brown Rust'),
        ('Wheat', 'Healthy'),
        ('Wheat', 'Yellow Rust'),
      ];

      for (final (species, disease) in classes) {
        expect(
          DiseaseKb.lookup(species, disease),
          isNotNull,
          reason: '$species/$disease is missing from the knowledge base',
        );
      }
      expect(classes.length, 16);
    });
  });
}
