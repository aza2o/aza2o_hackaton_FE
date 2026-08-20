import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_app/state/app_state.dart';
import 'package:shift_circadian_engine/roster/constants.dart';

void main() {
  test('데모 계정 근무표는 2026년 7월부터 9월까지다', () async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState.instance;
    state.signOut();

    await state.seedDemoAccount();

    expect(state.rosterStartDate, DateTime(2026, 7, 1));
    expect(state.roster, hasLength(92));
    final end = state.rosterStartDate!.add(
      Duration(days: state.roster!.length - 1),
    );
    expect(end, DateTime(2026, 9, 30));
  });

  test('데모 계정에는 잘못된 9~11월 로스터를 저장할 수 없다', () async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState.instance;
    state.signOut();
    await state.seedDemoAccount();

    state.saveRoster(
      List<ShiftType>.filled(92, ShiftType.night),
      startDate: DateTime(2026, 9, 1),
    );

    expect(state.rosterStartDate, DateTime(2026, 7, 1));
    expect(state.roster, hasLength(92));
    final end = state.rosterStartDate!.add(
      Duration(days: state.roster!.length - 1),
    );
    expect(end, DateTime(2026, 9, 30));
  });
}
