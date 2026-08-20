import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../engine/alertness_service.dart';
import '../engine/gap_service.dart';
import '../engine/nudge_service.dart';
import '../engine/skin_routine_service.dart';
import '../services/report_api.dart';
import '../health/health_signal_source.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_card.dart';
import 'ai_report_screen.dart';
import 'quick_advice_result_screen.dart';
import '../services/auth_service.dart';
import 'settings_screen.dart';

/// "최근 회복 상태" 카드에 쓰는 값 — 조회 실패·타임아웃·데이터 없음을 모두
/// null로 통일한다(§6-3-c와 같은 원칙: 선택 데이터라 실패해도 화면을 막지
/// 않는다).
class _RecoveryStats {
  const _RecoveryStats({
    this.sleepDuration,
    this.hrvZScore,
    this.restingBpm,
    this.daylightMinutes,
  });
  final Duration? sleepDuration;
  final double? hrvZScore;
  final double? restingBpm;
  final double? daylightMinutes; // null = capabilities.hasDaylight가 false인 기기

  static const empty = _RecoveryStats();
}

Future<_RecoveryStats> _loadRecovery(HealthSignalSource source) async {
  try {
    return await _fetchRecovery(source).timeout(const Duration(seconds: 8));
  } catch (_) {
    // 권한 거부·기기 미지원·조회 지연 등 원인과 무관하게 "데이터 없음"으로
    // 통일한다 — 이 카드는 선택 데이터라 실패해도 홈 화면을 막으면 안 된다.
    return _RecoveryStats.empty;
  }
}

Future<_RecoveryStats> _fetchRecovery(HealthSignalSource source) async {
  final now = DateTime.now();
  final since = now.subtract(const Duration(hours: 36));
  final today = DateTime(now.year, now.month, now.day);

  final sessions = await source.sleepSessions(DateRange(since, now));
  final hrv = await source.hrvNormalized(DateRange(since, now));
  final restingHr = await source.restingHeartRate(DateRange(since, now));
  final daylight = source.capabilities.hasDaylight
      ? await source.daylight(DateRange(today, now))
      : null;

  return _RecoveryStats(
    sleepDuration: sessions.isEmpty
        ? null
        : sessions.last.end.difference(sessions.last.start),
    hrvZScore: hrv == null || hrv.points.isEmpty ? null : hrv.points.last.$2,
    restingBpm: restingHr == null || restingHr.points.isEmpty
        ? null
        : restingHr.points.last.$2,
    daylightMinutes: daylight == null || daylight.points.isEmpty
        ? null
        : daylight.points.fold<double>(0.0, (sum, p) => sum + p.$2),
  );
}

String _formatSleep(Duration? d) {
  if (d == null) return '—';
  final h = d.inMinutes ~/ 60;
  final m = d.inMinutes % 60;
  return '${h}h ${m}m';
}

String _formatHrv(double? z) =>
    z == null ? '—' : '${z >= 0 ? '+' : ''}${z.toStringAsFixed(1)}σ';

String _formatBpm(double? bpm) => bpm == null ? '—' : '${bpm.round()}bpm';

String _formatDaylight(double? minutes) {
  if (minutes == null) return '—';
  if (minutes < 60) return '${minutes.round()}분';
  return '${(minutes / 60).toStringAsFixed(1)}h';
}

const _weekdaysKo = ['월', '화', '수', '목', '금', '토', '일'];
String _formatTodayKo(DateTime d) =>
    '${d.month}월 ${d.day}일 ${_weekdaysKo[d.weekday - 1]}요일';
String _fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _manualSleepSummary(AppState state) {
  final start = state.bedtimeIntents.first.at;
  final end = state.wakeIntents.first.at;
  final duration = state.latestManualSleepDuration;
  if (duration == null) return '${_fmtTime(start)}에 수면 시작을 기록했어요';
  final hours = duration.inMinutes ~/ 60;
  final minutes = duration.inMinutes % 60;
  return '${_fmtTime(start)} 취침 · ${_fmtTime(end)} 기상 · ${hours}h ${minutes}m';
}

