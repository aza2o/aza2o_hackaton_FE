// 하단 탭의 근무 달력 — 아무 달이나 넘겨볼 수 있고, 근무표가 없는 달은
// 오프로 채우지 않고 빈 상태로 둔다(없는 근무를 오프로 보여주면 사용자가
// "오프로 등록돼 있다"고 오해한다).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_app/screens/roster_calendar_screen.dart';
import 'package:shift_app/state/app_state.dart';
import 'package:shift_circadian_engine/roster/constants.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

/// 이번 달 1일부터 한 달치를 D/E/N/O 반복으로 채운다.
void _seedThisMonth() {
  final now = DateTime.now();
  final first = DateTime(now.year, now.month, 1);
  final days = DateTime(now.year, now.month + 1, 0).day;
  const pattern = [
    ShiftType.day,
    ShiftType.evening,
    ShiftType.night,
    ShiftType.off,
  ];
  AppState.instance.saveRoster(
    [for (var i = 0; i < days; i++) pattern[i % pattern.length]],
    startDate: first,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.signOut();
  });

  testWidgets('이번 달 근무표가 있으면 그리드와 범례가 뜬다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _seedThisMonth();

    await tester.pumpWidget(_wrap(const RosterCalendarScreen()));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    expect(find.text('${now.year}년 ${now.month}월'), findsOneWidget);
    expect(find.textContaining('데이'), findsOneWidget);
    expect(find.text('날짜를 눌러 근무를 바꿀 수 있어요'), findsOneWidget);
  });

  testWidgets('이전/다음 달로 넘길 수 있고, 근무표 없는 달은 빈 상태로 둔다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _seedThisMonth();

    await tester.pumpWidget(_wrap(const RosterCalendarScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('이전 달'));
    await tester.pumpAndSettle();

    final prev = DateTime(DateTime.now().year, DateTime.now().month - 1, 1);
    expect(find.text('${prev.year}년 ${prev.month}월'), findsOneWidget);
    expect(find.text('${prev.month}월 근무표가 아직 없어요'), findsOneWidget);
    expect(find.text('근무표 올리기'), findsOneWidget);

    // 다시 이번 달로 돌아오면 그리드가 보인다.
    await tester.tap(find.byTooltip('다음 달'));
    await tester.pumpAndSettle();
    expect(find.text('날짜를 눌러 근무를 바꿀 수 있어요'), findsOneWidget);
  });

  testWidgets('날짜를 누르면 근무가 바뀌고 저장된다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _seedThisMonth();

    await tester.pumpWidget(_wrap(const RosterCalendarScreen()));
    await tester.pumpAndSettle();

    // 1일은 시드에서 day(D) — 한 번 누르면 evening(E)이 된다.
    expect(AppState.instance.roster!.first, ShiftType.day);
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();

    expect(AppState.instance.roster!.first, ShiftType.evening);
  });
}
