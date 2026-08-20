// 근무표 기반 "목표 취침 vs 실측(데모) 취침" 격차(분) 계산 — `report_api.dart`
// (AI 리포트 POST body)와 홈 화면 하단 격차 추이 그래프가 공유한다.
//
// 데모 세션은 교대근무자의 불규칙한 취침과 수면 길이를 재현한다.
import 'package:shift_circadian_engine/nudge/circular_time.dart';
import 'package:shift_circadian_engine/nudge/nudge_engine.dart';
import 'package:shift_circadian_engine/roster/constants.dart';

import 'dart:math' as math;

const int _demoSeed = 20260821;

double _demoStartFor(int day) {
  final random = math.Random(_demoSeed + day * 7919);
  const anchors = [23.2, 23.8, 24.3, 8.4, 9.0, 24.1, 23.5];
  return anchors[(day + 70) % anchors.length] +
      (random.nextInt(41) - 20) / 60.0;
}

int _demoDurationFor(ShiftType shift, int day) {
  final random = math.Random(_demoSeed + day * 104729);
  return switch (shift) {
    ShiftType.day => 375 + random.nextInt(66), // 6h15m~7h20m
    ShiftType.evening => 390 + random.nextInt(61), // 6h30m~7h30m
    ShiftType.night => 330 + random.nextInt(81), // 5h30m~6h50m
    ShiftType.off => 420 + random.nextInt(76), // 7h00m~8h15m
  };
}

List<SleepSession> demoSessionsForWindow(int windowDays) {
  return [
    for (var d = -10; d < windowDays; d++)
      SleepSession(
        d * 24.0 + _demoStartFor(d),
        d * 24.0 +
            _demoStartFor(d) +
            _demoDurationFor(
                  ShiftType.values[(d + 70) % ShiftType.values.length],
                  d,
                ) /
                60.0,
      ),
  ];
}

class SleepDurationDay {
  const SleepDurationDay({
    required this.targetMinutes,
    required this.actualMinutes,
  });

  final int targetMinutes;
  final int actualMinutes;
  int get deficitMinutes => targetMinutes - actualMinutes;
}

/// 시뮬레이터용 개인 권장 수면량 추정. 근무 유형별 기본 수면량에 직전까지
/// 누적된 부족분의 25%(최대 45분)를 회복분으로 더한다. 실제 워치 연동 후에는
/// [actualMinutes]만 HealthKit/Health Connect 세션으로 교체할 수 있다.
List<SleepDurationDay> sleepDurationSeries({
  required List<ShiftType> roster,
  int windowDays = 14,
}) {
  final n = roster.length < windowDays ? roster.length : windowDays;
  var carriedDebt = 0;
  final out = <SleepDurationDay>[];

  for (var i = 0; i < n; i++) {
    final baseTarget = switch (roster[i]) {
      ShiftType.night || ShiftType.off => 8 * 60,
      ShiftType.day || ShiftType.evening => 7 * 60 + 30,
    };
    final recovery = (carriedDebt * 0.25).round().clamp(0, 45);
    final target = baseTarget + recovery;
    final actual = _demoDurationFor(roster[i], i);
    final day = SleepDurationDay(targetMinutes: target, actualMinutes: actual);
    out.add(day);

    carriedDebt += day.deficitMinutes;
    if (carriedDebt < 0) carriedDebt = 0;
    if (carriedDebt > 240) carriedDebt = 240;
  }
  return out;
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
    final gap =
        circularShortestDiffHours(ideal.bedtime % 24.0, actualBedtime % 24.0) *
        60.0;
    out.add(gap.round());
  }
  return out;
}
