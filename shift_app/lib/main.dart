import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

void main() {
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
      // 영구저장이 아직 없어(Drift 미구현) 앱을 재시작하면 로그인 상태도
      // 초기화된다 — AppState는 메모리 세션 상태다.
      home: const LoginScreen(),
    );
  }
}
