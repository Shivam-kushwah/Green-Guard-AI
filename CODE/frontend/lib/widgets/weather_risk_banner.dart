import 'package:flutter/material.dart';

import '../data/disease_kb.dart';
import '../screens/weather_risk_screen.dart';
import '../services/location_service.dart';
import '../services/risk_engine.dart';
import '../services/weather_service.dart';
import '../utils/colors.dart';
import '../utils/risk_colors.dart';

/// Compact risk summary for the home screen.
///
/// Deliberately quiet when there is nothing to say: no location, no key, or no
/// elevated risk all collapse to either a small neutral strip or nothing at
/// all. A banner that shouts every day stops being read.
class WeatherRiskBanner extends StatefulWidget {
  final List<String>? crops;

  const WeatherRiskBanner({super.key, this.crops});

  @override
  State<WeatherRiskBanner> createState() => _WeatherRiskBannerState();
}

class _WeatherRiskBannerState extends State<WeatherRiskBanner> {
  DiseaseRisk? _top;
  FarmLocation? _loc;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loc = await LocationService.instance.resolve();
      if (loc == null) {
        _markFailed();
        return;
      }

      final weather = await WeatherService.instance.fetch(
        lat: loc.lat,
        lng: loc.lng,
      );

      final crops = widget.crops?.isNotEmpty == true
          ? widget.crops!
          : (loc.district.majorCrops.isNotEmpty
                ? loc.district.majorCrops
                : DiseaseKb.allSpecies.where((s) => s != 'Generic').toList());

      final risks = RiskEngine.assessCrops(crops, weather.forecast);

      if (!mounted) return;
      setState(() {
        _loc = loc;
        _top = risks.isEmpty ? null : risks.first;
        _loading = false;
      });
    } catch (_) {
      _markFailed();
    }
  }

  void _markFailed() {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = true;
    });
  }

  void _open() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WeatherRiskScreen(crops: widget.crops),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _skeleton();

    // Nothing useful to show - stay out of the way rather than occupying
    // prime screen space with an error.
    if (_failed && _top == null) return const SizedBox.shrink();
    if (_top == null) return const SizedBox.shrink();

    final risk = _top!;
    final color = RiskColors.forBand(risk.band);
    final urgent =
        risk.band == RiskBand.high || risk.band == RiskBand.severe;

    return GestureDetector(
      onTap: _open,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: urgent
              ? RiskColors.surfaceFor(color)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: urgent ? color.withValues(alpha: 0.4) : AppColors.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                urgent
                    ? Icons.warning_amber_rounded
                    : Icons.wb_cloudy_outlined,
                color: color,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    urgent
                        ? '${risk.band.label} risk: ${risk.disease.commonName}'
                        : 'Disease risk is low this week',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: urgent ? color : AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    urgent && risk.drivers.isNotEmpty
                        ? risk.drivers.first
                        : '${_loc?.district.name ?? ""} - '
                              'tap for the 5-day forecast',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeleton() => Container(
    width: double.infinity,
    height: 68,
    decoration: BoxDecoration(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
