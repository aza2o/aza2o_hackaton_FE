import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shift_app/screens/roster_upload_screen.dart';
import 'package:shift_app/screens/roster_confirm_screen.dart';
import 'package:shift_app/screens/ai_report_screen.dart';
import 'package:shift_app/health/health_signal_source.dart';
import 'package:shift_app/screens/onboarding_flow.dart';
import 'package:shift_app/screens/permission_screen.dart';
import 'package:shift_app/screens/home_screen.dart';
import 'package:shift_app/screens/settings_screen.dart';
import 'package:shift_app/state/app_state.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('로스터 입력 → 동의 체크 전에는 CTA 비활성', (tester) async {
    await tester.pumpWidget(_wrap(const RosterUploadScreen()));
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    final buttonAfter = tester.widget<ElevatedButton>(
      find.byType(ElevatedButton),
    );
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

  testWidgets('온보딩 플로우 → 5단계를 거쳐 권한 화면까지 도달', (tester) async {
    await tester.pumpWidget(_wrap(const OnboardingFlow()));
    expect(find.text('근무 시각을 알려주세요'), findsOneWidget);

    for (final _ in [0, 1, 2, 3]) {
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
    await tester.pumpWidget(
      _wrap(const OnboardingFlow(healthSource: DemoHealthSource())),
    );
    for (final _ in [0, 1, 2, 3]) {
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

  testWidgets('홈에서 AI 인사이트·피부 루틴을 바로 보고, 상세는 링크로 간다', (tester) async {
    // 예전엔 둘 다 별도 화면으로 들어가야 볼 수 있었다. 지금은 홈 하단에
    // 펼쳐지고, 액토그램 같은 상세만 AI 리포트로 넘긴다.
    // ListView가 지연 생성이라, 화면 밖 섹션은 스크롤해야 만들어진다.
    await tester.binding.setSurfaceSize(const Size(400, 5000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    AppState.instance.saveConsent(privacy: true, ai: true);
    AppState.instance.saveAiComment('테스트용 개인화 인사이트');

    await tester.pumpWidget(
      _wrap(const HomeScreen(healthSource: DemoHealthSource())),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 오늘의 한 줄'), findsOneWidget);
    expect(find.text('피부 루틴'), findsOneWidget);

    await tester.tap(find.text('리듬 자세히 보기'));
    await tester.pumpAndSettle();
    expect(find.byType(AiReportScreen), findsOneWidget);
  });

  testWidgets('피부 루틴 섹션 → 점수·게이지·진단 문구가 없어야 한다', (tester) async {
    // 근거 문서 §2·§5가 명시적으로 금지한 패턴. 화면이 홈으로 옮겨졌어도
    // 이 보증은 그대로 지켜야 한다.
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(const HomeScreen(healthSource: DemoHealthSource())),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('피부 루틴'),
      300,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    expect(find.text('벽시계의 AM·PM 대신, 내 근무와 수면에 맞춘 생체 루틴'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data != null &&
            RegExp(r'\d+점').hasMatch(widget.data!),
      ),
      findsNothing,
    );
  });

  testWidgets('홈 헤더 설정 아이콘 → 설정 화면으로 이동', (tester) async {
    await tester.pumpWidget(
      _wrap(const HomeScreen(healthSource: DemoHealthSource())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('홈 화면 → 계산 엔진이 실제 넛지를 채워 렌더링한다 (로딩 스피너가 사라지고 행동 목록이 뜸)', (
    tester,
  ) async {
    // 실기기 플랫폼 채널이 없는 위젯 테스트 환경이라 DemoHealthSource를 주입한다.
    await tester.pumpWidget(
      _wrap(const HomeScreen(healthSource: DemoHealthSource())),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    // 넛지 개수는 실행 시각(now)에 따라 달라질 수 있어(§5, 과거 시각 제외)
    // 개수를 단언하지 않는다 — 로딩이 끝나고 계산된 섹션이 뜨는지만 본다.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('오늘의 행동'), findsOneWidget);
  });
}
