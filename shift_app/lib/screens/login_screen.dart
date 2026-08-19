import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/auth_field.dart';
import 'onboarding_flow.dart';
import 'root_shell.dart';
import 'signup_screen.dart';

/// 로그인 — 앱 최초 화면(`main.dart`). ⚠️ 실제 인증 서버가 없다 — 같은
/// 세션에서 `SignupScreen`으로 만든 계정과 이메일·비밀번호가 일치하는지만
/// `AppState.tryLogin()`으로 메모리에서 대조한다(`AppState` docstring 참고).
/// 계정이 없어도 "게스트로 계속하기"로 온보딩까지 그대로 진입 가능 —
/// 로그인을 강제해서 진입 장벽을 만들지 않는다는 게 다른 화면들의
/// 기존 원칙(권한 화면의 "나중에 하기" 등)과 일관됨.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final ok = AppState.instance.tryLogin(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('이메일 또는 비밀번호가 맞지 않아요')));
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RootShell()),
      (route) => false,
    );
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
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const SizedBox(height: AppSpacing.xxxl),
              Text('SHIFT', style: AppTypography.heading01.copyWith(color: AppColors.primary900)),
              const SizedBox(height: AppSpacing.sm),
              Text('교대근무자를 위한 생체리듬 코치',
                  style: AppTypography.body02.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.xxxl),
              AuthField(
                label: '이메일',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => (v == null || v.isEmpty) ? '이메일을 입력해주세요' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AuthField(
                label: '비밀번호',
                controller: _passwordController,
                obscureText: true,
                validator: (v) => (v == null || v.isEmpty) ? '비밀번호를 입력해주세요' : null,
              ),
              const SizedBox(height: AppSpacing.xxl),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary500,
                    foregroundColor: AppColors.gray900,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _submit,
                  child: Text('로그인', style: AppTypography.button03),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.gray200),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const SignupScreen())),
                  child: Text('회원가입',
                      style: AppTypography.button03.copyWith(color: AppColors.textPrimary)),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: TextButton(
                  onPressed: _continueAsGuest,
                  child: Text('게스트로 계속하기',
                      style: AppTypography.caption01.copyWith(color: AppColors.textTertiary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
