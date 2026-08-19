/// SHIFT 서캐디언 엔진 — Dart 포팅 코어.
///
/// Arcascope `circadian` v1.0.3 (Python, MIT)의 CircadianModel 기반 클래스를
/// 그대로 옮긴 것이다. RK4 적분기, equilibrate 루프, 선형보간 궤적 조회까지
/// Python 원본과 1:1 대응하도록 작성했다.
///
/// 검증 상태: `dart test`로 골든 벡터 17개 전부 통과 확인 완료 (2026-08-17).
/// 단, 검증 범위는 72시간·16L/8D 규칙적 조도 스케줄 1가지뿐이다 — 실제
/// 로스터 기반 lux(t)처럼 불규칙한 입력에 대해서는 별도 골든 벡터 추가를
/// 권한다. 최초 포팅 시 시간축을 `h += 0.1` 누적으로 만들어 부동소수점
/// 오차가 쌓이는 버그가 있었다 (`i * dt`로 고쳐서 해결) — 이 엔진을 호출하는
/// 쪽에서도 time 배열은 반드시 인덱스 곱셈으로 만들 것.
library circadian_model;

import 'dart:math' as math;

/// `dart:math`의 top-level `pow()`는 `num`을 반환해서 double 연산에 섞으면
/// 정적 타입이 num으로 번져 컴파일 에러가 난다. 모델 derv()는 전부 double
/// 산술이므로 여기서 double로 강제한다.
double powd(double base, double exponent) => math.pow(base, exponent).toDouble();

/// 시간에 따른 상태 궤적. Python `DynamicalTrajectory`에 대응.
class DynamicalTrajectory {
  final List<double> time;
  final List<List<double>> states; // states[i] = 시간 time[i]에서의 상태 벡터

  DynamicalTrajectory(this.time, this.states) {
    if (states.length != time.length) {
      throw ArgumentError('states와 time의 길이가 같아야 한다');
    }
  }

  /// 임의 시각의 상태를 선형보간으로 반환. Python `__call__`에 대응.
  List<double> call(double timepoint) {
    if (timepoint < time.first || timepoint > time.last) {
      throw ArgumentError('timepoint must be within the time range');
    }
    final numStates = states[0].length;
    final out = List<double>.filled(numStates, 0.0);
    for (var s = 0; s < numStates; s++) {
      out[s] = _interp(timepoint, time, states.map((st) => st[s]).toList());
    }
    return out;
  }

  static double _interp(double x, List<double> xs, List<double> ys) {
    if (x <= xs.first) return ys.first;
    if (x >= xs.last) return ys.last;
    // xs는 오름차순 정렬되어 있다고 가정 (엔진 사용부에서 항상 그렇게 만든다)
    var lo = 0, hi = xs.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (xs[mid] <= x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final t = (x - xs[lo]) / (xs[hi] - xs[lo]);
    return ys[lo] + t * (ys[hi] - ys[lo]);
  }
}

List<double> _addScaled(List<double> a, List<double> b, double scale) {
  final out = List<double>.filled(a.length, 0.0);
  for (var i = 0; i < a.length; i++) {
    out[i] = a[i] + b[i] * scale;
  }
  return out;
}

/// 4개 서캐디언 모델(Forger99/Hannay19/Hannay19TP/Jewett99)의 공통 베이스.
/// Python `CircadianModel` 추상 클래스에 대응.
abstract class CircadianModel {
  int get numStates;
  List<double> get defaultInitialCondition;

  /// DLMO = CBTmin - cbtToDlmo (시간). 4개 모델 전부 7.0으로 동일하다.
  double get cbtToDlmo => 7.0;

  /// CBTmin 마커 사이 최소 간격(시간). Python `_min_marker_distance_in_hours`.
  double get minMarkerDistanceHours => 13.0;

  /// CBTmin 시각에 더하는 보정값(시간). Jewett99만 `phi_ref`(0.8)로 오버라이드하고,
  /// 나머지 3개 모델은 0.0 그대로 둔다. Python 원본에서 Jewett99.cbt()만
  /// `+ self.phi_ref`가 붙어 있는 것과 동일하다.
  double get cbtOffsetHours => 0.0;

  /// 미분방정식 우변. 모델별로 구현.
  /// [light]는 해당 시각의 조도(lux) 스칼라.
  List<double> derv(double t, List<double> state, double light);

  /// CBTmin 추정에 쓰는 신호(모델별로 다름 — 예: Forger99는 -x, Hannay19는 -cos(psi)).
  List<double> cbtSignal(DynamicalTrajectory traj);

