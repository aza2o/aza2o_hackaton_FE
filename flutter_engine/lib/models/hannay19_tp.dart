import 'dart:math';
import '../circadian_model.dart';

/// Hannay 2019 두집단(Two-Population) 모델 — "Macroscopic models for human
/// circadian rhythms". 상태: [Rv, Rd, Psiv, Psid, n]. 입력: 조도(lux).
class Hannay19TP extends CircadianModel {
  final double tauV;
  final double tauD;
  final double kvv;
  final double kdd;
  final double kvd;
  final double kdv;
  final double gamma;
  final double a1;
  final double a2;
  final double betaL;
  final double betaL2;
  final double sigma;
  final double G;
  final double alpha0;
  final double delta;
  final double p;
  final double I0;

  Hannay19TP({
    this.tauV = 24.25,
    this.tauD = 24.0,
    this.kvv = 0.05,
    this.kdd = 0.04,
    this.kvd = 0.05,
    this.kdv = 0.01,
    this.gamma = 0.024,
    this.a1 = 0.440068,
    this.a2 = 0.159136,
    this.betaL = 0.06452,
    this.betaL2 = -1.38935,
    this.sigma = 0.0477375,
    this.G = 33.75,
    this.alpha0 = 0.05,
    this.delta = 0.0075,
    this.p = 1.5,
    this.I0 = 9325.0,
  });

  @override
  int get numStates => 5;

  @override
  List<double> get defaultInitialCondition =>
      [0.82423745, 0.82304996, 1.75233424, 1.863457, 0.52318122];

  @override
  List<double> derv(double t, List<double> state, double light) {
    final Rv = state[0], Rd = state[1], Psiv = state[2], Psid = state[3];
    final n = state[4];

    final alpha = alpha0 * powd(light, p) / (powd(light, p) + I0);
    final bHat = G * (1.0 - n) * alpha;

    final a1TermAmp =
        a1 * 0.5 * bHat * (1.0 - powd(Rv, 4.0)) * cos(Psiv + betaL);
    final a2TermAmp =
        a2 * 0.5 * bHat * Rv * (1.0 - powd(Rv, 8.0)) * cos(2.0 * Psiv + betaL2);
    final lightAmp = a1TermAmp + a2TermAmp;

    final a1TermPhase =
        a1 * bHat * 0.5 * (powd(Rv, 3.0) + 1.0 / Rv) * sin(Psiv + betaL);
    final a2TermPhase =
        a2 * bHat * 0.5 * (1.0 + powd(Rv, 8.0)) * sin(2.0 * Psiv + betaL2);
    final lightPhase = sigma * bHat - a1TermPhase - a2TermPhase;

    return [
      -gamma * Rv +
          kvv / 2.0 * Rv * (1 - powd(Rv, 4.0)) +
          kdv / 2.0 * Rd * (1 - powd(Rv, 4.0)) * cos(Psid - Psiv) +
          lightAmp,
      -gamma * Rd +
          kdd / 2.0 * Rd * (1 - powd(Rd, 4.0)) +
          kvd / 2.0 * Rv * (1.0 - powd(Rd, 4.0)) * cos(Psid - Psiv),
      2.0 * pi / tauV +
          kdv / 2.0 * Rd * (powd(Rv, 3.0) + 1.0 / Rv) * sin(Psid - Psiv) +
          lightPhase,
      2.0 * pi / tauD -
          kvd / 2.0 * Rv * (powd(Rd, 3.0) + 1.0 / Rd) * sin(Psid - Psiv),
      60.0 * (alpha * (1.0 - n) - delta * n),
    ];
  }

  @override
  List<double> cbtSignal(DynamicalTrajectory traj) {
    // Psiv = states[2] (Python: -np.cos(states[:,2]))
    return traj.states.map((s) => -cos(s[2])).toList();
  }
}
