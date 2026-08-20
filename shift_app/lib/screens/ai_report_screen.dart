import 'package:flutter/material.dart';
import 'package:shift_circadian_engine/nudge/circular_time.dart';
import 'package:shift_circadian_engine/nudge/nudge_engine.dart';
import 'package:shift_circadian_engine/roster/constants.dart' show ShiftType;
import '../engine/alertness_service.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_card.dart';
import '../widgets/actogram_painter.dart';
import '../services/report_api.dart';

double _clip(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

List<(double, double)> _windowsIn(List<(double, double)> src, double dayStart, double dayEnd) {
  final out = <(double, double)>[];
  for (final (s, e) in src) {
    if (e <= dayStart || s >= dayEnd) continue;
    out.add((_clip(s, dayStart, dayEnd) - dayStart, _clip(e, dayStart, dayEnd) - dayStart));
  }
  return out;
}

/// [_buildRows] 결과 — 행 목록 + 목표 취침과 가장 크게 어긋난 날(있다면).
class _ActogramData {
  const _ActogramData(this.rows, this.calloutDate, this.calloutGapMin);
  final List<ActogramRow> rows;
  final DateTime? calloutDate;
  final int? calloutGapMin;
}

/// [AlertnessResult]를 이중 플롯(0~48h) 액토그램 행으로 변환한다. 세그먼트
/// 탭(주간/월간/근무루틴별)은 아직 실제 필터링에 안 이어져 있어(TODO),
/// 지금은 로스터 앞 7일만 보여준다.
///
/// 목표 취침(`idealSleepTimes`)은 실제 수면 이력이 아니라 [r.sleep](근무표
/// 기반 예측 수면)을 폴백 이력으로 재사용한다 — 아직 헬스 연동 전이라
/// `report_api.dart`의 데모 세션과 마찬가지로 근사치다.
_ActogramData _buildRows(AlertnessResult r) {
  final n = r.roster.length < 7 ? r.roster.length : 7;
  final rows = <ActogramRow>[];
  final sleepAbs = [for (final w in r.sleep) (w.start, w.end)];
  final recentSessions = [for (final w in r.sleep) SleepSession(w.start, w.end)];

  DateTime? calloutDate;
  int? calloutGapMin;

  for (var i = 0; i < n; i++) {
    final dayStart = i * 24.0;
    final dayEnd = dayStart + 48.0;
    final shift = r.roster[i];

    var workWindows = const <(double, double)>[];
    if (shift != ShiftType.off) {
      final timing = r.profile.shiftTimings[shift]!;
      final start = dayStart + timing.start;
      workWindows = _windowsIn([(start, start + timing.duration)], dayStart, dayEnd);
    }

    var dlmoHour = 24.0;
    final inRange = r.dlmos.where((d) => d >= dayStart && d < dayEnd);
    if (inRange.isNotEmpty) {
      dlmoHour = inRange.first - dayStart;
    } else if (r.dlmos.isNotEmpty) {
      final nearest =
          r.dlmos.reduce((a, b) => (a - (dayStart + 24)).abs() < (b - (dayStart + 24)).abs() ? a : b);
      dlmoHour = _clip(nearest - dayStart, 0, 48);
    }

    final sleepWindows = _windowsIn(sleepAbs, dayStart, dayEnd);

    double? idealBedtimeHour;
    try {
      final ideal = idealSleepTimes(
        roster: r.roster,
        todayIndex: i,
        shiftTimings: r.profile.shiftTimings,
        commuteMinutes: r.profile.commuteMinutes,
        recentSessions: recentSessions,
      );
      idealBedtimeHour = _clip(ideal.bedtime - dayStart, 0, 48);

      if (sleepWindows.isNotEmpty) {
        final actualStart = sleepWindows.first.$1 + dayStart;
        final gapMin =
            (circularShortestDiffHours(ideal.bedtime % 24.0, actualStart % 24.0) * 60).round();
        if (calloutGapMin == null || gapMin.abs() > calloutGapMin.abs()) {
          calloutGapMin = gapMin;
          calloutDate = r.startDate.add(Duration(days: i));
        }
      }
    } on ArgumentError {
      idealBedtimeHour = null; // 양쪽 다 오프인 첫날 등, 폴백에 쓸 이력이 없음
    }

    final date = r.startDate.add(Duration(days: i));

    rows.add(ActogramRow(
      label: '${date.month}/${date.day}',
      sleep: sleepWindows,
      work: workWindows,
      dlmoHour: dlmoHour,
      riskWindows: _windowsIn(r.riskWindows, dayStart, dayEnd),
      idealBedtimeHour: idealBedtimeHour,
    ));
  }
  return _ActogramData(rows, calloutDate, calloutGapMin);
}

/// AI 리포트 (Figma 신규 파일 `13:2`). 주간/월간/근무루틴별 세그먼트 +
/// 액토그램. 넛지 예상효과는 아주 작은 캡션으로만 노출(확정 원칙,
/// 공식 홈 화면의 "완료 버튼" 넛지 UI와는 별개로 취급).
class AiReportScreen extends StatefulWidget {
  const AiReportScreen({super.key});

  @override
  State<AiReportScreen> createState() => _AiReportScreenState();
}

class _AiReportScreenState extends State<AiReportScreen> {
  int _segment = 0;
  static const _segments = ['주간', '월간', '근무루틴별'];
  late Future<AlertnessResult> _future;
  Future<AiReportResult>? _reportFuture;

  final _noteController = TextEditingController();

  /// 빠른 선택 — 매번 타이핑하게 만들면 아무도 안 쓴다.
  static const _quickStates = [
    '많이 피곤해요',
    '잠이 잘 안 와요',
    '자다가 자꾸 깨요',
    '두통이 있어요',
    '오늘은 괜찮아요',
  ];
  final _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _future = loadAlertness();
    // 동의 전에는 외부(Gemini) 호출을 하지 않는다 — 화면을 열었다는
    // 이유만으로 데이터가 국외로 나가면 안 된다.
    // (initState에서는 setState를 거치지 않고 바로 넣는다.)
    if (AppState.instance.aiConsent) _reportFuture = _buildReportFuture();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  /// 선택한 칩 + 자유 입력을 한 문장으로 합친다.
  String get _stateNote {
    final typed = _noteController.text.trim();
    return [..._selected, if (typed.isNotEmpty) typed].join(', ');
  }

  Future<AiReportResult> _buildReportFuture() => _future.then((r) => fetchAiReport(
        roster: r.roster,
        profile: r.profile,
        stateNote: _stateNote.isEmpty ? null : _stateNote,
      ));

  void _requestReport() {
    setState(() => _reportFuture = _buildReportFuture());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 리포트')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _SegmentedControl(
              labels: _segments,
              index: _segment,
              onChanged: (i) => setState(() => _segment = i),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('이번 주 리듬', style: AppTypography.subtitle02),
                  const SizedBox(height: 4),
                  Text('근무 · 수면 · 예측 DLMO',
                      style: AppTypography.caption02
                          .copyWith(color: AppColors.textTertiary)),
                  const SizedBox(height: AppSpacing.lg),
                  FutureBuilder<AlertnessResult>(
                    future: _future,
                    builder: (context, snapshot) {
                      final result = snapshot.data;
                      if (snapshot.hasError) {
                        return Text('리듬 계산에 실패했어요\n${snapshot.error}',
                            style: AppTypography.caption01.copyWith(color: AppColors.error01));
                      }
                      if (result == null) {
                        return const SizedBox(
                            height: 160, child: Center(child: CircularProgressIndicator()));
                      }
                      final data = _buildRows(result);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ActogramTimeAxis(),
                          const SizedBox(height: 2),
                          ActogramView(rows: data.rows),
                          if (data.calloutDate != null && data.calloutGapMin != null) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _GapCallout(date: data.calloutDate!, gapMin: data.calloutGapMin!),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.lg,
                    runSpacing: 4,
                    children: [
                      _LegendDot(color: AppColors.gray700, label: '수면'),
                      _LegendDot(color: AppColors.primary300, label: '근무(광노출)'),
                      _LegendDot(color: AppColors.primary900, label: '예측 DLMO'),
                      _LegendDot(color: AppColors.information01, label: '목표 취침'),
                      _LegendDot(color: AppColors.error01, label: '컨디션 저하 구간'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text('지금 상태를 알려주세요', style: AppTypography.subtitle03),
            const SizedBox(height: 4),
            Text('적어주시면 계산 결과와 함께 읽고 오늘 할 일을 골라드려요',
                style: AppTypography.caption02
                    .copyWith(color: AppColors.textTertiary)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final s in _quickStates)
                  _StateChip(
                    label: s,
                    selected: _selected.contains(s),
                    onTap: () => setState(() {
                      if (!_selected.add(s)) _selected.remove(s);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _noteController,
              maxLength: stateNoteMaxLength,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: '직접 적기 (예: 어제 나이트 끝나고 3시간밖에 못 잤어요)',
                hintStyle: AppTypography.caption01
                    .copyWith(color: AppColors.textPlaceholder),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary500,
                  foregroundColor: AppColors.gray900,
                  disabledBackgroundColor: AppColors.gray100,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed:
                    AppState.instance.aiConsent ? _requestReport : null,
                child: Text('이 상태로 조언 받기', style: AppTypography.button03),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text('이번 주 인사이트', style: AppTypography.subtitle03),
            const SizedBox(height: AppSpacing.sm),
            if (!AppState.instance.aiConsent)
              const _AiConsentNotice()
            else
            FutureBuilder<AiReportResult>(
              future: _reportFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('인사이트를 불러오지 못했어요',
                      style: AppTypography.body02.copyWith(color: AppColors.error01));
                }
                final result = snapshot.data;
                if (result == null) {
                  return const SizedBox(
                      height: 20, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                }
                return Text(result.comment,
                    style: AppTypography.body02.copyWith(color: AppColors.textSecondary));
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            _TinyEffectLine('밝은 빛 노출 · DLMO 평균 25분 지연'),
            _TinyEffectLine('퇴근길 차광 · 수면 진입 보호 효과 확인'),
          ],
        ),
      ),
    );
  }
}

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: Container(
                  decoration: BoxDecoration(
                    color: i == index ? AppColors.grayWhite : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: i == index
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(labels[i],
                      style: (i == index
                              ? AppTypography.subtitle04
                              : AppTypography.body02)
                          .copyWith(
                              color: i == index
                                  ? AppColors.textPrimary
                                  : AppColors.textTertiary)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 목표 취침과 가장 크게 어긋난 날을 직접 짚어주는 콜아웃 — "이번 주
/// 인사이트" 문단과 별개로, 그래프 바로 아래서 특정 날짜를 가리킨다.
class _GapCallout extends StatelessWidget {
  const _GapCallout({required this.date, required this.gapMin});
  final DateTime date;
  final int gapMin;

  @override
  Widget build(BuildContext context) {
    final isLate = gapMin >= 0;
    final abs = gapMin.abs();
    return Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 14, color: AppColors.information01),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '${date.month}/${date.day} · 목표 취침보다 $abs분 ${isLate ? '늦게' : '일찍'} 잠들었어요',
            style: AppTypography.caption02.copyWith(color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: AppTypography.caption02.copyWith(color: AppColors.textTertiary)),
      ],
    );
  }
}

class _TinyEffectLine extends StatelessWidget {
  const _TinyEffectLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
                color: AppColors.textPlaceholder, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(text,
              style: AppTypography.caption03.copyWith(color: AppColors.textPlaceholder)),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary500 : AppColors.grayWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary500 : AppColors.gray100),
        ),
        child: Text(label,
            style: AppTypography.caption01.copyWith(
              color: selected ? AppColors.gray900 : AppColors.textSecondary,
            )),
      ),
    );
  }
}

/// 국외 이전 동의를 안 한 경우 — 호출 대신 이유를 보여준다.
class _AiConsentNotice extends StatelessWidget {
  const _AiConsentNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AI 인사이트는 동의가 필요해요', style: AppTypography.subtitle04),
          const SizedBox(height: 4),
          Text(
            '리포트 문구를 만들려면 근무·수면 요약을 Google(Gemini)로 보내야 해요. '
            '설정 > AI 리포트에서 동의하면 바로 사용할 수 있어요.',
            style: AppTypography.caption01
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
