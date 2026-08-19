// 근무표 기반 "목표 취침 vs 실측(데모) 취침" 격차(분) 계산 — `report_api.dart`
// (AI 리포트 POST body)와 홈 화면 하단 격차 추이 그래프가 공유한다.
//
// 데모 세션(매일 22:00 취침, 7시간)을 쓰는 이유는 report_api.dart 상단
// 주석과 동일 — HealthKit/Health Connect 연동 전까지의 임시값이다.
import 'package:shift_circadian_engine/nudge/circular_time.dart';
import 'package:shift_circadian_engine/nudge/nudge_engine.dart';
import 'package:shift_circadian_engine/roster/constants.dart';

List<SleepSession> demoSessionsForWindow(int windowDays) {
  return [
    for (var d = -10; d < windowDays; d++) SleepSession(d * 24.0 + 22.0, d * 24.0 + 29.0),
  ];
}

/// 최근(로스터 앞) [windowDays]일치 하루 단위 격차(분) — 실측이 목표보다
/// 늦으면 양수, 이르면 음수. -10일치 데모 이력을 항상 깔아두므로
/// `idealSleepTimes`의 오프-오프 폴백도 항상 이력을 찾아 값이 빈다.
List<int> gapMinutesSeries({
  required List<ShiftType> roster,
  required Map<ShiftType, ShiftTiming> shiftTimings,
  required double commuteMinutes,
  int windowDays = 14,
}) {
  final n = roster.length < windowDays ? roster.length : windowDays;
  final sessions = demoSessionsForWindow(n);
  final out = <int>[];
  for (var i = 0; i < n; i++) {
    final ideal = idealSleepTimes(
      roster: roster,
      todayIndex: i,
      shiftTimings: shiftTimings,
      commuteMinutes: commuteMinutes,
      recentSessions: sessions,
    );
    final actualBedtime = sessions[i + 10].startAt;
    final gap = circularShortestDiffHours(ideal.bedtime % 24.0, actualBedtime % 24.0) * 60.0;
    out.add(gap.round());
  }
  return out;
}
