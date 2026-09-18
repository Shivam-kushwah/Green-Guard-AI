// Replaces the stock Flutter counter-app template test, which asserted
// against a widget tree this project never had and so always failed.

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/maharashtra_districts.dart';

void main() {
  group('district lookup', () {
    test('matches an exact name', () {
      expect(MaharashtraDistricts.byName('Kolhapur')?.name, 'Kolhapur');
    });

    test('is tolerant of case and punctuation from geocoders', () {
      expect(MaharashtraDistricts.byName('  pune  ')?.name, 'Pune');
      expect(MaharashtraDistricts.byName('Pune District')?.name, 'Pune');
    });

    test('resolves districts renamed in 2023', () {
      // Most geocoding providers still return the pre-rename names, so a
      // scan from Aurangabad must not land in an "Unknown" bucket.
      expect(
        MaharashtraDistricts.byName('Aurangabad')?.name,
        'Chhatrapati Sambhajinagar',
      );
      expect(MaharashtraDistricts.byName('Osmanabad')?.name, 'Dharashiv');
    });

    test('returns null rather than guessing for an unknown name', () {
      expect(MaharashtraDistricts.byName('Bengaluru'), isNull);
      expect(MaharashtraDistricts.byName(''), isNull);
      expect(MaharashtraDistricts.byName(null), isNull);
    });
  });

  group('nearest-district fallback', () {
    test('snaps a coordinate to the right district', () {
      // Kolhapur city centre.
      expect(MaharashtraDistricts.nearest(16.70, 74.24).name, 'Kolhapur');
      // Nagpur.
      expect(MaharashtraDistricts.nearest(21.15, 79.09).name, 'Nagpur');
    });

    test('always returns something, even far outside the state', () {
      expect(MaharashtraDistricts.nearest(28.6, 77.2), isNotNull);
    });
  });

  group('state bounds guard', () {
    test('accepts points inside Maharashtra', () {
      expect(MaharashtraDistricts.isWithinState(18.52, 73.86), isTrue);
    });

    test('rejects points outside, so other states do not skew the dashboard', () {
      expect(MaharashtraDistricts.isWithinState(28.61, 77.21), isFalse); // Delhi
      expect(MaharashtraDistricts.isWithinState(12.97, 77.59), isFalse); // Bengaluru
    });
  });

  group('district table integrity', () {
    test('has no duplicate names', () {
      final names = MaharashtraDistricts.names;
      expect(names.toSet().length, names.length);
    });

    test('every district sits inside the state bounding box', () {
      for (final d in MaharashtraDistricts.all) {
        expect(
          MaharashtraDistricts.isWithinState(d.lat, d.lng),
          isTrue,
          reason: '${d.name} has coordinates outside Maharashtra',
        );
      }
    });
  });
}
