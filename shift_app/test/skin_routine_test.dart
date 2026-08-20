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
}
