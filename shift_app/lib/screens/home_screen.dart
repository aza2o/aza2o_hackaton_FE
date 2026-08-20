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
import 'settings_screen.dart';

/// "최근 회복 상태" 카드에 쓰는 값 — 조회 실패·타임아웃·데이터 없음을 모두
/// null로 통일한다(§6-3-c와 같은 원칙: 선택 데이터라 실패해도 화면을 막지
/// 않는다).
class _RecoveryStats {
  const _RecoveryStats({this.sleepDuration, this.hrvZScore, this.restingBpm, this.daylightMinutes});
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
  final daylight = source.capabilities.hasDaylight ? await source.daylight(DateRange(today, now)) : null;

  return _RecoveryStats(
    sleepDuration: sessions.isEmpty ? null : sessions.last.end.difference(sessions.last.start),
    hrvZScore: hrv == null || hrv.points.isEmpty ? null : hrv.points.last.$2,
    restingBpm: restingHr == null || restingHr.points.isEmpty ? null : restingHr.points.last.$2,
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

String _formatHrv(double? z) => z == null ? '—' : '${z >= 0 ? '+' : ''}${z.toStringAsFixed(1)}σ';

String _formatBpm(double? bpm) => bpm == null ? '—' : '${bpm.round()}bpm';

String _formatDaylight(double? minutes) {
  if (minutes == null) return '—';
  if (minutes < 60) return '${minutes.round()}분';
  return '${(minutes / 60).toStringAsFixed(1)}h';
}

const _weekdaysKo = ['월', '화', '수', '목', '금', '토', '일'];
String _formatTodayKo(DateTime d) => '${d.month}월 ${d.day}일 ${_weekdaysKo[d.weekday - 1]}요일';
String _fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

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
  late Future<List<int>> _gapFuture;
  late final HealthSignalSource _healthSource = widget.healthSource ??
      (defaultTargetPlatform == TargetPlatform.android ? AndroidHealthSource() : IosHealthSource());
  late Future<_RecoveryStats> _recoveryFuture;

  // 행동별 완료 체크 — 인메모리 상태다(§ AppState와 동일하게 영구저장 전까지는
  // 앱 재시작 시 초기화됨). `data.actions`의 인덱스로 식별한다.
  final Set<int> _completedActions = {};

  @override
  void initState() {
    super.initState();
    _future = loadTodayNudges();
    _alertFuture = loadAlertness();
    _gapFuture = _alertFuture.then((r) => gapMinutesSeries(
          roster: r.roster,
          shiftTimings: r.profile.shiftTimings,
          commuteMinutes: r.profile.commuteMinutes,
        ));
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
                            Text(_formatTodayKo(DateTime.now()),
                                style: AppTypography.caption01
                                    .copyWith(color: AppColors.textTertiary)),
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
                          MaterialPageRoute(builder: (_) => const SettingsScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  if (snapshot.hasError)
                    SizedBox(
                      height: 160,
                      child: Center(
                        child: Text('오늘의 계획을 불러오지 못했어요\n${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: AppTypography.body02.copyWith(color: AppColors.error01)),
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
                        if (!_completedActions.add(i)) _completedActions.remove(i);
                      }),
                      onLogBedtime: () => setState(() => AppState.instance.logBedtimeIntent()),
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
                            color: AppColors.information03.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('지금이 오늘 중 컨디션이 가장 낮은 시간대예요',
                              style: AppTypography.caption01.copyWith(color: AppColors.textPrimary)),
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
                      final stats = recoverySnapshot.data ?? _RecoveryStats.empty;
                      final showDaylight = _healthSource.capabilities.hasDaylight;
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
                            child: _RecoveryTile(label: 'HRV', value: _formatHrv(stats.hrvZScore)),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _RecoveryTile(label: '안정심박', value: _formatBpm(stats.restingBpm)),
                          ),
                          if (showDaylight) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _RecoveryTile(label: '일광 노출', value: _formatDaylight(stats.daylightMinutes)),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text('최근 2주 취침 격차', style: AppTypography.subtitle04),
                  const SizedBox(height: 4),
                  Text('목표 취침 대비 몇 분 늦거나 일렀는지',
                      style: AppTypography.caption02.copyWith(color: AppColors.textTertiary)),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    child: FutureBuilder<List<int>>(
                      future: _gapFuture,
                      builder: (context, gapSnapshot) {
                        final gaps = gapSnapshot.data;
                        if (gapSnapshot.hasError) {
                          return const SizedBox(
                            height: 120,
                            child: Center(child: Text('격차 추이를 불러오지 못했어요')),
                          );
                        }
                        // 다른 보조 섹션(최근 회복 상태 등)과 같은 원칙 —
                        // 선택 데이터라 로딩 중에도 스피너 없이 빈 자리만
                        // 유지한다(레이아웃 점프만 방지).
                        if (gaps == null || gaps.isEmpty) {
                          return const SizedBox(height: 120);
                        }
                        return _GapTrendChart(gapMinutes: gaps);
                      },
                    ),
                  ),
                  // AI 인사이트와 피부 루틴은 별도 화면으로 들어가야
                  // 볼 수 있었다 — 탭 두 번을 없애고 여기 바로 편다.
                  const SizedBox(height: AppSpacing.xxl),
                  const _InsightSection(),
                  const SizedBox(height: AppSpacing.xxl),
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

/// 최근 2주(최대 14일)치 "목표 취침 - 실측 취침" 격차(분) 라인차트.
/// 데이터는 `gap_service.dart`(AI 리포트 POST body와 동일 소스) 재사용.
class _GapTrendChart extends StatelessWidget {
  const _GapTrendChart({required this.gapMinutes});
  final List<int> gapMinutes;

  @override
  Widget build(BuildContext context) {
    final maxAbs = gapMinutes.map((g) => g.abs()).fold<int>(30, (a, b) => a > b ? a : b);
    final bound = (maxAbs / 10).ceil() * 10 + 10;

    return SizedBox(
      height: 140,
      child: LineChart(
        LineChartData(
          minY: -bound.toDouble(),
          maxY: bound.toDouble(),
          minX: 0,
          maxX: (gapMinutes.length - 1).toDouble(),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(y: 0, color: AppColors.gray300, strokeWidth: 1),
          ]),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: bound.toDouble(),
                getTitlesWidget: (value, meta) => Text('${value.round()}분',
                    style: AppTypography.caption03.copyWith(color: AppColors.textPlaceholder)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                interval: (gapMinutes.length / 4).ceilToDouble(),
                getTitlesWidget: (value, meta) => Text('${value.round() + 1}일',
                    style: AppTypography.caption03.copyWith(color: AppColors.textPlaceholder)),
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map((s) => LineTooltipItem('${s.y.round()}분', AppTypography.caption02))
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < gapMinutes.length; i++)
                  FlSpot(i.toDouble(), gapMinutes[i].toDouble()),
              ],
              isCurved: false,
              color: AppColors.information01,
              barWidth: 2,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: false),
            ),
          ],
        ),
      ),
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
  });

  final bool isNight;
  final TodayNudges data;
  final Set<int> completedActions;
  final ValueChanged<int> onToggleAction;
  final VoidCallback onLogBedtime;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.xxl),
          decoration: BoxDecoration(
            color: AppColors.gray800,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.headerLabel,
                style: AppTypography.caption01.copyWith(
                  color: isNight ? AppColors.information03 : AppColors.primary400,
                ),
              ),
              const SizedBox(height: 4),
              Text(data.planLabel,
                  style: AppTypography.heading01.copyWith(color: AppColors.grayWhite)),
              if (data.summary.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(data.summary,
                    style: AppTypography.body02.copyWith(color: AppColors.gray300)),
              ],
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.grayWhite,
                    side: const BorderSide(color: AppColors.gray600),
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  ),
                  onPressed: onLogBedtime,
                  child: const Text('지금 누웠어요'),
                ),
              ),
              if (AppState.instance.bedtimeIntents.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '오늘 ${_fmtTime(AppState.instance.bedtimeIntents.first.at)}에 기록했어요',
                  style: AppTypography.caption03.copyWith(color: AppColors.gray400),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Text('오늘의 행동', style: AppTypography.subtitle04),
        const SizedBox(height: AppSpacing.sm),
        if (data.actions.isEmpty)
          Text('지금 시점에 남은 넛지가 없어요.',
              style: AppTypography.body02.copyWith(color: AppColors.textTertiary))
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
  const _ActionRow({required this.action, required this.completed, required this.onToggle});
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
    final textDecoration = completed ? TextDecoration.lineThrough : TextDecoration.none;

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
                Text(action.time,
                    style: AppTypography.body02.copyWith(
                        color: completed ? AppColors.gray400 : AppColors.textPrimary,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(statusLabel,
                    style: AppTypography.caption03
                        .copyWith(color: statusColor, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.label,
                    style: AppTypography.body02
                        .copyWith(color: textColor, decoration: textDecoration)),
                const SizedBox(height: 2),
                Text(action.message,
                    style: AppTypography.caption02.copyWith(
                        color: completed ? AppColors.gray400 : AppColors.textTertiary,
                        decoration: textDecoration)),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: completed ? AppColors.success01 : AppColors.textSecondary,
              side: BorderSide(color: completed ? AppColors.success01 : AppColors.gray200),
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
          Text(label,
              style: AppTypography.caption02
                  .copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: 4),
          Text(value, style: AppTypography.subtitle03.copyWith(color: AppColors.textPrimary)),
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
  const _InsightSection();

  @override
  State<_InsightSection> createState() => _InsightSectionState();
}

class _InsightSectionState extends State<_InsightSection> {
  Future<String>? _future;

  @override
  void initState() {
    super.initState();
    final s = AppState.instance;
    if (s.aiConsent && !s.hasFreshAiComment) _future = _fetch();
  }

  Future<String> _fetch() async {
    final r = await loadAlertness();
    final res = await fetchAiReport(roster: r.roster, profile: r.profile);
    AppState.instance.saveAiComment(res.comment);
    return res.comment;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('오늘의 인사이트', style: AppTypography.subtitle04),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiReportScreen()),
              ),
              child: Text('리듬 자세히 보기',
                  style: AppTypography.caption02
                      .copyWith(color: AppColors.textSecondary)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: !s.aiConsent
              ? Text(
                  '설정 > AI 리포트에서 동의하면 오늘의 리듬을 읽고 코멘트를 드려요.',
                  style: AppTypography.body02
                      .copyWith(color: AppColors.textTertiary),
                )
              : s.hasFreshAiComment
                  ? Text(s.aiComment!,
                      style: AppTypography.body02
                          .copyWith(color: AppColors.textSecondary, height: 1.6))
                  : FutureBuilder<String>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Text('인사이트를 불러오지 못했어요',
                              style: AppTypography.body02
                                  .copyWith(color: AppColors.textTertiary));
                        }
                        if (!snap.hasData) {
                          return const SizedBox(
                            height: 40,
                            child: Center(
                                child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        return Text(snap.data!,
                            style: AppTypography.body02.copyWith(
                                color: AppColors.textSecondary, height: 1.6));
                      },
                    ),
        ),
      ],
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
        Text('무엇을 바르는지가 아니라 언제 바르는지를 제안해요',
            style: AppTypography.caption02
                .copyWith(color: AppColors.textTertiary)),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: Column(
            children: [
              _RoutineRow(
                time: routine.wakeLabel,
                title: '주간 보호 루틴',
                desc: '기상 직후',
              ),
              const Divider(height: AppSpacing.xxl, color: AppColors.gray100),
              _RoutineRow(
                time: routine.bedtimeLabel,
                title: '야간 보습 루틴',
                desc: '취침 전',
              ),
              if (routine.isNightShift && routine.commuteLabel != null) ...[
                const Divider(height: AppSpacing.xxl, color: AppColors.gray100),
                _RoutineRow(
                  time: routine.commuteLabel!,
                  title: '퇴근길 선글라스',
                  desc: '위상 전진 방지 + UV 차단',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({
    required this.time,
    required this.title,
    required this.desc,
  });

  final String time;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 58,
          child: Text(time, style: AppTypography.subtitle03),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.body02),
              const SizedBox(height: 2),
              Text(desc,
                  style: AppTypography.caption02
                      .copyWith(color: AppColors.textTertiary)),
            ],
          ),
        ),
      ],
    );
  }
}
