import 'package:flutter/material.dart';

import '../model/app_user.dart';
import '../model/district_stat.dart';
import '../model/intervention.dart';
import '../services/dashboard_service.dart';
import '../services/expert_service.dart';
import '../services/hotspot_service.dart';
import '../services/session.dart';
import '../utils/colors.dart';
import '../utils/risk_colors.dart';
import '../widgets/dashboard_charts.dart';
import 'hotspot_map_screen.dart';

/// Surveillance dashboard for Maharashtra agriculture officers.
///
/// Runs from the same codebase as the farmer app. On mobile it is a role-gated
/// tab; built for web (`flutter build web`) the same screen is the browser
/// dashboard, which is why it is laid out responsively rather than for a fixed
/// phone width.
class OfficerDashboardScreen extends StatefulWidget {
  const OfficerDashboardScreen({super.key});

  @override
  State<OfficerDashboardScreen> createState() => _OfficerDashboardScreenState();
}

class _OfficerDashboardScreenState extends State<OfficerDashboardScreen> {
  final _dash = DashboardService.instance;
  final _hotspots = HotspotService.instance;

  List<DailyCount> _trend = const [];
  ModelAgreement? _agreement;
  QueueHealth? _queueHealth;

  /// Demo rows are excluded from the officer view by default. An officer must
  /// never make a decision on seeded data without knowing it is seeded.
  bool _includeDemo = true;

  int _trendDays = 30;

  @override
  void initState() {
    super.initState();
    _loadAsyncPanels();
  }

  Future<void> _loadAsyncPanels() async {
    final results = await Future.wait([
      _dash.diseaseTrend(days: _trendDays),
      _dash.modelAgreement(),
      ExpertService.instance.queueHealth(),
    ]);

    if (!mounted) return;
    setState(() {
      _trend = results[0] as List<DailyCount>;
      _agreement = results[1] as ModelAgreement;
      _queueHealth = results[2] as QueueHealth;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = Session.instance.user;

    if (user == null || !user.canViewDashboard) {
      return _gate(user);
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'State Surveillance',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Open outbreak map',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HotspotMapScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadAsyncPanels,
          ),
        ],
      ),
      body: StreamBuilder<List<DistrictStat>>(
        stream: _hotspots.watchDistricts(includeDemo: _includeDemo),
        builder: (context, statSnap) {
          if (statSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final stats = statSnap.data ?? const <DistrictStat>[];
          final summary = _hotspots.summarise(stats);

          return StreamBuilder<List<Intervention>>(
            stream: _dash.watchInterventions(),
            builder: (context, intSnap) {
              final clusters = _dash.buildClusters(
                stats,
                intSnap.data ?? const <Intervention>[],
              );

              return RefreshIndicator(
                onRefresh: _loadAsyncPanels,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Two columns on a browser window, one on a phone.
                    final wide = constraints.maxWidth >= 900;
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                      children: [
                        if (stats.any((s) => s.isDemo)) _demoBanner(),
                        _kpiRow(summary, constraints.maxWidth),
                        const SizedBox(height: 20),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _leftColumn(summary, stats)),
                              const SizedBox(width: 20),
                              Expanded(child: _rightColumn(clusters, user)),
                            ],
                          )
                        else ...[
                          _leftColumn(summary, stats),
                          const SizedBox(height: 20),
                          _rightColumn(clusters, user),
                        ],
                      ],
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _leftColumn(StateSummary summary, List<DistrictStat> stats) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _trendPanel(),
      const SizedBox(height: 20),
      _diseasePanel(summary),
      const SizedBox(height: 20),
      _cropPanel(stats),
    ],
  );

  Widget _rightColumn(List<OutbreakCluster> clusters, AppUser user) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _interventionPanel(clusters, user),
      const SizedBox(height: 20),
      _expertPanel(),
      const SizedBox(height: 20),
      _modelPanel(),
    ],
  );

  // ------------------------------------------------------------ panels

