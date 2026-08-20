import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/auth_field.dart';
import 'login_screen.dart';
import 'onboarding_flow.dart';
import 'privacy_policy_screen.dart';

/// Supabase Auth 이메일 회원가입 화면. 이름과 동의 내역은 Auth metadata로
/// 전달되고 DB trigger가 `profiles`에 사용자 소유 행을 생성한다.
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

  // 필수 동의는 체크 전까지 가입 버튼이 비활성이다. AI 리포트용 국외
  // 이전은 별도 선택 항목 — 필수 동의에 끼워 넣으면 '동의하지 않을 권리'가
  // 사라진다(privacy_policy_screen.dart §5).
  bool _privacyConsent = false;
  bool _aiConsent = false;
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final result = await AuthService.signUp(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        privacyConsent: _privacyConsent,
        aiConsent: _aiConsent,
      );
      if (!mounted) return;
      if (result.requiresEmailConfirmation) {
        await showDialog<void>(
          context: context,
          builder: (context) => const AlertDialog(
            title: Text('이메일을 확인해주세요'),
            content: Text('인증 메일의 링크를 누른 뒤 로그인하면 가입이 완료돼요.'),
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OnboardingFlow()),
          (route) => false,
        );
      }
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
              Text('슬립레디와 함께 리듬을 관리해요', style: AppTypography.heading04),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '몇 가지만 알려주시면 바로 시작할 수 있어요',
                style: AppTypography.body02.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              AuthField(
                label: '이름',
                controller: _nameController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '이름을 입력해주세요' : null,
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
                validator: (v) =>
                    (v == null || v.length < 6) ? '6자 이상 입력해주세요' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AuthField(
                label: '비밀번호 확인',
                controller: _confirmController,
                obscureText: true,
                validator: (v) =>
                    v != _passwordController.text ? '비밀번호가 일치하지 않아요' : null,
              ),
              const SizedBox(height: AppSpacing.xxl),
              _ConsentTile(
                value: _privacyConsent,
                onChanged: (v) => setState(() => _privacyConsent = v),
                label: '[필수] 개인정보 수집·이용에 동의합니다',
                sub: '근무표·수면 정보를 리듬 계산에 사용해요',
                onOpenPolicy: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PrivacyPolicyScreen(),
                  ),
                ),
              ),
              _ConsentTile(
                value: _aiConsent,
                onChanged: (v) => setState(() => _aiConsent = v),
                label: '[선택] AI 리포트를 위한 국외 이전에 동의합니다',
                sub:
                    '리포트를 열 때 근무·수면 요약이 Google(Gemini)로 전송돼요. '
                    '동의하지 않아도 넛지는 그대로 받을 수 있어요',
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary500,
                    foregroundColor: AppColors.gray900,
                    disabledBackgroundColor: AppColors.gray100,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _privacyConsent && !_loading ? _submit : null,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('가입하기', style: AppTypography.button03),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  child: Text(
                    '이미 계정이 있으신가요? 로그인',
                    style: AppTypography.caption01.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 가입 화면의 동의 항목 한 줄.
class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.value,
    required this.onChanged,
    required this.label,
    required this.sub,
    this.onOpenPolicy,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final String sub;
  final VoidCallback? onOpenPolicy;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(label, style: AppTypography.body02),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: AppTypography.caption02.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (onOpenPolicy != null)
              TextButton(
                onPressed: onOpenPolicy,
                child: Text(
                  '전문',
                  style: AppTypography.caption01.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
