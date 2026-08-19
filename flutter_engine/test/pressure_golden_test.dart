/// `logic/pressure.py` 대비 골든 벡터 검증. 생성 스크립트: 대화 기록 참고
/// (roster=[D,D,E,E,N,N,O], UserProfile 기본값, start_date=2026-08-17,
/// DLMO는 Hannay19 단일모델 — `golden_vectors_test.dart`에서 이미 검증된
/// 값을 그대로 재사용해 이 테스트는 pressure.dart 계산만 격리해서 본다).
library pressure_golden_test;

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../lib/roster/constants.dart';
import '../lib/roster/light_schedule.dart';
import '../lib/pressure/pressure.dart';

void expectClose(double actual, double expected, {double tol = 1e-6, String? reason}) {
  expect((actual - expected).abs() < tol, isTrue,
      reason: '${reason ?? ''} expected=$expected actual=$actual diff=${(actual - expected).abs()}');
}

void main() {
  final golden =
      jsonDecode(File('test/pressure_golden.json').readAsStringSync()) as Map<String, dynamic>;

  final roster = [
    ShiftType.day, ShiftType.day, ShiftType.evening,
    ShiftType.evening, ShiftType.night, ShiftType.night, ShiftType.off,
  ];
  final profile = UserProfile();
  final startDate = DateTime.utc(2026, 8, 17);

  final sleep = planSleep(roster, profile);
  final series = lightSeries(roster, profile, startDate, sleep: sleep);
  final t = series.time;

  final dlmos = (golden['dlmos'] as List).map((e) => (e as num).toDouble()).toList();

  test('simulatePressure + alertness가 Python 원본과 일치 (허용오차 1e-6)', () {
    final pres = simulatePressure(t, sleep, s0: (golden['s0'] as num).toDouble());
    final alert = alertness(t, pres.s, dlmos);

    for (final sample in golden['samples'] as List) {
      final st = (sample['t'] as num).toDouble();
      final expectedS = (sample['s'] as num).toDouble();
      final expectedAlert = (sample['alert'] as num).toDouble();

      expectClose(pres.at(st), expectedS, tol: 1e-4, reason: 't=$st S');

      // alert는 원본 파이썬의 np.interp(t)로 만든 샘플이라, Dart 쪽도
      // 같은 선형보간으로 비교한다(PressureResult.at과 동일한 탐색 방식).
      var lo = 0, hi = t.length - 1;
      while (hi - lo > 1) {
        final mid = (lo + hi) ~/ 2;
        if (t[mid] <= st) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      final f = (st - t[lo]) / (t[hi] - t[lo]);
      final interpAlert = alert[lo] + f * (alert[hi] - alert[lo]);
      expectClose(interpAlert, expectedAlert, tol: 1e-3, reason: 't=$st alert');
    }
  });

  test('riskWindows가 Python 원본과 일치', () {
    final pres = simulatePressure(t, sleep, s0: (golden['s0'] as num).toDouble());
    final alert = alertness(t, pres.s, dlmos);
    final risks = riskWindows(t, alert);

    final expectedWindows = golden['risk_windows'] as List;
    expect(risks.length, expectedWindows.length, reason: 'risk window 개수');

    for (var i = 0; i < risks.length; i++) {
      final expStart = (expectedWindows[i][0] as num).toDouble();
      final expEnd = (expectedWindows[i][1] as num).toDouble();
      expectClose(risks[i].$1, expStart, tol: 1e-4, reason: 'risk[$i].start');
      expectClose(risks[i].$2, expEnd, tol: 1e-4, reason: 'risk[$i].end');
    }
  });

  test('seDiscount: 문헌 상한·하한 클램프', () {
    expectClose(seDiscount(null), 1.0);
    expectClose(seDiscount(0.85), 1.0); // seReference 그 자체
    expectClose(seDiscount(1.0), 1.0); // 상한 클램프
    expectClose(seDiscount(0.0), seFloor); // 하한 클램프
  });
}
