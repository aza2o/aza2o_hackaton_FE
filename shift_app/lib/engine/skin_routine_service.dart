// 피부 루틴 타이밍 — `SHIFT_skin_track_plan.md` F1(생체 루틴 타이밍),
// F2(퇴근길 자외선 알림).
//
// 예전엔 화면에 시각이 하드코딩돼 있었다("14:30", "07:00"). "오늘 당신의
// 기상·취침 시각 기준으로 제안해요"라고 써놓고 실제로는 근무표와 무관한
// 고정 문자열이었고, 그래서 14:30에 "AM" 같은 표기까지 붙어 있었다.
// 여기서 실제 수면 창으로 계산한다.
import 'package:shift_circadian_engine/roster/constants.dart' show ShiftType;
import 'alertness_service.dart';
import 'gap_service.dart';

class SkinRoutine {
  const SkinRoutine({
    required this.wakeLabel,
    required this.bedtimeLabel,
    required this.isNightShift,
    required this.commuteLabel,
    required this.shiftLabel,
    required this.upcomingNightCount,
    required this.isRecoveryMode,
    required this.todayDeficitMinutes,
  });

  /// 기상 직후 — 주간 보호 루틴 시각. 예: "07:20"
  final String wakeLabel;

  /// 취침 전 — 야간 보습 루틴 시각. 예: "22:40"
  final String bedtimeLabel;

  /// 오늘이 나이트 근무인지 — 퇴근길 자외선 항목은 나이트 전용이다
  /// (아침 햇빛이 위상을 앞당겨버리는 걸 막는 게 목적).
  final bool isNightShift;

  /// 나이트일 때 퇴근 예정 시각. 예: "07:00"
  final String? commuteLabel;

  /// 오늘 루틴을 계산한 근무 유형. 피부 상태를 진단하는 값이 아니라,
  /// 어떤 로스터를 기준으로 시각을 옮겼는지 설명하기 위한 값이다.
  final String shiftLabel;

  /// 오늘부터 최대 14일 동안 예정된 나이트 횟수. 사후 피부 평가가 아니라
  /// 확정된 미래 로스터를 이용한 선제 루틴 안내에만 쓴다.
  final int upcomingNightCount;

  /// 시뮬레이터에서는 목업 워치 수면, 실기기에서는 실제 수면 세션으로
  /// 교체될 값. 60분 이상 부족할 때 복잡한 루틴보다 단순한 장벽 루틴을
  /// 제안한다. 피부 상태를 진단하는 값은 아니다.
  final bool isRecoveryMode;
  final int todayDeficitMinutes;
}

/// [r]의 오늘 수면 창에서 루틴 시각을 뽑는다. 오늘 수면 창을 못 찾으면
/// null — 화면은 이 경우 섹션을 그리지 않는다(추측한 시각을 보여주느니
/// 안 보여주는 게 낫다).
SkinRoutine? skinRoutineFrom(AlertnessResult r, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final dayIndex = DateTime(today.year, today.month, today.day)
      .difference(r.startDate)
      .inDays;
  if (dayIndex < 0 || dayIndex >= r.roster.length) return null;

  final dayStart = dayIndex * 24.0;
  // 오늘 자정~다음 자정 사이에 시작하는 주 수면 창.
  final main = r.sleep.where(
    (w) => w.kind == 'main' && w.start >= dayStart && w.start < dayStart + 24,
  );
  if (main.isEmpty) return null;
  final w = main.first;

  final shift = r.roster[dayIndex];
  final isNight = shift == ShiftType.night;
  final shiftLabel = switch (shift) {
    ShiftType.day => '데이 근무',
    ShiftType.evening => '이브닝 근무',
    ShiftType.night => '나이트 근무',
    ShiftType.off => '오프',
  };
  final windowEnd = (dayIndex + 14).clamp(0, r.roster.length);
  final upcomingNightCount = r.roster
      .sublist(dayIndex, windowEnd)
      .where((s) => s == ShiftType.night)
      .length;
  final sleepDay = sleepDurationSeries(
    roster: r.roster,
    windowDays: dayIndex + 1,
  )[dayIndex];
  final todayDeficitMinutes = sleepDay.deficitMinutes > 0
      ? sleepDay.deficitMinutes
      : 0;

  String? commute;
  if (isNight) {
    // 나이트 종료 시각 = 퇴근. shiftTimings의 end는 24를 넘길 수 있다.
    final timing = r.profile.shiftTimings[ShiftType.night];
    if (timing != null) commute = _hhmm(timing.start + timing.duration);
  }

  return SkinRoutine(
    wakeLabel: _hhmm(w.end),
    bedtimeLabel: _hhmm(w.start),
    isNightShift: isNight,
    commuteLabel: commute,
    shiftLabel: shiftLabel,
    upcomingNightCount: upcomingNightCount,
    isRecoveryMode: todayDeficitMinutes >= 60,
    todayDeficitMinutes: todayDeficitMinutes,
  );
}

/// 절대시간(h)을 그날의 벽시계 HH:mm으로. 24시간 표기를 쓴다 —
/// AM/PM을 붙였다가 14:30에 "AM"이 달리는 버그가 있었다.
String _hhmm(double absHours) {
  final inDay = absHours % 24.0;
  var h = inDay.floor();
  var m = ((inDay - h) * 60).round();
  if (m == 60) {
    m = 0;
    h = (h + 1) % 24;
  }
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}
