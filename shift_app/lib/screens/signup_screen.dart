import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/auth_field.dart';
import 'login_screen.dart';
import 'onboarding_flow.dart';

/// 회원가입. 필드는 Drift `user_profile` 테이블 초안의 계정 컬럼
/// (`name`/`email`/`password_hash`)을 그대로 따른다
/// (`docs/SHIFT_프론트엔드_구현체크리스트.md` §5).
///
/// ⚠️ 실제 인증 서버가 없다 — `AppState.signUp()`이 메모리에 평문으로만
/// 들고 있는 데모 구현이다. 진짜 계정 시스템이 붙기 전까지 보안 기능으로
/// 오해하면 안 된다.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    AppState.instance.signUp(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingFlow()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text('SHIFT와 함께 리듬을 관리해요', style: AppTypography.heading04),
              const SizedBox(height: AppSpacing.sm),
              Text('몇 가지만 알려주시면 바로 시작할 수 있어요',
                  style: AppTypography.body02.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.xxl),
              AuthField(
                label: '이름',
                controller: _nameController,
                validator: (v) => (v == null || v.trim().isEmpty) ? '이름을 입력해주세요' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AuthField(
                label: '이메일',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: (v) =>
                    (v == null || !v.contains('@')) ? '올바른 이메일을 입력해주세요' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AuthField(
                label: '비밀번호',
                controller: _passwordController,
                obscureText: true,
                validator: (v) => (v == null || v.length < 4) ? '4자 이상 입력해주세요' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AuthField(
                label: '비밀번호 확인',
                controller: _confirmController,
                obscureText: true,
                validator: (v) => v != _passwordController.text ? '비밀번호가 일치하지 않아요' : null,
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
                  child: Text('가입하기', style: AppTypography.button03),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginScreen())),
                  child: Text('이미 계정이 있으신가요? 로그인',
                      style: AppTypography.caption01.copyWith(color: AppColors.textSecondary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
