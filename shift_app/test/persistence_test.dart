// 재시작 후에도 온보딩 값이 남아있는지 — 이 앱에서 "앱을 껐다 켜면
// 처음부터 다시"가 제일 큰 미완성 항목이었다(구현체크리스트 §7-2).
//
// AppState가 싱글턴이라 "재시작"을 직접 흉내낼 수는 없어서, 저장 →
// 메모리 비우기(signOut 대신 필드 초기화) → load() 순서로 확인한다.
// signOut()은 저장소까지 지우는 게 정상 동작이라 재시작 흉내에 쓰면 안 된다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_app/state/app_state.dart';
import 'package:shift_circadian_engine/roster/constants.dart';

const _timings = {
  ShiftType.day: (TimeOfDay(hour: 7, minute: 0), TimeOfDay(hour: 15, minute: 0)),
  ShiftType.evening: (TimeOfDay(hour: 15, minute: 0), TimeOfDay(hour: 23, minute: 0)),
  ShiftType.night: (TimeOfDay(hour: 23, minute: 0), TimeOfDay(hour: 7, minute: 0)),
};

/// 앱을 껐다 켠 것처럼 메모리 상태만 날리고 저장소는 그대로 둔다.
void _simulateRestart() {
  final s = AppState.instance;
  s.userName = null;
  s.userEmail = null;
  s.shiftTimings = null;
  s.roster = null;
  s.rosterStartDate = null;
  s.chronotype = 'neutral';
  s.caffeineCutoff = const TimeOfDay(hour: 14, minute: 0);
  s.bedtimeIntents.clear();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _simulateRestart();
  });

  testWidgets('재시작해도 온보딩·로스터가 남아있어 홈으로 바로 간다', (tester) async {
    final s = AppState.instance;
    s.signUp(name: '김간호', email: 'a@b.com', password: 'pw1234');
    s.saveOnboarding(
      shiftTimings: _timings,
      workplaceLighting: 'bright',
      bedroomLighting: 'blackout',
      chronotype: 'evening',
      caffeineCutoff: const TimeOfDay(hour: 16, minute: 30),
    );
    s.saveRoster(
      const [ShiftType.day, ShiftType.night, ShiftType.off],
      startDate: DateTime(2026, 8, 1),
    );
    await tester.pumpAndSettle();

    _simulateRestart();
    expect(s.hasProfile, isFalse, reason: '재시작 직후엔 메모리가 비어 있어야 한다');

    await s.load();

    expect(s.hasProfile, isTrue, reason: 'load()가 온보딩을 복원해야 홈으로 간다');
    expect(s.userName, '김간호');
    expect(s.shiftTimings![ShiftType.night]!.$1, const TimeOfDay(hour: 23, minute: 0));
    expect(s.workplaceLighting, 'bright');
    expect(s.bedroomLighting, 'blackout');
    expect(s.roster, [ShiftType.day, ShiftType.night, ShiftType.off]);
    expect(s.rosterStartDate, DateTime(2026, 8, 1));
  });

  testWidgets('온보딩 3단계 답(크로노타입·카페인)도 복원된다', (tester) async {
    // 예전엔 saveOnboarding이 이 둘을 아예 받지 않아서, 사용자가 고른 값이
    // 화면을 넘어가는 순간 사라졌다.
    final s = AppState.instance;
    s.saveOnboarding(
      shiftTimings: _timings,
      workplaceLighting: 'normal',
      bedroomLighting: 'curtain',
      chronotype: 'morning',
      caffeineCutoff: const TimeOfDay(hour: 11, minute: 15),
    );
    await tester.pumpAndSettle();

    _simulateRestart();
    await s.load();

    expect(s.chronotype, 'morning');
    expect(s.caffeineCutoff, const TimeOfDay(hour: 11, minute: 15));
  });

  testWidgets('비밀번호는 저장소에 남지 않는다', (tester) async {
    final s = AppState.instance;
    s.signUp(name: '김간호', email: 'a@b.com', password: 'sup3rsecret');
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('shift_app_state_v1');
    expect(raw, isNotNull);
    expect(raw, isNot(contains('sup3rsecret')));
  });

  testWidgets('로그아웃하면 저장된 것도 지워진다', (tester) async {
    final s = AppState.instance;
    s.signUp(name: '김간호', email: 'a@b.com', password: 'pw1234');
    s.saveOnboarding(
      shiftTimings: _timings,
      workplaceLighting: 'normal',
      bedroomLighting: 'curtain',
      chronotype: 'neutral',
      caffeineCutoff: const TimeOfDay(hour: 14, minute: 0),
    );
    await tester.pumpAndSettle();

    s.signOut();
    await tester.pumpAndSettle();
    await s.load();

    expect(s.hasProfile, isFalse);
    expect(s.userName, isNull);
  });

  testWidgets('저장 데이터가 깨져 있어도 최초 실행처럼 시작한다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'shift_app_state_v1': '{이건 JSON이 아니다',
    });

    await AppState.instance.load();

    expect(AppState.instance.hasProfile, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('shift_app_state_v1'), isNull,
        reason: '깨진 데이터는 지워서 다음 실행에 또 걸리지 않게 한다');
  });
}
