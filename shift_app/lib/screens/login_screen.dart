import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/auth_field.dart';
import 'onboarding_flow.dart';
import 'root_shell.dart';
import 'signup_screen.dart';

/// Supabase Auth 이메일 로그인 화면. 계정이 없어도 "게스트로 계속하기"로
/// 온보딩에 진입할 수 있으며, 로그인 시 서버 프로필과 일일 기록을 복원한다.
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
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          // 좌우 여백을 화면 폭의 8%까지 주되 넓은 화면(웹·태블릿)에서는
          // 폼이 끝없이 늘어나지 않게 460px로 묶는다.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: (MediaQuery.sizeOf(context).width * 0.08).clamp(
                    AppSpacing.xxl,
                    40,
                  ),
                  vertical: AppSpacing.lg,
                ),
                children: [
                  const SizedBox(height: 56),
                  Text(
                    '슬립레디',
                    style: AppTypography.heading01.copyWith(
                      color: AppColors.primary900,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '교대근무자를 위한 생체리듬 코치',
                    style: AppTypography.body02.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 44),
                  AuthField(
                    label: '이메일',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) =>
                        (v == null || v.isEmpty) ? '이메일을 입력해주세요' : null,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AuthField(
                    label: '비밀번호',
                    controller: _passwordController,
                    obscureText: true,
                    validator: (v) =>
                        (v == null || v.isEmpty) ? '비밀번호를 입력해주세요' : null,
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary500,
                        foregroundColor: AppColors.gray900,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('로그인', style: AppTypography.button03),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.gray200),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SignupScreen()),
                      ),
                      child: Text(
                        '회원가입',
                        style: AppTypography.button03.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
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
    );
  }
}
