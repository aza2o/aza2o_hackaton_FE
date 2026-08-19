/// 골든 벡터 검증 테스트.
///
/// `golden_vectors.json`은 Python `circadian` v1.0.3 원본 패키지를 직접 돌려서
/// 생성한 값이다 (생성 스크립트는 이 리포의 대화 기록 참고 — 72시간,
/// dt=0.1h, 16L/8D 반복 조도 스케줄, 기본 초기조건 기준).
///
/// 17개 전부 통과 확인됨(`dart-sdk` brew 설치 후 `dart test` 실행, 2026-08-17).
/// 최초 버전은 시간축을 `h += 0.1` 누적으로 만들어 부동소수점 오차가 쌓이면서
/// 전부 실패했었다 — `i * dt` 인덱스 곱셈으로 고쳐서 해결했다. 이 엔진을
/// 호출하는 모든 코드는 time 배열을 같은 방식으로 만들어야 한다.
library golden_vectors_test;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../lib/circadian_model.dart';
import '../lib/models/forger99.dart';
import '../lib/models/hannay19.dart';
import '../lib/models/hannay19_tp.dart';
import '../lib/models/jewett99.dart';

/// golden_vectors.json 생성 시 쓴 것과 동일한 시간축 + 조도 스케줄.
({List<double> time, List<double> light}) buildSchedule(double totalHours) {
  // numpy.arange(0, totalHours, 0.1)과 동일하게 i*dt로 계산한다.
  // h += 0.1을 반복 누적하면 부동소수점 오차가 쌓여 720스텝 뒤에는
  // 무시할 수 없는 위상 오차가 생긴다 — 실제로 이 버그 때문에 첫 버전의
  // 골든 테스트가 전부 실패했다.
  const dt = 0.1;
  final n = (totalHours / dt).round();
  final time = List<double>.generate(n, (i) => i * dt);
  final light = time.map((h) {
    final hourOfDay = h % 24.0;
    return hourOfDay >= 8.0 ? 100.0 : 0.0;
  }).toList();
  return (time: time, light: light);
}

void expectClose(double actual, double expected, {double tol = 1e-3, String? reason}) {
  expect((actual - expected).abs() < tol, isTrue,
      reason: '${reason ?? ''} expected=$expected actual=$actual diff=${(actual-expected).abs()}');
}

void main() {
  final goldenFile = File('test/golden_vectors.json');
  final golden = jsonDecode(goldenFile.readAsStringSync()) as Map<String, dynamic>;

  final models = <String, CircadianModel>{
    'Forger99': Forger99(),
    'Hannay19': Hannay19(),
    'Hannay19TP': Hannay19TP(),
    'Jewett99': Jewett99(),
  };

  for (final entry in models.entries) {
    final name = entry.key;
    final model = entry.value;
    final g = golden[name] as Map<String, dynamic>;

    group(name, () {
      test('기본 초기조건이 Python 원본과 동일', () {
        final expected = (g['default_initial_condition'] as List).cast<num>();
        for (var i = 0; i < expected.length; i++) {
          expectClose(model.defaultInitialCondition[i], expected[i].toDouble(),
              tol: 1e-6, reason: '$name IC[$i]');
        }
      });

      test('72시간 적분 후 상태값이 Python 원본과 일치 (허용오차 1e-3)', () {
        final sched = buildSchedule(72.0);
        final traj = model.integrate(sched.time, light: sched.light);

        final expectedFinal = (g['final_state_no_equilibrate'] as List).cast<num>();
        for (var i = 0; i < expectedFinal.length; i++) {
          expectClose(traj.states.last[i], expectedFinal[i].toDouble(),
              reason: '$name final_state[$i]');
        }

        final expectedT24 = (g['state_at_t24'] as List).cast<num>();
        final stateT24 = traj.call(24.0);
        for (var i = 0; i < expectedT24.length; i++) {
          expectClose(stateT24[i], expectedT24[i].toDouble(), reason: '$name state@24h[$i]');
        }

        final expectedT48 = (g['state_at_t48'] as List).cast<num>();
        final stateT48 = traj.call(48.0);
        for (var i = 0; i < expectedT48.length; i++) {
          expectClose(stateT48[i], expectedT48[i].toDouble(), reason: '$name state@48h[$i]');
        }
      });

      test('DLMO 마커가 Python 원본과 일치 (허용오차 0.1h)', () {
        final sched = buildSchedule(72.0);
        final traj = model.integrate(sched.time, light: sched.light);
        final dlmo = model.dlmos(traj);
        final expected = (g['dlmos_no_equilibrate'] as List).cast<num>();

        expect(dlmo.length, expected.length, reason: '$name DLMO 개수');
        for (var i = 0; i < expected.length; i++) {
          expectClose(dlmo[i], expected[i].toDouble(), tol: 0.1, reason: '$name dlmo[$i]');
        }
      });

      test('equilibrate 5회 결과가 Python 원본과 일치', () {
        final sched = buildSchedule(24.0);
        final result = model.equilibrate(sched.time, sched.light, numLoops: 5);
        final expected = (g['equilibrated_ic_5loops'] as List).cast<num>();
        for (var i = 0; i < expected.length; i++) {
          expectClose(result.finalState[i], expected[i].toDouble(),
              reason: '$name equilibrated[$i]');
        }
      });
    });
  }

  group('findPeaks', () {
    test('단순 사인파에서 봉우리를 정확히 찾는다', () {
      final t = List.generate(200, (i) => i * 0.1);
      final signal = t.map((x) => sin(2 * pi * x / 10.0)).toList(); // 주기 10h
      final peaks = findPeaks(signal, minDistance: 50); // 5시간 최소간격
      expect(peaks.length, greaterThan(0));
      // 각 피크에서 signal 값이 실제로 국소최대인지 확인
      for (final p in peaks) {
        expect(signal[p], greaterThan(signal[p - 1]));
        expect(signal[p], greaterThan(signal[p + 1]));
      }
    });
  });
}
