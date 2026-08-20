import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shift_app/main.dart';
import 'package:shift_app/screens/login_screen.dart';
import 'package:shift_app/screens/signup_screen.dart';
import 'package:shift_app/screens/onboarding_flow.dart';
import 'package:shift_app/screens/permission_screen.dart';
import 'package:shift_app/screens/roster_upload_screen.dart';
import 'package:shift_app/screens/roster_confirm_screen.dart';
import 'package:shift_app/screens/home_screen.dart';
import 'package:shift_app/screens/settings_screen.dart';
import 'package:shift_app/state/app_state.dart';

void main() {
  setUp(() => AppState.instance.signOut()); // 테스트 간 싱글턴 상태 격리

  testWidgets('앱 최초 실행 → 회원가입·온보딩·권한·로스터 확인을 거쳐 홈까지 도달하면, '
      '가입 때 입력한 이름이 홈·설정 화면에 그대로 뜬다', (WidgetTester tester) async {
    // 로스터 입력 화면 CTA가 기본 테스트 뷰포트(800x600)보다 아래에 있어
    // 세로로 넉넉하게 키운다(`screens_test.dart`의 같은 화면 테스트와 동일).
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ShiftApp());
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.tap(find.text('회원가입'));
    await tester.pumpAndSettle();
    expect(find.byType(SignupScreen), findsOneWidget);

    // 각 필드에 접근성 라벨이 없어 순서(이름/이메일/비밀번호/비밀번호 확인)로 찾는다.
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '테스트유저');
    await tester.enterText(fields.at(1), 'test@example.com');
    await tester.enterText(fields.at(2), 'pw1234');
    await tester.enterText(fields.at(3), 'pw1234');

    // 개인정보 필수 동의 전에는 가입 버튼이 잠겨 있다.
    final signupButton = tester.widget<ElevatedButton>(
      find.byType(ElevatedButton),
    );
    expect(signupButton.onPressed, isNull);

    await tester.tap(find.textContaining('[필수] 개인정보'));
    await tester.pumpAndSettle();

    // 실제 Supabase 가입은 네트워크 통합 테스트의 책임이다. 위젯 테스트는
    // 인증된 사용자 상태를 주입해 이후 온보딩과 이름 전달을 검증한다.
    AppState.instance.signUp(
      name: '테스트유저',
      email: 'test@example.com',
      password: 'pw1234',
    );
    await tester.pumpWidget(const MaterialApp(home: OnboardingFlow()));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingFlow), findsOneWidget);

    for (final _ in [0, 1, 2, 3]) {
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();
    expect(find.byType(PermissionScreen), findsOneWidget);

    await tester.tap(find.text('권한 허용하고 계속하기'));
    await tester.pumpAndSettle();
    expect(find.byType(RosterUploadScreen), findsOneWidget);

    // "1차: 엑셀 업로드"는 실제 file_picker + POST /roster/parse를
    // 태우므로(위젯 테스트에서 검증 불가) 서버 없이도 되는 2차 경로로 진행한다.
    await tester.tap(find.text('패턴 선택 + 캘린더 편집'));
    await tester.pumpAndSettle();
    expect(find.byType(RosterConfirmScreen), findsOneWidget);

    await tester.tap(find.text('확인하고 넛지 받기'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('안녕하세요, 테스트유저님'), findsOneWidget);

    // 이 플로우는 RootShell을 거쳐 실제 플랫폼 어댑터로 HomeScreen에
    // 도달하므로(DI 주입 지점 없음), "최근 회복 상태" 조회의 8초 타임아웃이
    // 테스트 종료 시점에 pending 타이머로 남지 않도록 페이크 클록을 흘려보낸다.
    await tester.pump(const Duration(seconds: 9));

    // 설정은 하단 탭에서 홈 우측 상단 아이콘으로 옮겨졌다(그 탭 자리는
    // 근무 달력이 가져갔다).
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('테스트유저'), findsOneWidget);
  });

  testWidgets('로그인 화면 → 게스트로 계속하기는 가입 없이 바로 온보딩으로 간다', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ShiftApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('게스트로 계속하기'));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingFlow), findsOneWidget);
  });
}