/// 기존 확정 디자인(구 Figma 파일 `29:3772`, 낮/오프·나이트/이브닝 2 variant)을
/// 하나의 위젯으로 구현한다. 낮/쿨톤 배경 분기는 더 이상 수동 스위치가
/// 아니라 `NudgeService`가 실제 로스터(`AppState`, 없으면 데모)로 계산한
/// 오늘 근무 타입에서 그대로 따라온다(`TodayNudges.isNightMood`).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.healthSource});

  // 테스트에서 실기기 플랫폼 채널 대신 DemoHealthSource를 주입하기 위한 훅.
  // null이면 플랫폼에 맞는 실제 어댑터를 쓴다.
  final HealthSignalSource? healthSource;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<TodayNudges> _future;
  late Future<AlertnessResult> _alertFuture;
  late Future<List<SleepDurationDay>> _sleepDurationFuture;
  late final HealthSignalSource _healthSource =
      widget.healthSource ??
      (AppState.instance.isDemoAccount || kDebugMode
          ? (AppState.instance.isDemoAccount
                ? const SyncedHealthSource()
                : const DemoHealthSource())
          : defaultTargetPlatform == TargetPlatform.android
          ? AndroidHealthSource()
          : IosHealthSource());
  late Future<_RecoveryStats> _recoveryFuture;

  // 행동별 완료 체크 — 인메모리 상태다(§ AppState와 동일하게 영구저장 전까지는
  // 앱 재시작 시 초기화됨). `data.actions`의 인덱스로 식별한다.
  final Set<int> _completedActions = {};

  @override
  void initState() {
    super.initState();
    _future = loadTodayNudges();
    _alertFuture = loadAlertness();
    _sleepDurationFuture = _alertFuture.then(
      (r) => sleepDurationSeries(roster: r.roster),
    );
    _recoveryFuture = _loadRecovery(_healthSource);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<TodayNudges>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final isNight = data?.isNightMood ?? false;
          final gradientColors = isNight
              ? [const Color(0xFFDCEBFF), AppColors.background]
              : [const Color(0xFFFFE7AF), AppColors.background];

          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: gradientColors,
              ),
            ),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatTodayKo(DateTime.now()),
                              style: AppTypography.caption01.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '안녕하세요, ${AppState.instance.userName ?? '게스트'}님',
                              style: AppTypography.heading04,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // 설정은 여기 하나만 둔다. 예전엔 이 자리에 AI
                      // 리포트·피부 루틴 아이콘 2개가 있었는데, 아이콘만
                      // 봐서는 뭔지 알 수 없어서 아래 카드로 내렸다.
                      _HeaderIconButton(
                        icon: Icons.settings_rounded,
                        tooltip: '설정',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  if (snapshot.hasError)
                    SizedBox(
                      height: 160,
                      child: Center(
                        child: Text(
                          '오늘의 계획을 불러오지 못했어요\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: AppTypography.body02.copyWith(
                            color: AppColors.error01,
                          ),
                        ),
                      ),
                    )
                  else if (data == null)
                    const SizedBox(
                      height: 160,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    _TodayContent(
                      isNight: isNight,
                      data: data,
                      completedActions: _completedActions,
                      onToggleAction: (i) => setState(() {
                        if (!_completedActions.add(i)) {
                          _completedActions.remove(i);
                        }
                      }),
                      onLogBedtime: () =>
                          setState(() => AppState.instance.logBedtimeIntent()),
                      onLogWake: () =>
                          setState(() => AppState.instance.logWakeIntent()),
                    ),
                  FutureBuilder<AlertnessResult>(
                    future: _alertFuture,
                    builder: (context, alertSnapshot) {
                      final low = alertSnapshot.data?.isLowNow ?? false;
                      if (!low) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.information03.withValues(
                              alpha: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '지금이 오늘 중 컨디션이 가장 낮은 시간대예요',
                            style: AppTypography.caption01.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text('최근 회복 상태', style: AppTypography.subtitle04),
                  const SizedBox(height: AppSpacing.sm),
                  FutureBuilder<_RecoveryStats>(
                    future: _recoveryFuture,
                    builder: (context, recoverySnapshot) {
                      final stats =
                          recoverySnapshot.data ?? _RecoveryStats.empty;
                      final showDaylight =
                          _healthSource.capabilities.hasDaylight;
                      return Row(
                        children: [
                          Expanded(
                            child: _RecoveryTile(
                              label: '수면시간',
                              value: _formatSleep(stats.sleepDuration),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _RecoveryTile(
                              label: 'HRV',
                              value: _formatHrv(stats.hrvZScore),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _RecoveryTile(
                              label: '안정심박',
                              value: _formatBpm(stats.restingBpm),
                            ),
                          ),
                          if (showDaylight) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _RecoveryTile(
                                label: '일광 노출',
                                value: _formatDaylight(stats.daylightMinutes),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const _HomeSectionDivider(),
                  Text('최근 2주 권장 수면량', style: AppTypography.subtitle04),
                  const SizedBox(height: 4),
                  Text(
                    '근무와 누적 부족분을 반영한 권장량 대비 실제 수면',
                    style: AppTypography.caption02.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    child: FutureBuilder<List<SleepDurationDay>>(
                      future: _sleepDurationFuture,
                      builder: (context, sleepSnapshot) {
                        final days = sleepSnapshot.data;
                        if (sleepSnapshot.hasError) {
                          return const SizedBox(
                            height: 120,
                            child: Center(child: Text('수면량을 불러오지 못했어요')),
                          );
                        }
                        // 다른 보조 섹션(최근 회복 상태 등)과 같은 원칙 —
                        // 선택 데이터라 로딩 중에도 스피너 없이 빈 자리만
                        // 유지한다(레이아웃 점프만 방지).
                        if (days == null || days.isEmpty) {
                          return const SizedBox(height: 120);
                        }
                        return _SleepDurationChart(days: days);
                      },
                    ),
                  ),
                  // AI 인사이트와 피부 루틴은 별도 화면으로 들어가야
                  // 볼 수 있었다 — 탭 두 번을 없애고 여기 바로 편다.
                  const _HomeSectionDivider(),
                  FutureBuilder<AlertnessResult>(
                    future: _alertFuture,
                    builder: (context, snap) {
                      final r = snap.data;
                      if (r == null) return const SizedBox.shrink();
                      final routine = skinRoutineFrom(r);
                      if (routine == null) return const SizedBox.shrink();
                      return _SkinRoutineSection(routine: routine);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SleepDurationChart extends StatelessWidget {
  const _SleepDurationChart({required this.days});
  final List<SleepDurationDay> days;

  @override
  Widget build(BuildContext context) {
    final averageTarget =
        days.fold<int>(0, (sum, d) => sum + d.targetMinutes) ~/ days.length;
    final averageActual =
        days.fold<int>(0, (sum, d) => sum + d.actualMinutes) ~/ days.length;
    final totalDeficit = days.fold<int>(
      0,
      (sum, d) => sum + (d.deficitMinutes > 0 ? d.deficitMinutes : 0),
    );
    final maxSleep = days
        .expand((d) => [d.targetMinutes, d.actualMinutes])
        .fold<int>(8 * 60, (a, b) => a > b ? a : b);
    final bound = ((maxSleep / 60).ceil() * 60 + 60).toDouble();

    return SizedBox(
      height: 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SleepSummary(label: '평균 권장', minutes: averageTarget),
              ),
              Expanded(
                child: _SleepSummary(label: '평균 실제', minutes: averageActual),
              ),
              Expanded(
                child: _SleepSummary(label: '누적 부족', minutes: totalDeficit),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _SleepLegend(color: AppColors.gray300, label: '권장 수면'),
              const SizedBox(width: AppSpacing.md),
              _SleepLegend(color: AppColors.primary500, label: '실제 수면'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: bound,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 120,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: AppColors.gray100, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 0,
                      color: AppColors.gray300,
                      strokeWidth: 1.5,
                    ),
                  ],
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: 120,
                      getTitlesWidget: (value, meta) => Text(
                        value == 0 ? '0' : '${(value / 60).round()}h',
                        style: AppTypography.caption03.copyWith(
                          color: AppColors.textPlaceholder,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      getTitlesWidget: (value, meta) {
                        final day = value.round() + 1;
                        final show =
                            day == 1 ||
                            day == 5 ||
                            day == 9 ||
                            day == days.length;
                        return Text(
                          show ? '$day일' : '',
                          style: AppTypography.caption03.copyWith(
                            color: AppColors.textPlaceholder,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                        BarTooltipItem(
                          _sleepTooltip(days[group.x]),
                          AppTypography.caption02,
                        ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < days.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: days[i].targetMinutes.toDouble(),
                          width: 7,
                          color: AppColors.gray300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        BarChartRodData(
                          toY: days[i].actualMinutes.toDouble(),
                          width: 7,
                          color: AppColors.primary500,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _durationLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

String _sleepTooltip(SleepDurationDay day) {
  final deficit = day.deficitMinutes;
  return '권장 ${_durationLabel(day.targetMinutes)}\n'
      '실제 ${_durationLabel(day.actualMinutes)}\n'
      '${deficit > 0 ? '${_durationLabel(deficit)} 부족' : '목표 충족'}';
}

class _SleepSummary extends StatelessWidget {
  const _SleepSummary({required this.label, required this.minutes});
  final String label;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.caption03.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 2),
        Text(_durationLabel(minutes), style: AppTypography.subtitle04),
      ],
    );
  }
}

class _SleepLegend extends StatelessWidget {
  const _SleepLegend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTypography.caption03.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _HomeSectionDivider extends StatelessWidget {
  const _HomeSectionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      color: AppColors.gray200,
    );
  }
}

class _TodayContent extends StatelessWidget {
  const _TodayContent({
    required this.isNight,
    required this.data,
    required this.completedActions,
    required this.onToggleAction,
    required this.onLogBedtime,
    required this.onLogWake,
  });

  final bool isNight;
  final TodayNudges data;
  final Set<int> completedActions;
  final ValueChanged<int> onToggleAction;
  final VoidCallback onLogBedtime;
  final VoidCallback onLogWake;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.xxl),
          decoration: BoxDecoration(
            color: AppColors.grayWhite,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.gray100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.headerLabel,
                style: AppTypography.caption01.copyWith(
                  color: isNight
                      ? AppColors.information01
                      : AppColors.primary900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                data.planLabel,
                style: AppTypography.heading01.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _InsightSection(fallback: data.summary),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    backgroundColor: AppColors.gray50,
                    side: const BorderSide(color: AppColors.gray200),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                  ),
                  onPressed: AppState.instance.hasOpenManualSleep
                      ? onLogWake
                      : onLogBedtime,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        AppState.instance.hasOpenManualSleep
                            ? Icons.wb_sunny_outlined
                            : Icons.bedtime_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        AppState.instance.hasOpenManualSleep
                            ? '지금 일어났어요'
                            : '지금 누웠어요',
                      ),
                    ],
                  ),
                ),
              ),
              if (AppState.instance.bedtimeIntents.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  AppState.instance.hasOpenManualSleep
                      ? '${_fmtTime(AppState.instance.bedtimeIntents.first.at)}부터 수면 시작으로 기록 중이에요'
                      : _manualSleepSummary(AppState.instance),
                  style: AppTypography.caption03.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Text('오늘의 행동', style: AppTypography.subtitle04),
        const SizedBox(height: AppSpacing.sm),
        if (data.actions.isEmpty)
          Text(
            '지금 시점에 남은 넛지가 없어요.',
            style: AppTypography.body02.copyWith(color: AppColors.textTertiary),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              children: [
                for (var i = 0; i < data.actions.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: AppColors.gray100),
                  _ActionRow(
                    action: data.actions[i],
                    completed: completedActions.contains(i),
                    onToggle: () => onToggleAction(i),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: AppColors.grayWhite,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

/// 완료(사용자가 직접 체크) / 놓침(예정 시각이 지났는데 미완료) / 예정
/// (아직 시각 전) 3-상태. "언제 오는지"(시각)와 "지났는데 안 함"을 UI로
/// 구분해달라는 요청 — 놓침은 이 앱의 핵심 가치(타이밍이 곧 효과, §7-2)를
/// 살리려고 단순 완료/미완료 대신 넣었다.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.action,
    required this.completed,
    required this.onToggle,
  });
  final NudgeAction action;
  final bool completed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final missed = !completed && action.isPast;
    final statusLabel = completed ? '완료' : (missed ? '놓침' : '예정');
    final statusColor = completed
        ? AppColors.success01
        : (missed ? AppColors.error01 : AppColors.textTertiary);
    final textColor = completed ? AppColors.gray400 : AppColors.textPrimary;
    final textDecoration = completed
        ? TextDecoration.lineThrough
        : TextDecoration.none;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.time,
                  style: AppTypography.body02.copyWith(
                    color: completed
                        ? AppColors.gray400
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusLabel,
                  style: AppTypography.caption03.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.label,
                  style: AppTypography.body02.copyWith(
                    color: textColor,
                    decoration: textDecoration,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  action.message,
                  style: AppTypography.caption02.copyWith(
                    color: completed
                        ? AppColors.gray400
                        : AppColors.textTertiary,
                    decoration: textDecoration,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: completed
                  ? AppColors.success01
                  : AppColors.textSecondary,
              side: BorderSide(
                color: completed ? AppColors.success01 : AppColors.gray200,
              ),
              minimumSize: const Size(52, 36),
            ),
            onPressed: onToggle,
            child: completed
                ? const Icon(Icons.check, size: 18)
                : Text('완료', style: AppTypography.caption02),
          ),
        ],
      ),
    );
  }
}

class _RecoveryTile extends StatelessWidget {
  const _RecoveryTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: [
          Text(
            label,
            style: AppTypography.caption02.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.subtitle03.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 홈에 바로 뜨는 AI 코멘트. 예전엔 AI 리포트 화면까지 들어가야 볼 수
/// 있었다.
///
/// 홈은 하루에도 여러 번 여는 화면이라 열 때마다 호출하면 Gemini 비용이
/// 그대로 늘어난다 — 하루 한 번만 받고 그 뒤로는 캐시를 보여준다
/// (`AppState.hasFreshAiComment`).
class _InsightSection extends StatefulWidget {
  const _InsightSection({required this.fallback});

  final String fallback;

  @override
  State<_InsightSection> createState() => _InsightSectionState();
}

class _InsightSectionState extends State<_InsightSection> {
  Future<String>? _future;
  String? _previousComment;

  @override
  void initState() {
    super.initState();
    final s = AppState.instance;
    s.addListener(_onAppStateChanged);
    if (s.aiConsent && !s.hasFreshAiComment) _future = _fetch();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    final s = AppState.instance;
    if (!s.aiConsent) {
      setState(() => _future = null);
      return;
    }
    if (!s.hasFreshAiComment && _future == null) {
      setState(() {
        _future = _fetch();
      });
      return;
    }
    setState(() {});
  }

  void _refreshInsight() {
    if (!AppState.instance.aiConsent) return;
    _previousComment = AppState.instance.aiComment;
    setState(() => _future = null);
    AppState.instance.clearAiComment();
  }

  Future<String> _fetch() async {
    final r = await loadAlertness();
    final res = await fetchAiReport(
      roster: r.roster,
      profile: r.profile,
      previousComment: _previousComment,
    );
    // 요청 도중 동의를 철회했다면 늦게 도착한 응답을 저장하거나 노출하지 않는다.
    if (!AppState.instance.aiConsent) return '';
    AppState.instance.saveAiComment(res.comment);
    return res.comment;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final fallback = widget.fallback.isEmpty
        ? '오늘의 근무와 수면 흐름에 맞춰 회복할 시간을 준비해보세요.'
        : widget.fallback;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.zero,
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: AppColors.gray100, height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.primary500,
                size: 17,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'AI 오늘의 한 줄',
                style: AppTypography.caption02.copyWith(
                  color: AppColors.primary900,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (s.aiConsent)
                GestureDetector(
                  onTap: _refreshInsight,
                  child: const Icon(
                    Icons.refresh_rounded,
                    color: AppColors.textTertiary,
                    size: 17,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (!s.aiConsent)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  backgroundColor: AppColors.gray50,
                  side: const BorderSide(color: AppColors.gray200),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('설정에서 AI 인사이트 켜기'),
              ),
            )
          else if (s.hasFreshAiComment)
            Text(
              s.aiComment!,
              style: AppTypography.body02.copyWith(
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            )
          else
            FutureBuilder<String>(
              future: _future,
              builder: (context, snap) {
                final text = snap.hasData ? snap.data! : fallback;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        text,
                        style: AppTypography.body02.copyWith(
                          color: snap.hasError
                              ? AppColors.error01
                              : AppColors.textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ),
                    if (snap.connectionState == ConnectionState.waiting) ...[
                      const SizedBox(width: AppSpacing.sm),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary500,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          if (s.aiConsent) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.gray200),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: AppColors.grayWhite,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      builder: (_) => const _QuickAdviceSheet(),
                    ),
                    icon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 16,
                    ),
                    label: Text('상태·고민 전달', style: AppTypography.caption02),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AiReportScreen()),
                    ),
                    icon: const Icon(Icons.insights_outlined, size: 16),
                    label: Text('리듬 자세히 보기', style: AppTypography.caption02),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickAdviceSheet extends StatefulWidget {
  const _QuickAdviceSheet();

  @override
  State<_QuickAdviceSheet> createState() => _QuickAdviceSheetState();
}

class _QuickAdviceSheetState extends State<_QuickAdviceSheet> {
  static const _choices = ['많이 피곤해요', '잠이 잘 안 와요', '자꾸 깨요', '피부가 예민해요'];
  final _controller = TextEditingController();
  final _selected = <String>{};
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final typed = _controller.text.trim();
    final note = [..._selected, if (typed.isNotEmpty) typed].join(', ');
    if (note.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('오늘 상태나 고민을 하나 이상 알려주세요.')));
      return;
    }
    setState(() {
      _loading = true;
    });
    try {
      AppState.instance.saveDailyCheckIn(tags: _selected.toList(), note: typed);
      try {
        await AuthService.saveDailyCheckIn(
          tags: _selected.toList(),
          note: typed,
        );
      } catch (_) {
        // AI 답변은 서버 체크인 동기화 실패와 별개로 계속 제공한다.
      }
      final rhythm = await loadAlertness();
      final result = await fetchAiReport(
        roster: rhythm.roster,
        profile: rhythm.profile,
        stateNote: note,
      );
      if (!mounted) return;
      final nightCount = rhythm.roster
          .where((shift) => shift.name == 'night')
          .length;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => QuickAdviceResultScreen(
            userState: note,
            aiAnalysis: result.comment,
            nightShiftCount: nightCount,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 조언을 불러오지 못했어요. 다시 시도해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.gray200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('오늘 상태와 고민 전달', style: AppTypography.subtitle02),
            const SizedBox(height: 4),
            Text(
              '근무와 수면 리듬을 함께 읽고 지금 할 수 있는 행동을 제안해드려요.',
              style: AppTypography.caption02.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final choice in _choices)
                  ChoiceChip(
                    label: Text(choice),
                    selected: _selected.contains(choice),
                    selectedColor: AppColors.primary500,
                    onSelected: (_) => setState(() {
                      if (!_selected.add(choice)) _selected.remove(choice);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _controller,
              minLines: 3,
              maxLines: 5,
              maxLength: stateNoteMaxLength,
              decoration: InputDecoration(
                hintText: '예: 귀와 턱 주변 트러블이 반복되고 잠도 자주 깨요',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _send,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('AI에게 바로 전달하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 피부 루틴 — 별도 화면이었다가 홈 하단 섹션으로 내려왔다. 시각은
/// 하드코딩이 아니라 오늘 수면 창에서 계산한다(`skin_routine_service.dart`).
class _SkinRoutineSection extends StatelessWidget {
  const _SkinRoutineSection({required this.routine});
  final SkinRoutine routine;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('피부 루틴', style: AppTypography.subtitle04),
        const SizedBox(height: 4),
        Text(
          '벽시계의 AM·PM 대신, 내 근무와 수면에 맞춘 생체 루틴',
          style: AppTypography.caption02.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.primary50,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.primary900,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '오늘은 ${routine.shiftLabel} 기준',
                      style: AppTypography.subtitle04,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${routine.wakeLabel} 기상부터 ${routine.bedtimeLabel} 주 수면까지를 '
                '하나의 생체 하루로 보고 루틴 시각을 배치했어요.',
                style: AppTypography.caption01.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              if (routine.isRecoveryMode) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.grayWhite,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.bedtime_outlined,
                        color: AppColors.primary900,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '회복 모드 · 오늘 권장 수면보다 ${routine.todayDeficitMinutes}분 부족해요. '
                          '여러 단계를 더하기보다 세안과 장벽 보습 중심으로 단순하게 제안해요.',
                          style: AppTypography.caption02.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (routine.upcomingNightCount > 0) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.grayWhite,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_rounded,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '앞으로 2주간 나이트 ${routine.upcomingNightCount}회 · '
                          '수면 시각이 바뀌면 피부 루틴도 함께 이동해요.',
                          style: AppTypography.caption02.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          elevated: true,
          child: Column(
            children: [
              _RoutineRow(
                time: routine.wakeLabel,
                title: '주간 보호 루틴',
                desc: '기상 직후 · 순한 세안 → 보습 → 자외선 차단',
                reason: '벽시계 아침이 아니라 오늘의 생체 기상 직후에 맞췄어요.',
                productSlot: 'AAC 선케어 · 주간 보호 제품군',
              ),
              const Divider(height: AppSpacing.xxl, color: AppColors.gray100),
              _RoutineRow(
                time: routine.bedtimeLabel,
                title: routine.isRecoveryMode ? '회복 모드 루틴' : '야간 보습 루틴',
                desc: routine.isRecoveryMode
                    ? '주 수면 직전 · 순한 세안 → 진정·장벽 보습'
                    : '주 수면 직전 · 세안 → 보습 중심으로 단순하게',
                reason: routine.isRecoveryMode
                    ? '수면 부족이 큰 날이라 자극을 늘리지 않는 구성이에요.'
                    : '오늘의 주 수면 직전을 생체 PM으로 사용해요.',
                productSlot: 'AAC 진정 · 장벽 보습 제품군',
              ),
              if (routine.isNightShift && routine.commuteLabel != null) ...[
                const Divider(height: AppSpacing.xxl, color: AppColors.gray100),
                _RoutineRow(
                  time: routine.commuteLabel!,
                  title: '나이트 퇴근길 보호',
                  desc: '선글라스 + 자외선 차단 · 빛 노출도 함께 줄여요',
                  reason: '아침 퇴근길의 빛과 자외선을 한 행동으로 함께 관리해요.',
                  productSlot: 'AAC 휴대용 선케어 제품군',
                ),
              ],
            ],
          ),
        ),
        if (routine.upcomingNightCount > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.primary50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary400),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AAC 제품 연동 데모',
                  style: AppTypography.caption02.copyWith(
                    color: AppColors.primary900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '나이트 ${routine.upcomingNightCount}회 준비 키트',
                  style: AppTypography.subtitle04.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '순한 클렌저 · 진정/장벽 보습 · 휴대용 선케어',
                  style: AppTypography.body02.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 154,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: const [
                      _HomeDemoProduct(
                        Icons.water_drop_outlined,
                        '클렌저',
                        'Calm Wash',
                        Color(0xFFDDEEFF),
                      ),
                      _HomeDemoProduct(
                        Icons.spa_outlined,
                        '미스트',
                        'Reset Mist',
                        Color(0xFFE4F2E8),
                      ),
                      _HomeDemoProduct(
                        Icons.science_outlined,
                        '세럼',
                        'Barrier Drop',
                        Color(0xFFFFE7D7),
                      ),
                      _HomeDemoProduct(
                        Icons.bubble_chart_outlined,
                        '크림',
                        'Night Shield',
                        Color(0xFFE8E4F5),
                      ),
                      _HomeDemoProduct(
                        Icons.wb_sunny_outlined,
                        '선케어',
                        'SleepReady UV',
                        Color(0xFFFFF0C8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({
    required this.time,
    required this.title,
    required this.desc,
    required this.reason,
    required this.productSlot,
  });

  final String time;
  final String title;
  final String desc;
  final String reason;
  final String productSlot;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 58, child: Text(time, style: AppTypography.subtitle03)),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.body02),
              const SizedBox(height: 2),
              Text(
                desc,
                style: AppTypography.caption02.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                reason,
                style: AppTypography.caption03.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  productSlot,
                  style: AppTypography.caption03.copyWith(
                    color: AppColors.primary900,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HomeDemoProduct extends StatelessWidget {
  const _HomeDemoProduct(this.icon, this.type, this.name, this.color);

  final IconData icon;
  final String type;
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118,
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.grayWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 66,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              children: [
                Center(child: Icon(icon, size: 30, color: AppColors.gray700)),
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.grayWhite,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('DEMO', style: AppTypography.caption03),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            type,
            style: AppTypography.caption03.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            name,
            maxLines: 1,
            style: AppTypography.caption02.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
