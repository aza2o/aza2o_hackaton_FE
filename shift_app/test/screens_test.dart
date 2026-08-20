import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shift_app/screens/roster_upload_screen.dart';
import 'package:shift_app/screens/roster_confirm_screen.dart';
import 'package:shift_app/screens/ai_report_screen.dart';
import 'package:shift_app/screens/skin_routine_screen.dart';
import 'package:shift_app/health/health_signal_source.dart';
import 'package:shift_app/screens/onboarding_flow.dart';
import 'package:shift_app/screens/permission_screen.dart';
import 'package:shift_app/screens/home_screen.dart';
import 'package:shift_app/screens/settings_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('로스터 입력 → 동의 체크 전에는 CTA 비활성', (tester) async {
    await tester.pumpWidget(_wrap(const RosterUploadScreen()));
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    final buttonAfter = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(buttonAfter.onPressed, isNotNull);
  });

  testWidgets('로스터 입력 → 2차(패턴 선택) 경로로 확인 화면으로 이동', (tester) async {
    // "1차: 엑셀 업로드"는 이제 실제 file_picker + POST /roster/parse를
    // 태우므로(위젯 테스트에서 검증 불가) 서버 없이도 되는 2차 경로로 확인한다.
    // 기본 테스트 뷰포트(800x600)가 좁아 하단 CTA가 화면 밖으로 밀린다 —
    // 실기기 화면 비율에 맞춰 세로로 넉넉하게 키운다.
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const RosterUploadScreen()));
    await tester.tap(find.text('패턴 선택 + 캘린더 편집'));
    await tester.pumpAndSettle();
    expect(find.byType(RosterConfirmScreen), findsOneWidget);
  });

  testWidgets('로스터 확인 → 그리드와 범례가 렌더링된다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const RosterConfirmScreen()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsOneWidget); // 1일차 셀
    expect(find.textContaining('데이'), findsOneWidget);
    expect(find.textContaining('나이트'), findsOneWidget);
  });

  testWidgets('AI 리포트 → 세그먼트 탭 전환 + 액토그램 렌더링', (tester) async {
    await tester.pumpWidget(_wrap(const AiReportScreen()));
    expect(find.text('이번 주 리듬'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.tap(find.text('월간'));
    await tester.pump();
    // 세그먼트 전환 자체가 예외 없이 되는지만 확인 (콘텐츠는 아직 동일)
    expect(find.text('월간'), findsOneWidget);
  });

  testWidgets('피부·손 루틴 → 점수/게이지 문구가 없어야 한다', (tester) async {
    await tester.pumpWidget(_wrap(const SkinRoutineScreen()));
    expect(find.text('오늘의 루틴 타이밍'), findsOneWidget);
    expect(find.text('퇴근길 자외선 알림'), findsOneWidget);
    // 금지된 패턴(점수/게이지 숫자 표기)이 없는지 확인
    expect(find.textContaining('점'), findsNothing);
    // F3(손 보습)은 기능에서 제외됨(2026-08-18)
    expect(find.text('근무 중 손 보습'), findsNothing);
  });

  testWidgets('온보딩 플로우 → 4단계를 거쳐 권한 화면까지 도달', (tester) async {
    await tester.pumpWidget(_wrap(const OnboardingFlow()));
    expect(find.text('근무 시각을 알려주세요'), findsOneWidget);

    for (final _ in [0, 1, 2]) {
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
    }
    expect(find.text('첫 주는 이렇게 진행돼요'), findsOneWidget);

    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();
    expect(find.byType(PermissionScreen), findsOneWidget);
  });

  testWidgets('온보딩 근무 시각 → 시간을 탭하면 선택기가 뜬다', (tester) async {
    await tester.pumpWidget(_wrap(const OnboardingFlow()));
    expect(find.text('근무 시각을 알려주세요'), findsOneWidget);

    // Day/Evening/Night 각 행의 시작·종료 시각 탭 영역 중 첫 번째(Day 시작).
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);
  });

  testWidgets('온보딩 헬스 연동 카드 → 확인하면 수면 기록을 찾고 체크리스트가 갱신된다', (tester) async {
    // 실기기 플랫폼 채널이 없는 위젯 테스트 환경이라 DemoHealthSource를 주입한다.
    await tester.pumpWidget(_wrap(const OnboardingFlow(healthSource: DemoHealthSource())));
    for (final _ in [0, 1, 2]) {
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
    }
    expect(find.text('첫 주는 이렇게 진행돼요'), findsOneWidget);
    expect(find.text('지금 확인하기'), findsOneWidget);

    // DemoHealthSource는 지연 없이 바로 완료되므로(실기기 어댑터와 달리
    // 인위적 딜레이를 넣지 않는다) 로딩 스피너의 중간 상태는 따로 확인하지
    // 않는다 — pump() 한 번으로 microtask가 다 풀려 이미 완료 상태가 된다.
    await tester.tap(find.text('지금 확인하기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('건의 수면 기록을 찾았어요'), findsOneWidget);
    expect(find.text('다시 확인하기'), findsOneWidget);
  });

  testWidgets('권한 화면 → 허용하고 계속하기 누르면 로스터 입력으로 이동', (tester) async {
    await tester.pumpWidget(_wrap(const PermissionScreen()));
    await tester.tap(find.text('권한 허용하고 계속하기'));
    await tester.pumpAndSettle();
    expect(find.byType(RosterUploadScreen), findsOneWidget);
  });

  testWidgets('홈 하단 카드 → AI 리포트/피부 루틴으로 이동', (tester) async {
    // 헤더 아이콘 2개(무슨 화면인지 알 수 없었다) 대신 홈 하단에 이름이
    // 붙은 카드로 내려왔다 — 헤더에는 설정만 남는다.
    // 실기기 플랫폼 채널이 없는 위젯 테스트 환경이라 DemoHealthSource를 주입한다.
    await tester.pumpWidget(_wrap(const HomeScreen(healthSource: DemoHealthSource())));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('AI 리포트'), 300);
    await tester.tap(find.text('AI 리포트'));
    await tester.pumpAndSettle();
    expect(find.byType(AiReportScreen), findsOneWidget);
  });

  testWidgets('홈 헤더 설정 아이콘 → 설정 화면으로 이동', (tester) async {
    await tester.pumpWidget(_wrap(const HomeScreen(healthSource: DemoHealthSource())));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('홈 화면 → 계산 엔진이 실제 넛지를 채워 렌더링한다 (로딩 스피너가 사라지고 행동 목록이 뜸)',
      (tester) async {
    // 실기기 플랫폼 채널이 없는 위젯 테스트 환경이라 DemoHealthSource를 주입한다.
    await tester.pumpWidget(_wrap(const HomeScreen(healthSource: DemoHealthSource())));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    // 넛지 개수는 실행 시각(now)에 따라 달라질 수 있어(§5, 과거 시각 제외)
    // 개수를 단언하지 않는다 — 로딩이 끝나고 계산된 섹션이 뜨는지만 본다.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('오늘의 행동'), findsOneWidget);
  });
}
