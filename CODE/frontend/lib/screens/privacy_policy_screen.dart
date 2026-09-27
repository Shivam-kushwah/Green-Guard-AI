import 'package:flutter/material.dart';

import '../utils/colors.dart';

/// Plain-language privacy policy, written to match what this app actually
/// does - not a boilerplate template. Kept in one file so it stays easy to
/// keep in sync with LocationService's coordinate rounding, ScanReportingService's
/// upload path, and HotspotService's demo-data labelling if any of those change.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Privacy Policy',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: const [
            _Intro(),
            _Section(
              title: 'What we collect',
              points: [
                'Your name, email and profile photo from Google Sign-In.',
                'Leaf photos you scan, along with the AI diagnosis and your '
                    'own scan history.',
                'Your farm\'s approximate location - used to fetch weather '
                    'data and to place your case on the district map. The '
                    'exact coordinate is rounded to about 1.1 km before it '
                    'ever leaves your phone; the precise reading is never '
                    'uploaded anywhere.',
                'If you request expert review: the case details an '
                    'agronomist needs to answer it.',
              ],
            ),
            _Section(
              title: 'What we do not collect',
              points: [
                'Your exact farm location - only the rounded, taluka-level '
                    'point ever reaches our servers.',
                'Anything from your device besides what you explicitly scan '
                    'or the location you grant permission for.',
              ],
            ),
            _Section(
              title: 'How your data is used',
              points: [
                'Diagnosing the crop you scanned, and building your personal '
                    'scan history.',
                'Showing weather-based outbreak risk for your area.',
                'Placing an anonymised, district-level point on the public '
                    'hotspot map so other farmers and officers can see where '
                    'disease is being reported.',
                'If you ask for expert review, your case (image and '
                    'diagnosis) is shown to a verified agronomist so they can '
                    'confirm or correct it.',
                'When an agronomist rules on a case, that verdict may later '
                    'be used - stripped of anything that identifies you '
                    'personally beyond the image itself - to retrain and '
                    'improve the disease-detection model.',
              ],
            ),
            _Section(
              title: 'Who can see what',
              points: [
                'Your name and email are visible to other signed-in users '
                    'only where the app needs it to function - for example, '
                    'showing a farmer which agronomist answered their case.',
                'The public hotspot map only ever shows district-level '
                    'aggregates - never anyone\'s name, photo, or exact '
                    'location.',
                'Demonstration data used for presentations is always '
                    'labelled "DEMO" wherever it appears, and is never mixed '
                    'into real counts without that label.',
              ],
            ),
            _Section(
              title: 'Your choices',
              points: [
                'Disease detection works fully offline - if you never grant '
                    'location permission or sign in, scanning and your local '
                    'history still work exactly the same.',
                'You can delete your local scan history from the History '
                    'screen at any time.',
                'You can ask us to remove your account and associated cloud '
                    'data at any time by contacting an administrator.',
              ],
            ),
            _Section(
              title: 'Changes to this policy',
              points: [
                'If how we handle your data changes in a meaningful way, '
                    'this page will be updated and the change will be dated '
                    'below.',
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Last updated: this build.',
              style: TextStyle(fontSize: 11.5, color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 20),
    child: Text(
      'Green Guard is built so disease detection works with as little data '
      'as possible, and the cloud features that need more are always opt-in '
      'and explained plainly. This page describes exactly what is collected '
      'and why - in the same language the app itself uses, not legal '
      'boilerplate.',
      style: TextStyle(fontSize: 13.5, height: 1.55, color: AppColors.onSurfaceVariant),
    ),
  );
}

class _Section extends StatelessWidget {
  final String title;
  final List<String> points;

  const _Section({required this.title, required this.points});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        for (final p in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(
                    Icons.circle,
                    size: 5,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
