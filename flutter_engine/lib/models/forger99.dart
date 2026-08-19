import 'dart:math';
import '../circadian_model.dart';

double _pow(double b, double e) => powd(b, e);

/// Forger 1999 — "A simpler model of the human circadian pacemaker".
/// 상태: [x, xc, n]. 입력: 조도(lux).
class Forger99 extends CircadianModel {
  final double taux;
  final double mu;
  final double G;
  final double alpha0;
  final double beta;
  final double p;
  final double I0;
  final double k;

  Forger99({
    this.taux = 24.2,
    this.mu = 0.23,
    this.G = 33.75,
    this.alpha0 = 0.05,
    this.beta = 0.0075,
    this.p = 0.50,
    this.I0 = 9500.0,
    this.k = 0.55,
  });

  @override
  int get numStates => 3;

  @override
  List<double> get defaultInitialCondition =>
      [-0.0843259, -1.09607546, 0.45584306];

  @override
  List<double> derv(double t, List<double> state, double light) {
    final x = state[0], xc = state[1], n = state[2];

    final alpha = alpha0 * _pow(light / I0, p);
    final bHat = G * (1.0 - n) * alpha * (1 - 0.4 * x) * (1 - 0.4 * xc);
    final muTerm = mu * (xc - 4.0 / 3.0 * _pow(xc, 3.0));
    final tauxTerm = _pow(24.0 / (0.99669 * taux), 2.0) + k * bHat;

    return [
      pi / 12.0 * (xc + bHat),
      pi / 12.0 * (muTerm - x * tauxTerm),
      60.0 * (alpha * (1.0 - n) - beta * n),
    ];
  }

  @override
  List<double> cbtSignal(DynamicalTrajectory traj) {
    return traj.states.map((s) => -1.0 * s[0]).toList();
  }
}
