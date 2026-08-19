import 'dart:math';
import '../circadian_model.dart';

/// Jewett 1999 — "Revised Limit Cycle Oscillator Model of Human Circadian
/// Pacemaker". 상태: [x, xc, n]. 입력: 조도(lux).
class Jewett99 extends CircadianModel {
  final double taux;
  final double mu;
  final double G;
  final double beta;
  final double k;
  final double q;
  final double I0;
  final double p;
  final double alpha0;
  final double phiRef;

  Jewett99({
    this.taux = 24.2,
    this.mu = 0.13,
    this.G = 19.875,
    this.beta = 0.013,
    this.k = 0.55,
    this.q = 1.0 / 3,
    this.I0 = 9500,
    this.p = 0.6,
    this.alpha0 = 0.16,
    this.phiRef = 0.8,
  });

  @override
  int get numStates => 3;

  @override
  List<double> get defaultInitialCondition =>
      [-0.10097101, -1.21985662, 0.50529415];

  @override
  double get cbtOffsetHours => phiRef;

  @override
  List<double> derv(double t, List<double> state, double light) {
    final x = state[0], xc = state[1], n = state[2];

    final alpha = alpha0 * powd(light / I0, p);
    final bHat = G * alpha * (1 - n) * (1 - 0.4 * x) * (1 - 0.4 * xc);
    final muTerm =
        mu * (1.0 / 3.0 * x + 4.0 / 3.0 * powd(x, 3.0) - 256.0 / 105.0 * powd(x, 7.0));
    final tauxTerm = powd(24.0 / (0.99729 * taux), 2.0) + k * bHat;

    return [
      pi / 12 * (xc + muTerm + bHat),
      pi / 12 * (q * bHat * xc - x * tauxTerm),
      60.0 * (alpha * (1 - n) - beta * n),
    ];
  }

  @override
  List<double> cbtSignal(DynamicalTrajectory traj) {
    return traj.states.map((s) => -1.0 * s[0]).toList();
  }
}