  /// RK4 1스텝. Python `step_rk4`에 대응.
  List<double> stepRk4(double t, List<double> state, double light, double dt) {
    final k1 = derv(t, state, light);
    final k2 = derv(t, _addScaled(state, k1, dt / 2.0), light);
    final k3 = derv(t, _addScaled(state, k2, dt / 2.0), light);
    final k4 = derv(t, _addScaled(state, k3, dt), light);
    final out = List<double>.filled(state.length, 0.0);
    for (var i = 0; i < state.length; i++) {
      out[i] = state[i] +
          (dt / 6.0) * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i]);
    }
    return out;
  }

  /// [time]과 같은 길이의 [light] 배열을 받아 전체 궤적을 적분.
  /// Python `integrate`에 대응. time은 오름차순, 등간격일 필요는 없다.
  DynamicalTrajectory integrate(
    List<double> time, {
    List<double>? initialCondition,
    required List<double> light,
  }) {
    if (light.length != time.length) {
      throw ArgumentError('light와 time의 길이가 같아야 한다');
    }
    final ic = initialCondition ?? defaultInitialCondition;
    final states = List<List<double>>.filled(time.length, const []);
    states[0] = List<double>.from(ic);
    var state = List<double>.from(ic);
    for (var idx = 1; idx < time.length; idx++) {
      final dt = time[idx] - time[idx - 1];
      state = stepRk4(time[idx], state, light[idx], dt);
      states[idx] = state;
    }
    return DynamicalTrajectory(time, states);
  }

  /// 같은 [light] 스케줄을 [numLoops]번 반복 적분해서 초기조건을 수렴시킨다.
  /// Python `equilibrate`에 대응. 반환값은 마지막 루프의 최종 상태.
  ///
  /// Python 버전과 달리 "수렴했는지" 여부를 boolean으로 함께 반환한다
  /// (Python은 warnings.warn만 하고 넘어가는데, 앱에서는 이 값으로
  /// "위상 추정 신뢰도 낮음" 경고를 UI에 노출해야 하기 때문 — 원본 파이썬
  /// 엔진의 pipeline.py도 동일한 목적으로 이 값을 already 쓰고 있다).
  ({List<double> finalState, bool equilibrated}) equilibrate(
    List<double> time,
    List<double> light, {
    int numLoops = 10,
  }) {
    List<double> ic = List<double>.from(defaultInitialCondition);
    List<double> prevLastDlmo = const [];
    List<double> lastDlmo = const [];
    List<double> finalState = ic;

    for (var loop = 0; loop < numLoops; loop++) {
      final traj = integrate(time, initialCondition: ic, light: light);
      final dlmo = dlmos(traj);
      prevLastDlmo = lastDlmo;
      lastDlmo = dlmo;
      finalState = traj.states.last;
      ic = List<double>.from(finalState);
    }

    var equilibrated = false;
    if (prevLastDlmo.isNotEmpty && lastDlmo.isNotEmpty) {
      equilibrated =
          (prevLastDlmo.last - lastDlmo.last).abs() < 1e-3;
    }
    return (finalState: finalState, equilibrated: equilibrated);
  }

  /// CBTmin 마커 시각들. `cbtSignal`에서 최소 간격 제약을 둔 트로프를 찾는다.
  List<double> cbt(DynamicalTrajectory traj) {
    final signal = cbtSignal(traj);
    final dt = traj.time.length > 1 ? traj.time[1] - traj.time[0] : 1.0;
    final minDistanceSamples = (minMarkerDistanceHours / dt).ceil();
    final peakIdxs = findPeaks(signal, minDistance: minDistanceSamples);
    return peakIdxs.map((i) => traj.time[i] + cbtOffsetHours).toList();
  }

  /// DLMO 마커 시각들. Python `dlmos`에 대응 (Jewett99는 하위 클래스에서 오버라이드).
  List<double> dlmos(DynamicalTrajectory traj) {
    return cbt(traj).map((c) => c - cbtToDlmo).toList();
  }
}

/// `scipy.signal.find_peaks(x, distance=minDistance)`의 최소 재현.
///
/// 원본과 100% 동일하지 않다 — 원본은 평평한 구간(plateau)을 중점으로 처리하는
/// 로직이 있는데, 이 구현은 엄격한 국소극댓값(x[i-1] < x[i] > x[i+1])만 찾는다.
/// ODE 적분 결과는 사실상 평평한 구간이 나오지 않으므로 실질적 차이는 거의
/// 없을 것으로 예상하지만, golden_vectors_test에서 반드시 확인할 것.
///
/// 알고리즘: 후보 국소극댓값을 전부 찾은 뒤, 값이 큰 순서로 정렬해서 그리디하게
/// 채택한다 — 이미 채택된 피크로부터 [minDistance] 샘플 이내면 버린다.
/// (scipy의 `_select_by_peak_distance`와 동일한 그리디 최우선순위 전략)
List<int> findPeaks(List<double> x, {required int minDistance}) {
  final candidates = <int>[];
  for (var i = 1; i < x.length - 1; i++) {
    if (x[i - 1] < x[i] && x[i] > x[i + 1]) {
      candidates.add(i);
    }
  }
  if (candidates.isEmpty) return const [];

  final order = List<int>.from(candidates)
    ..sort((a, b) => x[b].compareTo(x[a])); // 값 큰 순

  final keep = <int>{};
  for (final idx in order) {
    final tooClose = keep.any((k) => (k - idx).abs() < minDistance);
    if (!tooClose) keep.add(idx);
  }
  final result = keep.toList()..sort();
  return result;
}
