// Process C(DLMO, 4모델 ODE 중 Hannay19) + Process S(수면압력) → 각성도·
// 위험구간. `nudge_service.dart`(룰엔진 기반 넛지 타이밍)와는 다른 축 —
// 여긴 `circadian_model.dart`의 ODE 코어를 실제로 돌린다. 로스터가
// 길수록(한 달치) 계산이 걸릴 수 있어 화면 진입 시 1회 정도만 부르는
// 용도로 설계했다(캐시 없음 — 필요해지면 추가).
import 'package:shift_circadian_engine/models/hannay19.dart';
import 'package:shift_circadian_engine/pressure/pressure.dart';
import 'package:shift_circadian_engine/roster/constants.dart';
import 'package:shift_circadian_engine/roster/light_schedule.dart';
import '../state/app_state.dart';

const _demoRoster = [
  ShiftType.day, ShiftType.day, ShiftType.evening,
  ShiftType.night, ShiftType.night, ShiftType.off, ShiftType.off,
];

class AlertnessResult {
  const AlertnessResult({
    required this.time,
    required this.alert,
    required this.riskWindows,
    required this.sleep,
    required this.startDate,
    required this.roster,
    required this.dlmos,
    required this.profile,
  });

  final List<double> time; // 절대시간(h), startDate 00:00 = 0
  final List<double> alert; // 상대 스케일(0~1) — 절대 수치로 노출 금지
  final List<(double, double)> riskWindows;
  final List<SleepWindow> sleep;
  final DateTime startDate;
  final List<ShiftType> roster;
  final List<double> dlmos;
  final UserProfile profile;

  bool isLowAt(double absHours) => riskWindows.any((w) => absHours >= w.$1 && absHours < w.$2);

  /// 지금 이 순간이 위험구간(하위 15%)에 들어가는지.
  bool get isLowNow {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dayIndex = today.difference(startDate).inDays;
    final abs = dayIndex * 24.0 + now.hour + now.minute / 60.0;
    return isLowAt(abs);
  }
}

Future<AlertnessResult> loadAlertness() async {
  final app = AppState.instance;
  final roster = app.roster ?? _demoRoster;
  final startDate = app.rosterStartDate ??
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final profile = app.hasProfile ? app.toUserProfile() : UserProfile();

  final sleep = planSleep(roster, profile);
  final series = lightSeries(roster, profile, startDate, sleep: sleep);
  final t = series.time;
  final light = series.light;

  final model = Hannay19();
  final eq = model.equilibrate(t, light, numLoops: 5);
  final traj = model.integrate(t, initialCondition: eq.finalState, light: light);
  final dlmos = model.dlmos(traj);

  final pres = simulatePressure(t, sleep);
  final alert = alertness(t, pres.s, dlmos);
  final risks = riskWindows(t, alert);

  return AlertnessResult(
    time: t, alert: alert, riskWindows: risks, sleep: sleep, startDate: startDate,
    roster: roster, dlmos: dlmos, profile: profile,
  );
}
