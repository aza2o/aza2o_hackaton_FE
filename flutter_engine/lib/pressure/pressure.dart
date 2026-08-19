/// Process S — 수면압력, 그리고 각성도 합성. `logic/pressure.py`의 1:1 포팅.
///
/// ⚠️ 이 모듈은 Song/Hong 계열(CSS)의 재현이 아니다. 교과서 Two-Process
/// (Borbély/Daan)의 열화 근사다. 발표 표현: "Two-Process 기반 각성도
/// 추정, CSS 통합은 로드맵". 금지 표현: "Song 2023 모델 탑재".
///
/// [왜 위상만으로는 부족한가]
///   같은 새벽 4시라도 —
///     나이트 1일차, 저녁 낮잠 후 출근 → S 낮음 / C 최저점 → 각성도 중간
///     나이트 3일차, 낮잠 실패로 20시간 각성 → S·C 동시 최악 → 붕괴
///   위상만 보면 두 상황이 동일하게 출력된다.
library pressure;

import 'dart:math' as math;
import '../roster/light_schedule.dart' show SleepWindow;

// Python logic/constants.py 값 그대로.
const double seReference = 0.85; // 이 수면효율에서 할인 계수 1.0
const double seFloor = 0.40; // 할인 계수 하한(과도한 페널티 방지)
const double sUpper = 1.0;
const double sLower = 0.0;
const double tauRise = 18.2; // UNVERIFIED: 각성 중 압력 상승 시상수(h) — 원본 주석 그대로
const double tauDecay = 4.2; // UNVERIFIED: 수면 중 압력 감쇠 시상수(h)

double _clamp(double x, double lo, double hi) => x < lo ? lo : (x > hi ? hi : x);

/// 수면효율 → 감쇠율 할인 계수. null이면 할인 없음(1.0).
double seDiscount(double? sleepEfficiency) {
  if (sleepEfficiency == null) return 1.0;
  return _clamp(sleepEfficiency / seReference, seFloor, 1.0);
}

class PressureResult {
  const PressureResult(this.time, this.s, this.awake);
  final List<double> time;
  final List<double> s;
  final List<bool> awake;

  /// 선형보간으로 임의 시각의 S값 조회. Python `PressureResult.at`에 대응.
  double at(double t) {
    if (t <= time.first) return s.first;
    if (t >= time.last) return s.last;
    var lo = 0, hi = time.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (time[mid] <= t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final f = (t - time[lo]) / (time[hi] - time[lo]);
    return s[lo] + f * (s[hi] - s[lo]);
  }
}

/// 수면압력 시계열.
/// 각성 중: S → sUpper로 시상수 tauRise로 포화.
/// 수면 중: S → sLower로 시상수 tauDecay로 감쇠(수면효율로 할인).
///
/// [sleepEfficiency]는 [sleep] 리스트 인덱스 → 0~1 수면효율. 없는 인덱스는
/// 할인 없음.
PressureResult simulatePressure(
  List<double> t,
  List<SleepWindow> sleep, {
  Map<int, double>? sleepEfficiency,
  double s0 = 0.4,
}) {
  final dt = t.length > 1 ? t[1] - t[0] : 1.0;
  final awake = List<bool>.filled(t.length, true);
  final disc = List<double>.filled(t.length, 1.0);

  for (var i = 0; i < sleep.length; i++) {
    final w = sleep[i];
    final se = sleepEfficiency?[i];
    final d = se != null ? seDiscount(se) : 1.0;
    for (var k = 0; k < t.length; k++) {
      if (t[k] >= w.start && t[k] < w.end) {
        awake[k] = false;
        if (se != null) disc[k] = d;
      }
    }
  }

  final s = List<double>.filled(t.length, 0.0);
  var cur = s0;
  for (var i = 0; i < t.length; i++) {
    if (awake[i]) {
      cur += (sUpper - cur) * (dt / tauRise);
    } else {
      cur += (sLower - cur) * (dt / tauDecay) * disc[i];
    }
    s[i] = cur;
  }

  return PressureResult(t, s, awake);
}

/// 각성도 = -(Process S) + wC * (Process C 진동).
/// Process C는 DLMO에서 추정한 위상으로 코사인 근사. CBTmin ≈ DLMO + 7h
/// 부근에서 각성도 최저.
///
/// ⚠️ 출력은 임의 스케일의 상대값이다. 절대 각성도 수치를 UI에 노출하지
/// 말 것 — "지금이 오늘 중 가장 낮은 구간" 같은 상대 표현만 허용된다.
List<double> alertness(List<double> t, List<double> s, List<double> dlmos, {double wC = 0.5}) {
  final c = List<double>.filled(t.length, 0.0);
  if (dlmos.isNotEmpty) {
    final ref = dlmos[0] + 7.0;
    var period = 24.0;
    if (dlmos.length > 1) {
      final diffs = <double>[for (var i = 1; i < dlmos.length; i++) dlmos[i] - dlmos[i - 1]];
      diffs.sort();
      final mid = diffs.length ~/ 2;
      final median =
          diffs.length.isOdd ? diffs[mid] : (diffs[mid - 1] + diffs[mid]) / 2.0;
      if (median > 20.0 && median < 28.0) period = median;
    }
    for (var i = 0; i < t.length; i++) {
      c[i] = -math.cos(2 * math.pi * (t[i] - ref) / period);
    }
  }

  final a = List<double>.filled(t.length, 0.0);
  for (var i = 0; i < t.length; i++) {
    a[i] = -s[i] + wC * c[i];
  }
  final maxA = a.reduce(math.max);
  final minA = a.reduce(math.min);
  final range = maxA - minA;
  if (range <= 0) return List<double>.filled(t.length, 0.0);
  return a.map((v) => (v - minA) / range).toList();
}

/// numpy `np.percentile`(선형보간, 기본값)과 동일한 방식.
double _percentile(List<double> sortedValues, double p) {
  final n = sortedValues.length;
  if (n == 1) return sortedValues[0];
  final rank = (p / 100.0) * (n - 1);
  final lo = rank.floor();
  final hi = rank.ceil();
  if (lo == hi) return sortedValues[lo];
  final frac = rank - lo;
  return sortedValues[lo] + frac * (sortedValues[hi] - sortedValues[lo]);
}

/// 각성도 하위 [percentile]% 구간을 위험 창으로 반환. 근무 중 넛지 배치 근거.
List<(double, double)> riskWindows(
  List<double> t,
  List<double> alert, {
  double percentile = 15.0,
}) {
  final sorted = List<double>.from(alert)..sort();
  final thr = _percentile(sorted, percentile);

  final out = <(double, double)>[];
  double? start;
  for (var i = 0; i < alert.length; i++) {
    final low = alert[i] <= thr;
    if (low && start == null) {
      start = t[i];
    } else if (!low && start != null) {
      if (t[i] - start >= 0.5) out.add((start, t[i]));
      start = null;
    }
  }
  if (start != null) out.add((start, t.last));
  return out;
}
