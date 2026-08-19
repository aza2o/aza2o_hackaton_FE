/// `nudge/` 넛지 계산층 테스트.
///
/// `룰엔진_규칙_v2.md`에는 Python 참조 구현이 없어(순수 스펙 문서) 다른
/// 레이어처럼 골든 벡터 대조가 불가능하다 — 대신 문서에 명시된 공식을
/// 손으로 재계산한 값과 대조한다. 순환평균/최단거리는 문서가 "틀리면
/// 테스트로 잘 안 잡힌다"고 직접 경고한 지점이라 별도로 검증한다.
library nudge_engine_test;

import 'package:test/test.dart';
import '../lib/roster/constants.dart';
import '../lib/nudge/circular_time.dart';
import '../lib/nudge/nudge_constants.dart';
import '../lib/nudge/nudge_engine.dart';

void expectClose(double actual, double expected, {double tol = 1e-6, String? reason}) {
  expect((actual - expected).abs() < tol, isTrue,
      reason: '${reason ?? ''} expected=$expected actual=$actual diff=${(actual - expected).abs()}');
}

void main() {
  group('circular_time', () {
    test('circularMeanHours: 23:00과 01:00의 순환평균은 00:00 (산술평균 12:00 아님)', () {
      expectClose(circularMeanHours([23.0, 1.0]), 0.0, tol: 1e-9);
    });

    test('circularShortestDiffHours: 04:00 -> 22:00 은 +18이 아니라 -6', () {
      expectClose(circularShortestDiffHours(4.0, 22.0), -6.0);
    });

    test('circularShortestDiffHours: 23:50 -> 00:10 은 +20분 (자정을 넘어가는 최단경로)', () {
      expectClose(circularShortestDiffHours(23.0 + 50.0 / 60.0, 10.0 / 60.0), 20.0 / 60.0);
    });

    test('circularStdHours: 모두 같은 시각이면 0', () {
      expectClose(circularStdHours([23.0, 23.0, 23.0]), 0.0, tol: 1e-9);
    });

    test('circularStdHours: 23:00/01:00처럼 자정을 사이에 두고 갈라져도 큰 값으로 새지 않음', () {
      // 산술표준편차로 계산하면 22시간대 값으로 튀지만, 순환 척도에서는
      // 두 값이 자정을 사이에 두고 1시간씩만 떨어져 있다.
      final std = circularStdHours([23.0, 1.0]);
      expect(std, greaterThan(0.0));
      expect(std, lessThan(2.0));
    });

    test('circularStdHours: 4등분으로 골고루 퍼지면 최댓값(12시간)으로 clamp', () {
      expectClose(circularStdHours([0.0, 6.0, 12.0, 18.0]), 12.0, tol: 1e-9);
    });
  });

  group('idealSleepTimes (§2-①)', () {
    final t = defaultShiftTimings;

    test('Night 근무는 종료시각 + 통근 + 준비 기준', () {
      final roster = [ShiftType.day, ShiftType.night, ShiftType.off];
      final r = idealSleepTimes(
        roster: roster,
        todayIndex: 1,
        shiftTimings: t,
        commuteMinutes: 20.0,
        recentSessions: const [],
      );
      final expectedBedtime = 55.0 + 20.0 / 60.0 + prepMinutes / 60.0; // 1일차 종료(55h=2일차 07:00)
      expectClose(r.bedtime, expectedBedtime);
      expectClose(r.wake, expectedBedtime + defaultNeedSleepMin / 60.0);
    });

    test('Day 근무는 시작시각 기준 기상 역산 (종료시각 기준이면 격차 방향이 깨짐)', () {
      final roster = [ShiftType.day, ShiftType.day];
      final r = idealSleepTimes(
        roster: roster,
        todayIndex: 0,
        shiftTimings: t,
        commuteMinutes: 20.0,
        recentSessions: const [],
      );
      final expectedWake = 31.0 - prepMinutes / 60.0; // 내일(1일차) 07:00 - 준비시간
      expectClose(r.wake, expectedWake);
      expectClose(r.bedtime, expectedWake - defaultNeedSleepMin / 60.0);
    });

    test('내일·오늘 모두 OFF면 최근 실측 평균 취침시각으로 폴백', () {
      final roster = [ShiftType.off, ShiftType.off];
      final sessions = [const SleepSession(22.0, 29.0)]; // 0일차 22:00 취침
      final r = idealSleepTimes(
        roster: roster,
        todayIndex: 1,
        shiftTimings: t,
        commuteMinutes: 20.0,
        recentSessions: sessions,
      );
      expectClose(r.bedtime, 46.0); // 1일차 00:00(24h) + 22h
      expectClose(r.wake, 46.0 + defaultNeedSleepMin / 60.0);
    });
  });

  test('stepTowardTarget: 격차가 클라이언트 상한(60분)을 넘으면 clamp된다 (§2-③)', () {
    final r = stepTowardTarget(idealBedtime: 10.0, currentPhaseAbs: 100.0);
    // idealMidpoint clock=13.5, currentPhase clock=4.0 -> 격차 +9.5h(570분) -> +60분으로 clamp
    expectClose(r.bedtime, 100.0 + 1.0 - defaultNeedSleepMin / 60.0 / 2.0);
    expectClose(r.wake, r.bedtime + defaultNeedSleepMin / 60.0);
  });

  test('currentPhase: 날짜 앵커는 now에 가장 가까운 발생 시점을 골라야 함 (§2-②)', () {
    // 세션 중간점 clock=04:30. now=100.0h(4일차 04:00) 기준으로는
    // "오늘 새벽 04:30"(100.5h)이 정답 — "0일차 04:30"(4.5h)처럼 now와
    // 무관한 날짜에 고정되면 §2-③ 이후 목표 취침이 항상 과거로 계산된다.
    final sessions = [const SleepSession(1.0, 8.0)]; // midpoint=4.5
    final phase = currentPhase(recentSessions: sessions, now: 100.0);
    expectClose(phase, 100.5);
  });

  group('buildNudgePlan (§2~§5 통합)', () {
    final roster = [
      ShiftType.day, ShiftType.day, ShiftType.evening,
      ShiftType.night, ShiftType.night, ShiftType.off, ShiftType.off,
    ];

    test('근무 시작 3시간 이상 전 + Evening/Night 근무 -> 낮잠 플랜, 과거 넛지는 제외', () {
      final sessions = [const SleepSession(0.0, 49.0)]; // 부채 0 -> 20분 낮잠
      final plan = buildNudgePlan(
        roster: roster,
        todayIndex: 3, // Night, 근무 시작 = 3*24+23 = 95.0h
        now: 90.0,
        recentSessions: sessions,
      );

      expect(plan.sleep.type, PlanType.nap);
      final napStart = 95.0 - 3.0 - 20.0 / 60.0;
      expectClose(plan.sleep.napStart!, napStart);
      expectClose(plan.sleep.napEnd!, napStart + 20.0 / 60.0);

      // caffeineCutoff(napStart - 528분)은 now(90.0) 이전이라 제외되어야 함
      expect(plan.nudges.map((n) => n.kind), [NudgeKind.napStart, NudgeKind.lightExposure]);
      expectClose(plan.nudges[0].at, napStart);
      expectClose(plan.nudges[1].at, napStart + 20.0 / 60.0 + 15.0 / 60.0);
    });

    test('Night 근무 당일, 근무 임박(<180분) -> 취침 플랜 + 나이트 전용 넛지, 우선순위·과거필터 적용', () {
      final sessions = [const SleepSession(60.0, 67.0)]; // midpoint=63.5h -> clock 15.5
      final plan = buildNudgePlan(
        roster: roster,
        todayIndex: 3, // Night, 시작 95.0h, 종료 103.0h
        now: 94.0,     // 시작까지 60분 -> 낮잠 조건(180분) 미달
        recentSessions: sessions,
      );

      expect(plan.sleep.type, PlanType.bedtime);
      expectClose(plan.sleep.targetBedtime!, 83.0);
      expectClose(plan.sleep.targetWake!, 90.0);

      // caffeineCutoff/lightBlock/windDown/lightExposure는 전부 now(94.0) 이전이라 제외되고
      // 나이트 전용 brightLightAtWork/sunglassesCommute만 살아남는다.
      expect(plan.nudges.map((n) => n.kind),
          [NudgeKind.brightLightAtWork, NudgeKind.sunglassesCommute]);
      expectClose(plan.nudges[0].at, 95.5);
      expectClose(plan.nudges[1].at, 102.75);
    });
  });
}
