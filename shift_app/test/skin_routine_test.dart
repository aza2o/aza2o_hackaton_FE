import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_app/engine/alertness_service.dart';
import 'package:shift_app/engine/skin_routine_service.dart';
import 'package:shift_app/state/app_state.dart';
import 'package:shift_circadian_engine/roster/constants.dart';

void main() {
  test('다음 날 시작하는 주 수면이어도 피부 루틴을 숨기지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.signOut();
    final roster = List<ShiftType>.generate(
      92,
      (index) => const [
        ShiftType.day,
        ShiftType.evening,
        ShiftType.night,
        ShiftType.off,
      ][index % 4],
    );
    AppState.instance.saveRoster(roster, startDate: DateTime(2026, 7, 1));

    final result = await loadAlertness();
    final routine = skinRoutineFrom(result, now: DateTime(2026, 8, 21));

    expect(routine, isNotNull);
    expect(routine!.wakeLabel, isNotEmpty);
    expect(routine.bedtimeLabel, isNotEmpty);
  });

  test('로그인 계정 로스터가 비어도 데모 루틴으로 복구한다', () async {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.signOut();
    AppState.instance.saveRoster([], startDate: DateTime(2026, 8, 1));

    final result = await loadAlertness();
    final routine = skinRoutineFrom(result, now: DateTime(2026, 8, 21));

    expect(result.roster, isNotEmpty);
    expect(routine, isNotNull);
  });

  test('일반 계정 피부 회복 모드는 저장된 실제 수면 부족을 사용한다', () async {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.signOut();
    AppState.instance.setAuthenticatedUser(
      name: '실사용자',
      email: 'real@example.com',
    );
    final start = DateTime(2026, 8, 1);
    AppState.instance.saveRoster(
      List<ShiftType>.filled(31, ShiftType.day),
      startDate: start,
    );
    AppState.instance.replaceSyncedHealthMetrics([
      for (var day = 18; day <= 20; day++)
        SyncedHealthMetric(
          date: DateTime(2026, 8, day),
          sleepStart: DateTime(2026, 8, day - 1, 23),
          sleepEnd: DateTime(2026, 8, day, 5),
          sleepMinutes: 360,
          hrvZ: -0.2,
          restingHeartRate: 64,
          source: 'test_watch',
        ),
    ]);

    final result = await loadAlertness();
    final routine = skinRoutineFrom(result, now: DateTime(2026, 8, 21));

    expect(routine, isNotNull);
    expect(routine!.isRecoveryMode, isTrue);
    expect(routine.todayDeficitMinutes, greaterThanOrEqualTo(60));
  });
}
