import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/auth_field.dart';
import 'onboarding_flow.dart';
import 'root_shell.dart';
import 'signup_screen.dart';

/// Supabase Auth 이메일 로그인 화면. 계정이 없어도 게스트로 온보딩에
/// 진입할 수 있으며, 로그인 시 서버 프로필과 일일 기록을 복원한다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => AppState.instance.hasProfile
              ? const RootShell()
              : const OnboardingFlow(),
        ),
        (route) => false,
      );
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('AuthException: ', '')),
        ),
      );
    }
  }

  void _continueAsGuest() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingFlow()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompactHeight = MediaQuery.sizeOf(context).height < 700;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFDCEBFF),
                    Color(0xFFFFFBF0),
                    Color(0xFFFFE4A3),
                  ],
                  stops: [0, 0.56, 1],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _SleepPattern())),
          ),
          SafeArea(
            child: Form(
              key: _formKey,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: (MediaQuery.sizeOf(context).width * 0.08)
                          .clamp(AppSpacing.xxl, 40),
                      vertical: isCompactHeight ? AppSpacing.sm : AppSpacing.lg,
                    ),
                    children: [
                      SizedBox(height: isCompactHeight ? 20 : 56),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '슬립',
                              style: AppTypography.heading01.copyWith(
                                color: AppColors.gray900,
                                fontFamily: 'Jua',
                                fontSize: 52,
                                fontWeight: FontWeight.w400,
                                height: 1.05,
                                letterSpacing: -0.6,
                              ),
                            ),
                            TextSpan(
                              text: '레디',
                              style: AppTypography.heading01.copyWith(
                                color: AppColors.primary900,
                                fontFamily: 'Jua',
                                fontSize: 52,
                                fontWeight: FontWeight.w400,
                                height: 1.05,
                                letterSpacing: -0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '교대근무자를 위한 생체리듬 코치',
                        style: AppTypography.body02.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: isCompactHeight ? 24 : 44),
                      AuthField(
                        label: '이메일',
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) => value == null || value.isEmpty
                            ? '이메일을 입력해주세요'
                            : null,
                      ),
                      SizedBox(
                        height: isCompactHeight ? AppSpacing.md : AppSpacing.xl,
                      ),
                      AuthField(
                        label: '비밀번호',
                        controller: _passwordController,
                        obscureText: true,
                        validator: (value) => value == null || value.isEmpty
                            ? '비밀번호를 입력해주세요'
                            : null,
                      ),
                      SizedBox(height: isCompactHeight ? 20 : 36),
                      SizedBox(
                        width: double.infinity,
                        height: isCompactHeight ? 52 : 60,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary500,
                            foregroundColor: AppColors.gray900,
                            elevation: 8,
                            shadowColor: const Color(0x88D99500),
                            surfaceTintColor: Colors.transparent,
                            overlayColor: const Color(0x2EFFFFFF),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text('로그인', style: AppTypography.button03),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        height: isCompactHeight ? 52 : 60,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xEFFFFFFF),
                            elevation: 3,
                            shadowColor: const Color(0x33475A76),
                            surfaceTintColor: Colors.transparent,
                            overlayColor: const Color(0x1AFFFFFF),
                            side: const BorderSide(color: AppColors.gray200),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SignupScreen(),
                            ),
                          ),
                          child: Text(
                            '회원가입',
                            style: AppTypography.button03.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: isCompactHeight ? AppSpacing.xs : AppSpacing.lg,
                      ),
                      Center(
                        child: TextButton(
                          onPressed: _continueAsGuest,
                          child: Text(
                            '게스트로 계속하기',
                            style: AppTypography.caption01.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SleepPattern extends CustomPainter {
  const _SleepPattern();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF5E7DA8).withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    void clock(Offset center, double radius, double angle) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      canvas.drawCircle(Offset.zero, radius, stroke);
      canvas.drawLine(Offset.zero, Offset(0, -radius * 0.48), stroke);
      canvas.drawLine(Offset.zero, Offset(radius * 0.38, 0), stroke);
      canvas.restore();
    }

    clock(Offset(size.width * 0.84, size.height * 0.19), 28, 0.24);
    clock(Offset(size.width * 0.13, size.height * 0.66), 21, -0.32);
    clock(Offset(size.width * 0.79, size.height * 0.88), 35, 0.48);

    void zzz(String text, Offset offset, double angle, double fontSize) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: const Color(0xFFD58A00).withValues(alpha: 0.16),
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.rotate(angle);
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    }

    zzz('Zzz', Offset(size.width * 0.61, size.height * 0.08), -0.18, 25);
    zzz('Z', Offset(size.width * 0.08, size.height * 0.38), 0.24, 42);
    zzz('zz', Offset(size.width * 0.68, size.height * 0.59), -0.35, 34);
    zzz('Zzz', Offset(size.width * 0.73, size.height * 0.29), 0.16, 18);
    zzz('zz', Offset(size.width * 0.12, size.height * 0.52), -0.12, 22);
    zzz('Z', Offset(size.width * 0.82, size.height * 0.76), 0.28, 30);
    zzz('Zzz', Offset(size.width * 0.18, size.height * 0.92), -0.24, 20);

    final dot = Paint()..color = AppColors.primary500.withValues(alpha: 0.2);
    for (final point in [
      Offset(size.width * 0.17, size.height * 0.18),
      Offset(size.width * 0.91, size.height * 0.45),
      Offset(size.width * 0.26, size.height * 0.85),
    ]) {
      canvas.drawCircle(point, 5 + math.sin(point.dy) * 2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
