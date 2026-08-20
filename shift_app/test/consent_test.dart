// 개인정보 동의 — 필수 동의 없이는 가입이 안 되고, AI 리포트는 국외 이전
// 선택 동의가 없으면 외부 호출 자체를 하지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_app/screens/ai_report_screen.dart';
import 'package:shift_app/screens/privacy_policy_screen.dart';
import 'package:shift_app/screens/signup_screen.dart';
import 'package:shift_app/state/app_state.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.signOut();
  });

  testWidgets('필수 동의를 체크해야 가입 버튼이 열린다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const SignupScreen()));

    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );

    await tester.tap(find.textContaining('[필수] 개인정보'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });

  test('선택 동의(국외 이전)는 필수와 따로 저장된다', () {
    AppState.instance.saveConsent(privacy: true, ai: false);
    expect(AppState.instance.privacyConsent, isTrue);
    expect(
      AppState.instance.aiConsent,
      isFalse,
      reason: '선택 동의는 필수 동의에 딸려 들어가면 안 된다',
    );
    expect(AppState.instance.consentAt, isNotNull);
  });

  testWidgets('전문 버튼 → 개인정보 처리방침이 열리고 국외 이전이 명시돼 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const SignupScreen()));
    await tester.tap(find.text('전문'));
    await tester.pumpAndSettle();

    expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
    expect(find.textContaining('제3자 제공 및 국외 이전'), findsOneWidget);
  });

  testWidgets('국외 이전 미동의면 AI 리포트가 외부 호출 대신 안내를 보여준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    AppState.instance.saveConsent(privacy: true, ai: false);

    await tester.pumpWidget(_wrap(const AiReportScreen()));
    await tester.pumpAndSettle();

    expect(find.text('AI 인사이트는 동의가 필요해요'), findsOneWidget);

    // 동의 전에는 요청 버튼도 잠겨 있어야 한다 — 눌러서 나가는 경로가
    // 하나라도 열려 있으면 게이트가 의미 없다.
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '이 상태로 조언 받기'),
    );
    expect(button.onPressed, isNull);
  });
}
