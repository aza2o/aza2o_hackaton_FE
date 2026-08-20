import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_card.dart';
import 'login_screen.dart';
import 'privacy_policy_screen.dart';
import 'roster_upload_screen.dart';

/// 기존 확정 디자인(구 Figma 파일 `35:3968`)을 그대로 구현.
///
/// 하단 탭에서 홈 우측 상단 아이콘으로 옮겨졌기 때문에(그 탭 자리는 근무
/// 달력이 가져갔다) 뒤로 갈 수 있게 AppBar를 둔다 — 탭이던 시절엔 화면
/// 안의 '설정' 제목만 있으면 됐다.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            AppCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppState.instance.userName ?? '게스트',
                          style: AppTypography.subtitle02),
                      const SizedBox(height: 4),
                      Text('3교대 간호사·무료 플랜',
                          style: AppTypography.caption01
                              .copyWith(color: AppColors.textTertiary)),
                    ],
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textTertiary),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            _SectionLabel('근무·데이터'),
            AppCard(
              child: Column(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RosterUploadScreen()),
                    ),
                    child: _SettingsRow(
                        label: '근무표 관리', value: '', showChevron: true),
                  ),
                  const Divider(height: AppSpacing.xxl, color: AppColors.gray100),
                  _SettingsRow(label: '웨어러블 연동', value: 'Apple Health'),
                  const Divider(height: AppSpacing.xxl, color: AppColors.gray100),
                  _SettingsRow(label: '구독 서비스', value: '무료 플랜'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            _SectionLabel('알림'),
            AppCard(
              child: Column(
                children: [
                  _SettingsToggleRow(label: '행동 알림', value: true),
                  const Divider(height: AppSpacing.xxl, color: AppColors.gray100),
                  _SettingsToggleRow(label: '주간 리포트 알림', value: false),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            _SectionLabel('AI 리포트'),
            AppCard(
              child: Column(
                children: [
                  // 가입 때 받은 선택 동의를 언제든 켜고 끌 수 있어야 한다
                  // — 동의 철회가 막혀 있으면 '선택' 동의가 아니다.
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('AI 인사이트 사용', style: AppTypography.body02),
                            const SizedBox(height: 2),
                            Text('근무·수면 요약이 Google(Gemini)로 전송돼요',
                                style: AppTypography.caption02
                                    .copyWith(color: AppColors.textTertiary)),
                          ],
                        ),
                      ),
                      Switch(
                        value: AppState.instance.aiConsent,
                        onChanged: (v) => setState(() {
                          AppState.instance.saveConsent(
                            privacy: AppState.instance.privacyConsent,
                            ai: v,
                          );
                        }),
                      ),
                    ],
                  ),
                  const Divider(height: AppSpacing.xxl, color: AppColors.gray100),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                    ),
                    child: _SettingsRow(
                        label: '개인정보 처리방침', value: '', showChevron: true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            _SectionLabel('기타'),
            AppCard(
              child: Column(
                children: [
                  _SettingsRow(label: '문의 및 도움말', value: '', showChevron: true),
                  const Divider(height: AppSpacing.xxl, color: AppColors.gray100),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      AppState.instance.signOut();
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    },
                    child: Row(
                      children: [
                        Text('로그아웃',
                            style: AppTypography.body02.copyWith(color: AppColors.error01)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm, left: AppSpacing.sm),
      child: Text(label,
          style: AppTypography.subtitle04.copyWith(color: AppColors.textTertiary)),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.value, this.showChevron = false});
  final String label;
  final String value;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.body02),
        Row(
          children: [
            if (value.isNotEmpty)
              Text(value,
                  style: AppTypography.body02
                      .copyWith(color: AppColors.textTertiary)),
            if (showChevron || value.isNotEmpty) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textTertiary),
            ],
          ],
        ),
      ],
    );
  }
}

class _SettingsToggleRow extends StatefulWidget {
  const _SettingsToggleRow({required this.label, required this.value});
  final String label;
  final bool value;

  @override
  State<_SettingsToggleRow> createState() => _SettingsToggleRowState();
}

class _SettingsToggleRowState extends State<_SettingsToggleRow> {
  late bool _value = widget.value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(widget.label, style: AppTypography.body02),
        Switch(
          value: _value,
          activeTrackColor: AppColors.primary500,
          onChanged: (v) => setState(() => _value = v),
        ),
      ],
    );
  }
}
