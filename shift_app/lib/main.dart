import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/root_shell.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 저장된 세션 복원 — 있으면 로그인·온보딩을 건너뛰고 바로 홈으로 간다.
  await AppState.instance.load();
  runApp(const ShiftApp());
}

class ShiftApp extends StatelessWidget {
  const ShiftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SHIFT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // 최초 실행 플로우: 로그인/회원가입(또는 게스트) → 온보딩 →
      // 권한 온보딩 → 로스터 입력 → 홈(`SHIFT_프론트엔드_기획서.md` §2).
      //
      // 두 번째 실행부터는 [AppState.load]가 복원해준 값으로 이 플로우를
      // 통째로 건너뛴다. 온보딩까지 끝냈는지(`hasProfile`)를 기준으로 삼는다
      // — 로그인만 하고 온보딩 중에 앱을 껐다면 다시 온보딩부터다.
      home: AppState.instance.hasProfile
          ? const RootShell()
          : const LoginScreen(),
    );
  }
}
