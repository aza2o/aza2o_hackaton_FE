import 'package:flutter/material.dart';
import 'package:shift_circadian_engine/roster/constants.dart'
    show ShiftType, shiftTypeFromCode;

import '../engine/nudge_service.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/roster_calendar.dart';
import 'roster_upload_screen.dart';

/// 하단 탭의 "근무 달력". 온보딩의 근무표 확인 화면과 달리 **아무 달이나**
/// 넘겨볼 수 있다.
///
/// 저장된 로스터는 `rosterStartDate`를 앵커로 하는 평평한 배열이라, 화면에
/// 보이는 달의 각 날짜가 배열의 몇 번째인지는 시작일로부터의 일수로
/// 구한다. 배열 범위를 벗어나는 달(= 아직 업로드 안 한 달)은 빈 상태로
/// 두고 업로드를 유도한다 — 없는 근무를 오프로 채워 보여주면 사용자가
/// "오프로 등록돼 있다"고 오해하고, 그 값으로 넛지까지 계산돼버린다.
class RosterCalendarScreen extends StatefulWidget {
  const RosterCalendarScreen({super.key});

  @override
  State<RosterCalendarScreen> createState() => _RosterCalendarScreenState();
}

const _codeOf = {
  ShiftType.day: 'D',
  ShiftType.evening: 'E',
  ShiftType.night: 'N',
  ShiftType.off: 'O',
};

class _RosterCalendarScreenState extends State<RosterCalendarScreen> {
  /// 보고 있는 달의 1일.
  late DateTime _month = _initialMonth();

  static DateTime _initialMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  int get _daysInMonth => DateTime(_month.year, _month.month + 1, 0).day;
  int get _startOffset => (_month.weekday - 1) % 7;

  /// 이 달의 날짜(1-based) → 저장된 로스터 배열 인덱스. 범위 밖이면 null.
  int? _rosterIndexFor(int day) {
    final s = AppState.instance;
    final start = s.rosterStartDate;
    final roster = s.roster;
    if (start == null || roster == null) return null;
    final date = DateTime(_month.year, _month.month, day);
    if (s.isDemoAccount &&
        (date.isBefore(DateTime(2026, 7, 1)) ||
            date.isAfter(DateTime(2026, 9, 30)))) {
      return null;
    }
    final idx = date.difference(start).inDays;
    return (idx >= 0 && idx < roster.length) ? idx : null;
  }

  /// 화면에 그릴 코드 목록. 데이터가 하나도 없으면 null.
  List<String>? get _codes {
    final roster = AppState.instance.roster;
    if (roster == null) return null;
    final out = <String>[];
    var any = false;
    for (var d = 1; d <= _daysInMonth; d++) {
      final idx = _rosterIndexFor(d);
      if (idx == null) {
        out.add('O');
      } else {
        any = true;
        out.add(_codeOf[roster[idx]]!);
      }
    }
    return any ? out : null;
  }

  /// 이 달에 오늘이 들어있으면 0-based 인덱스.
  int? get _todayIndex {
    final now = DateTime.now();
    if (now.year != _month.year || now.month != _month.month) return null;
    return now.day - 1;
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  Future<void> _editDay(int day) async {
    final idx = _rosterIndexFor(day + 1);
    final s = AppState.instance;
    final roster = s.roster;
    // 업로드된 범위 밖의 날짜는 편집 대상이 아니다 — 배열을 늘리면
    // 시작일 앵커와 어긋나서 홈의 "오늘" 계산이 통째로 밀린다.
    if (idx == null || roster == null) return;

    final next = nextShiftCode(_codeOf[roster[idx]]!);
    final updated = List.of(roster)..[idx] = shiftTypeFromCode(next);
    s.saveRoster(updated, startDate: s.rosterStartDate!);
    setState(() {});

    // 근무가 바뀌면 목표 취침도 바뀌므로 예약된 알림을 다시 건다.
    await NotificationService.instance.rescheduleAll(
      await loadUpcomingNudgeTriggers(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final codes = _codes;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: '이전 달',
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${_month.year}년 ${_month.month}월',
                      style: AppTypography.heading04,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: '다음 달',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (codes != null)
              Text(
                '날짜를 눌러 근무를 바꿀 수 있어요',
                style: AppTypography.caption01.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            const WeekdayHeader(),
            const SizedBox(height: AppSpacing.xs),
            if (codes == null)
              _EmptyMonth(month: _month.month)
            else ...[
              CalendarGrid(
                shifts: codes,
                startOffset: _startOffset,
                highlightDay: _todayIndex,
                onTapDay: _editDay,
              ),
              const SizedBox(height: AppSpacing.lg),
              const ShiftLegend(),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyMonth extends StatelessWidget {
  const _EmptyMonth({required this.month});
  final int month;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          Icon(
            Icons.event_busy_outlined,
            size: 40,
            color: AppColors.textPlaceholder,
          ),
          const SizedBox(height: AppSpacing.md),
          Text('$month월 근무표가 아직 없어요', style: AppTypography.subtitle04),
          const SizedBox(height: 4),
          Text(
            '근무표를 올리면 이 달의 넛지도 계산해드려요',
            textAlign: TextAlign.center,
            style: AppTypography.caption01.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary500,
                foregroundColor: AppColors.gray900,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RosterUploadScreen()),
              ),
              child: Text('근무표 올리기', style: AppTypography.button03),
            ),
          ),
        ],
      ),
    );
  }
}
