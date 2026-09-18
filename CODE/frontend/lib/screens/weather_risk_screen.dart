import 'package:flutter/material.dart';

import '../data/disease_kb.dart';
import '../data/maharashtra_districts.dart';
import '../model/weather.dart';
import '../services/location_service.dart';
import '../services/risk_engine.dart';
import '../services/weather_service.dart';
import '../utils/colors.dart';
import '../utils/risk_colors.dart';

/// Weather-driven outbreak risk for the farmer's own location.
class WeatherRiskScreen extends StatefulWidget {
  /// Crops to assess. Defaults to whatever the district is known for when the
  /// farmer has not set their own crops yet.
  final List<String>? crops;

  const WeatherRiskScreen({super.key, this.crops});

  @override
  State<WeatherRiskScreen> createState() => _WeatherRiskScreenState();
}

class _WeatherRiskScreenState extends State<WeatherRiskScreen> {
  FarmLocation? _location;
  WeatherBundle? _weather;
  List<DiseaseRisk> _risks = const [];

  bool _loading = true;
  String? _error;
  String? _notice;

  late List<String> _crops = widget.crops ?? const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });

    final loc = await LocationService.instance.resolve(
      forceRefresh: forceRefresh,
    );

    if (loc == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _locationMessage(LocationService.instance.lastFailure);
      });
      return;
    }

    // Fall back to the district's main crops when the farmer has not told us
    // what they grow - better than showing nothing on first run.
    final crops = _crops.isNotEmpty
        ? _crops
        : (loc.district.majorCrops.isNotEmpty
              ? loc.district.majorCrops
              : DiseaseKb.allSpecies.where((s) => s != 'Generic').toList());

    try {
      final weather = await WeatherService.instance.fetch(
        lat: loc.lat,
        lng: loc.lng,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;
      setState(() {
        _location = loc;
        _weather = weather;
        _crops = crops;
        _risks = RiskEngine.assessCrops(crops, weather.forecast);
        _loading = false;
        _notice = weather.fromCache
            ? 'Showing the last saved forecast - no connection right now.'
            : null;
      });
    } on WeatherException catch (e) {
      if (!mounted) return;
      setState(() {
        _location = loc;
        _loading = false;
        _error = e.message;
      });
    }
  }

  String _locationMessage(LocationFailure? f) => switch (f) {
    LocationFailure.serviceDisabled =>
      'Location is switched off. Turn on GPS, or choose your district below.',
    LocationFailure.permissionDenied =>
      'Green Guard needs location to forecast risk for your field.',
    LocationFailure.permanentlyDenied =>
      'Location permission is blocked. Enable it in Settings, or pick your '
          'district below.',
    _ => 'Could not get a location fix. Choose your district below instead.',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Disease Risk Forecast',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _load(forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (_error != null) _errorCard(_error!),
        if (_notice != null) _noticeBanner(_notice!),
        if (_weather != null) ...[
          _currentCard(_weather!.current, _location!),
          const SizedBox(height: 18),
          _sectionTitle(
            'Outbreak risk this week',
            subtitle: _crops.join(' - '),
          ),
          const SizedBox(height: 10),
          if (_risks.isEmpty)
            _emptyRisk()
          else
            ..._risks.map(_riskCard),
          const SizedBox(height: 18),
          _methodologyNote(),
        ],
        if (_weather == null && _error != null) _districtPicker(),
      ],
    );
  }

  // ------------------------------------------------------------- pieces

  Widget _sectionTitle(String text, {String? subtitle}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        text,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface,
        ),
      ),
      if (subtitle != null && subtitle.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
    ],
  );

  Widget _currentCard(CurrentWeather w, FarmLocation loc) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.place_outlined,
                size: 17,
                color: AppColors.primary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  loc.district.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              // Be explicit about provenance rather than implying a precision
              // we do not have.
              Text(
                loc.isLiveFix ? 'GPS' : 'Approx.',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${w.tempC.round()}',
                style: const TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w300,
                  height: 1,
                  color: AppColors.onSurface,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'C',
                  style: TextStyle(
                    fontSize: 18,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    w.description.isEmpty ? w.condition : w.description,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _metric(Icons.water_drop_outlined,
                      '${w.humidity.round()}% humidity'),
                  const SizedBox(height: 3),
                  _metric(Icons.air_rounded,
                      '${w.windMs.toStringAsFixed(1)} m/s wind'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: AppColors.onSurfaceVariant),
      const SizedBox(width: 4),
      Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    ],
  );

  Widget _riskCard(DiseaseRisk risk) {
    final color = RiskColors.forBand(risk.band);
    final d = risk.disease;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: _riskDial(risk.score, color),
          title: Text(
            d.commonName,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.onSurface,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: RiskColors.surfaceFor(color),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${risk.band.label} risk',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    '${d.species} - ${d.pathogenType.label}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          children: [
            _actionLine(risk.band, color),
            const SizedBox(height: 12),
            ...risk.drivers.map(
              (why) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 5, right: 8),
                      child: Icon(
                        Icons.circle,
                        size: 5,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        why,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (risk.band == RiskBand.high || risk.band == RiskBand.severe) ...[
              const SizedBox(height: 4),
              _adviceBlock('What to do', d.treatment, color),
            ],
            const SizedBox(height: 8),
            _adviceBlock(
              'Watch for',
              d.symptoms,
              AppColors.primary,
            ),
            if (d.regionalNote != null) ...[
              const SizedBox(height: 8),
              _adviceBlock('In Maharashtra', d.regionalNote!, AppColors.tertiary),
            ],
            const SizedBox(height: 10),
            Text(
              'Threshold used: ${d.source}',
              style: const TextStyle(
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small circular gauge - conveys the score without needing the reader to
  /// parse a number, while the number stays available for those who want it.
  Widget _riskDial(double score, Color color) => SizedBox(
    width: 42,
    height: 42,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 42,
          height: 42,
          child: CircularProgressIndicator(
            value: score / 100,
            strokeWidth: 4,
            backgroundColor: AppColors.surfaceContainer,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        Text(
          score.round().toString(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );

  Widget _actionLine(RiskBand band, Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: RiskColors.surfaceFor(color),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          band == RiskBand.severe
              ? Icons.warning_amber_rounded
              : Icons.info_outline_rounded,
          size: 17,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            band.action,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _adviceBlock(String title, String body, Color accent) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: accent,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        body,
        style: const TextStyle(
          fontSize: 13,
          height: 1.45,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    ],
  );

  Widget _emptyRisk() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: RiskColors.surfaceFor(RiskColors.healthy),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Row(
      children: [
        Icon(Icons.check_circle_outline, color: RiskColors.healthy),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'No disease-favourable weather in the next five days for your '
            'crops. Routine scouting is enough.',
            style: TextStyle(fontSize: 13, height: 1.45),
          ),
        ),
      ],
    ),
  );

  /// Stating the method and its limits in the product itself, not just in the
  /// docs - an officer challenging a number should find the answer here.
  Widget _methodologyNote() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.science_outlined,
              size: 15,
              color: AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              'HOW THIS IS CALCULATED',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        const Text(
          'Each disease has a published temperature and humidity window in '
          'which it can infect. We check the 5-day forecast for stretches that '
          'fall inside that window for long enough to matter.\n\n'
          'Infection is really driven by leaf wetness, which no free weather '
          'service measures, so we estimate it from humidity. Treat this as a '
          'prompt to go and inspect your field - not a guarantee.',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  Widget _noticeBanner(String text) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: RiskColors.surfaceFor(AppColors.tertiary),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_rounded,
            size: 17, color: AppColors.tertiary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
        ),
      ],
    ),
  );

  Widget _errorCard(String message) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: RiskColors.surfaceFor(AppColors.error),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
        ),
      ],
    ),
  );

  /// The escape hatch when GPS is unavailable - common enough in the field
  /// that it deserves to be a first-class path, not a dead end.
  Widget _districtPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Choose your district'),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: MaharashtraDistricts.all
            .where((d) => d.majorCrops.isNotEmpty)
            .map(
              (d) => ActionChip(
                label: Text(d.name, style: const TextStyle(fontSize: 12.5)),
                backgroundColor: AppColors.surfaceContainerLowest,
                side: const BorderSide(color: AppColors.outlineVariant),
                onPressed: () async {
                  await LocationService.instance.setDistrictManually(d);
                  _load();
                },
              ),
            )
            .toList(),
      ),
    ],
  );
}