  Widget _kpiRow(StateSummary s, double width) {
    final columns = width >= 900 ? 4 : 2;
    final tiles = [
      StatTile(
        value: '${s.totalCases}',
        label: 'Disease cases',
        sublabel: 'of ${s.totalScans} scans',
        icon: Icons.coronavirus_outlined,
        accent: RiskColors.high,
      ),
      StatTile(
        value: '${(s.stateInfectionRate * 100).round()}%',
        label: 'Infection rate',
        sublabel: 'state-wide',
        icon: Icons.percent_rounded,
        accent: AppColors.primary,
      ),
      StatTile(
        value: '${s.activeOutbreakDistricts}',
        label: 'Active districts',
        sublabel: 'reported in 14 days',
        icon: Icons.location_on_outlined,
        accent: RiskColors.severe,
      ),
      StatTile(
        value: '${s.districtsReporting}/36',
        label: 'Districts covered',
        sublabel: 'any scan activity',
        icon: Icons.travel_explore_rounded,
        accent: AppColors.tertiary,
      ),
    ];

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 11,
      crossAxisSpacing: 11,
      childAspectRatio: 1.45,
      children: tiles,
    );
  }

  Widget _trendPanel() => _panel(
    title: 'Disease reports per day',
    subtitle: 'Last $_trendDays days, state-wide',
    trailing: _trendRangePicker(),
    child: DiseaseTrendChart(data: _trend),
  );

  Widget _trendRangePicker() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [7, 30, 90].map((days) {
      final active = _trendDays == days;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: GestureDetector(
          onTap: () {
            setState(() => _trendDays = days);
            _loadAsyncPanels();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary
                  : AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '${days}d',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }).toList(),
  );

  Widget _diseasePanel(StateSummary s) {
    final ranked = s.rankedDiseases;
    if (ranked.isEmpty) {
      return _panel(
        title: 'Diseases reported',
        child: _empty('No disease reports yet'),
      );
    }
    final max = ranked.first.count;

    return _panel(
      title: 'Diseases reported',
      subtitle: 'Across all crops, state-wide',
      child: Column(
        children: ranked
            .take(8)
            .map(
              (e) => RankedBar(
                label: e.info.commonName,
                sublabel: e.info.species,
                value: e.count,
                maxValue: max,
                color: RiskColors.forThreat(e.info.threat),
                badge: e.info.notifiable ? 'NOTIFIABLE' : null,
                badgeIcon: e.info.notifiable
                    ? Icons.priority_high_rounded
                    : null,
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _cropPanel(List<DistrictStat> stats) {
    final crops = _dash.cropBreakdown(stats);
    if (crops.isEmpty) {
      return _panel(
        title: 'Cases by crop',
        child: _empty('No crop data yet'),
      );
    }

    final entries = crops.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.first.value;

    return _panel(
      title: 'Cases by crop',
      subtitle: 'Which crops are under pressure',
      child: Column(
        children: entries
            .map(
              (e) => RankedBar(
                label: e.key,
                value: e.value,
                maxValue: max,
                // Magnitude comparison, so one hue - length carries the
                // ranking and colour adds nothing by varying.
                color: AppColors.primary,
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _interventionPanel(List<OutbreakCluster> clusters, AppUser user) {
    final open = clusters.where((c) => c.isOpen).take(8).toList();

    return _panel(
      title: 'Intervention worklist',
      subtitle: open.isEmpty
          ? 'Nothing open'
          : '${clusters.where((c) => c.isOpen).length} clusters need a decision',
      child: open.isEmpty
          ? _empty('No open outbreak clusters')
          : Column(
              children: open
                  .map((c) => _clusterRow(c, user))
                  .toList(),
            ),
    );
  }

  Widget _clusterRow(OutbreakCluster c, AppUser user) {
    final color = RiskColors.forThreat(c.disease.threat);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${c.district} - ${c.disease.commonName}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              Text(
                '${c.cases} cases',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: RiskColors.inkOn(color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (c.disease.notifiable) ...[
                const Icon(Icons.priority_high_rounded,
                    size: 11, color: RiskColors.severe),
                const SizedBox(width: 2),
                const Text(
                  'NOTIFIABLE',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    color: RiskColors.severe,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                c.status.label,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              if (c.intervention?.isStalled == true) ...[
                const SizedBox(width: 6),
                Text(
                  'stalled ${c.intervention!.daysSinceUpdate}d',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: RiskColors.high,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final status in [
                InterventionStatus.acknowledged,
                InterventionStatus.dispatched,
                InterventionStatus.resolved,
                InterventionStatus.dismissed,
              ])
                _statusChip(c, status, user),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(
    OutbreakCluster c,
    InterventionStatus status,
    AppUser user,
  ) {
    final active = c.status == status;
    return GestureDetector(
      onTap: () async {
        try {
          await _dash.setInterventionStatus(
            officer: user,
            district: c.district,
            diseaseKey: c.disease.key,
            status: status,
            currentCaseCount: c.cases,
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not update: $e')),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.outlineVariant,
          ),
        ),
        child: Text(
          status.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _expertPanel() {
    final h = _queueHealth;
    if (h == null) {
      return _panel(
        title: 'Expert validation',
        child: _empty('Loading...'),
      );
    }

    return _panel(
      title: 'Expert validation',
      subtitle: 'Whether the 24-hour target is actually being met',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _miniStat('${h.verifiedExperts}', 'verified experts'),
              ),
              Expanded(child: _miniStat('${h.pending}', 'waiting')),
              Expanded(
                child: _miniStat(
                  h.resolved + h.expired == 0
                      ? '-'
                      : '${(h.answerRate * 100).round()}%',
                  'answered in time',
                ),
              ),
            ],
          ),
          if (h.isUnderStaffed) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: RiskColors.surfaceFor(RiskColors.high),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.groups_outlined,
                      size: 16, color: RiskColors.inkOn(RiskColors.high)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      h.verifiedExperts == 0
                          ? 'No verified agronomists are signed up. Farmer '
                                'cases cannot be answered until some are '
                                'recruited - this is a staffing gap, not a '
                                'software one.'
                          : 'The queue is growing faster than '
                                '${h.verifiedExperts} agronomists can clear '
                                'it. More reviewers are needed to hold the '
                                '24-hour target.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: RiskColors.inkOn(RiskColors.high),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _modelPanel() {
    final a = _agreement;
    if (a == null) {
      return _panel(title: 'Model accuracy', child: _empty('Loading...'));
    }

    if (a.total == 0) {
      return _panel(
        title: 'Model accuracy',
        subtitle: 'Measured against expert verdicts',
        child: _empty(
          'No expert-reviewed cases yet. Accuracy on real field photos '
          'cannot be measured until agronomists start ruling on cases.',
        ),
      );
    }

    final rate = a.agreementRate!;
    return _panel(
      title: 'Model accuracy',
      subtitle: 'Agreement with expert verdicts on real field photos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(rate * 100).round()}%',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: rate >= 0.8
                      ? AppColors.primary
                      : RiskColors.inkOn(RiskColors.high),
                ),
              ),
              const SizedBox(width: 9),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${a.confirmed} confirmed / ${a.corrected} corrected',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),

          // Refusing to dress up a small sample as a measurement.
          if (!a.isStatisticallyMeaningful) ...[
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                'Based on only ${a.total} reviewed '
                '${a.total == 1 ? "case" : "cases"}. Treat this as an early '
                'indicator, not a measurement - at least '
                '${ModelAgreement.minimumMeaningfulSample} are needed before '
                'the figure means much.',
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],

          if (a.worstClasses.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'MOST OFTEN WRONG',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ...a.worstClasses.take(4).map(
              (w) => RankedBar(
                label: w.info.commonName,
                sublabel: w.info.species,
                value: w.misses,
                maxValue: a.worstClasses.first.misses,
                color: RiskColors.high,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------- chrome

  Widget _panel({
    required String title,
    String? subtitle,
    Widget? trailing,
    required Widget child,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );

  Widget _miniStat(String value, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: AppColors.onSurface,
        ),
      ),
      Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    ],
  );

  Widget _empty(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 12,
        height: 1.45,
        color: AppColors.onSurfaceVariant,
      ),
    ),
  );

  Widget _demoBanner() => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: RiskColors.surfaceFor(AppColors.tertiary),
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.35)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded,
            size: 17, color: AppColors.tertiary),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'These figures include seeded demonstration data.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _includeDemo = !_includeDemo),
          child: Text(
            _includeDemo ? 'HIDE' : 'SHOW',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _gate(AppUser? user) => Scaffold(
    backgroundColor: AppColors.surface,
    appBar: AppBar(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'State Surveillance',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
      ),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined,
                size: 40, color: AppColors.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              user == null ? 'Sign in required' : 'Officer access only',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              user == null
                  ? 'Sign in with your department account to open the '
                        'surveillance dashboard.'
                  : 'This dashboard is restricted to Maharashtra agriculture '
                        'officers. Ask an administrator to grant your account '
                        'officer access.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
