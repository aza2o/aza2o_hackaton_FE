import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_app/services/auth_service.dart';
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

  test('서버 근무표는 응답 순서가 아니라 실제 날짜에 배치한다', () {
    final parsed = parseDatedRosterRows(<Map<String, dynamic>>[
      {'work_date': '2026-07-03', 'shift_type': 'N'},
      {'work_date': '2026-07-01', 'shift_type': 'D'},
      {'work_date': '2026-07-02', 'shift_type': 'E'},
    ]);

    expect(parsed.startDate, DateTime(2026, 7, 1));
    expect(parsed.shifts, [ShiftType.day, ShiftType.evening, ShiftType.night]);
    expect(parsed.missingIndices, isEmpty);
  });

  test('누락 날짜는 비워두고 중복 날짜는 첫 번째 값을 유지한다', () {
    final parsed = parseDatedRosterRows(<Map<String, dynamic>>[
      {'work_date': '2026-07-03', 'shift_type': 'N'},
      {'work_date': '2026-07-01', 'shift_type': 'D'},
      {'work_date': '2026-07-01', 'shift_type': 'E'},
    ]);

    expect(parsed.shifts.first, ShiftType.day);
    expect(parsed.missingIndices, {1});
  });
}
