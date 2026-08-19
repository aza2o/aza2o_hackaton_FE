/// 순환(24시간) 통계 유틸 — 시각 평균과 최단거리 계산.
///
/// 벽시계 시각은 원형 척도라 산술평균이 틀린다. 23:50과 00:10의 산술평균은
/// 12:00이지만 정답은 00:00이다. 여기서는 시각을 각도(시간/24 × 360°)로
/// 바꿔 벡터 평균·최단거리를 낸 뒤 되돌린다. `룰엔진_규칙_v2.md` §2-②·③
/// 참고 — "여기서 틀리면 목표 시각이 12시간 어긋나는데 테스트로 잘 안
/// 잡힌다"고 문서가 명시적으로 경고하는 지점이라 별도 파일로 분리해 직접
/// 테스트한다.
library circular_time;

import 'dart:math' as math;

/// [hours]의 순환평균 시각을 [0, 24) 범위로 반환. 각 원소는 mod 24 처리되어
/// 들어오므로 절대시간(h)을 그대로 넘겨도 된다.
double circularMeanHours(List<double> hours) {
  if (hours.isEmpty) {
    throw ArgumentError('hours must not be empty');
  }
  var sumSin = 0.0, sumCos = 0.0;
  for (final h in hours) {
    final angle = (h % 24.0) / 24.0 * 2 * math.pi;
    sumSin += math.sin(angle);
    sumCos += math.cos(angle);
  }
  final meanAngle = math.atan2(sumSin, sumCos);
  final meanHours = meanAngle / (2 * math.pi) * 24.0;
  return (meanHours % 24.0 + 24.0) % 24.0;
}

/// [from]에서 [to]까지의 부호 있는 순환 최단거리(시간), 항상 (-12, 12] 범위.
/// 예: from=04:00, to=22:00 이면 +18이 아니라 -6.
double circularShortestDiffHours(double from, double to) {
  var diff = (to - from) % 24.0; // Dart의 %는 양수 나눗수에 대해 [0,24) 반환
  if (diff > 12.0) diff -= 24.0;
  return diff;
}

/// [hours]의 순환표준편차(시간) — Mardia 각편차(angular deviation,
/// `sqrt(-2 * ln(R))`, R은 평균 결과 벡터 길이)를 시간 단위로 환산.
/// 값이 원 위에 골고루 퍼져 R이 0에 가까우면(평균 방향이 무의미) 순환
/// 척도의 최댓값인 12시간으로 clamp한다.
double circularStdHours(List<double> hours) {
  if (hours.isEmpty) {
    throw ArgumentError('hours must not be empty');
  }
  var sumSin = 0.0, sumCos = 0.0;
  for (final h in hours) {
    final angle = (h % 24.0) / 24.0 * 2 * math.pi;
    sumSin += math.sin(angle);
    sumCos += math.cos(angle);
  }
  var r = math.sqrt(sumSin * sumSin + sumCos * sumCos) / hours.length;
  if (r <= 1e-9) return 12.0;
  if (r > 1.0) r = 1.0; // 부동소수점 오차로 1을 살짝 넘는 경우 방지(log(r>1) 이슈)
  final angularStd = math.sqrt(-2 * math.log(r));
  final stdHours = angularStd / (2 * math.pi) * 24.0;
  return stdHours > 12.0 ? 12.0 : stdHours;
}
