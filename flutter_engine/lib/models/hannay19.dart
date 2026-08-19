import 'dart:math';
import '../circadian_model.dart';

/// Hannay 2019 단일집단 모델 — "Macroscopic models for human circadian rhythms".
/// 상태: [R, Psi, n]. 입력: 조도(lux). SHIFT의 기본(primary) 모델.
class Hannay19 extends CircadianModel {
  final double tau;
  final double K;
  final double gamma;
  final double beta1;
  final double a1;
  final double a2;
  final double betaL1;
  final double betaL2;
  final double sigma;
  final double G;
  final double alpha0;
  final double delta;
  final double p;
  final double I0;

  Hannay19({
    this.tau = 23.84,
    this.K = 0.06358,
    this.gamma = 0.024,
    this.beta1 = -0.09318,
    this.a1 = 0.3855,
    this.a2 = 0.1977,
    this.betaL1 = -0.0026,
    this.betaL2 = -0.957756,
    this.sigma = 0.0400692,
    this.G = 33.75,
    this.alpha0 = 0.05,
    this.delta = 0.0075,
    this.p = 1.5,
    this.I0 = 9325.0,
  });

  @override
  int get numStates => 3;

  @override
  List<double> get defaultInitialCondition =>
      [0.82041911, 1.71383697, 0.52318122];

  @override
  List<double> derv(double t, List<double> state, double light) {
    final R = state[0], psi = state[1], n = state[2];

    final alpha = alpha0 * powd(light, p) / (powd(light, p) + I0);
    final bHat = G * (1.0 - n) * alpha;

    final a1TermAmp =
        a1 * 0.5 * bHat * (1.0 - powd(R, 4.0)) * cos(psi + betaL1);
    final a2TermAmp =
        a2 * 0.5 * bHat * R * (1.0 - powd(R, 8.0)) * cos(2.0 * psi + betaL2);
    final lightAmp = a1TermAmp + a2TermAmp;

    final a1TermPhase =
        a1 * bHat * 0.5 * (powd(R, 3.0) + 1.0 / R) * sin(psi + betaL1);
    final a2TermPhase =
        a2 * bHat * 0.5 * (1.0 + powd(R, 8.0)) * sin(2.0 * psi + betaL2);
    final lightPhase = sigma * bHat - a1TermPhase - a2TermPhase;

    return [
      -1.0 * gamma * R +
          K * cos(beta1) / 2.0 * R * (1.0 - powd(R, 4.0)) +
          lightAmp,
      2 * pi / tau + K / 2.0 * sin(beta1) * (1 + powd(R, 4.0)) + lightPhase,
      60.0 * (alpha * (1.0 - n) - delta * n),
    ];
  }

  @override
  List<double> cbtSignal(DynamicalTrajectory traj) {
    return traj.states.map((s) => -cos(s[1])).toList();
  }
}
