import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_card.dart';
import 'login_screen.dart';
import 'privacy_policy_screen.dart';
import 'roster_upload_screen.dart';
import 'wearable_connection_screen.dart';

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
  String get _healthPlatformName =>
      defaultTargetPlatform == TargetPlatform.android
      ? 'Health Connect'
      : 'Apple Health';

  Future<void> _openWearableConnection() async {
    if (!AppState.instance.wearableConsent) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            '$_healthPlatformName를 연결할까요?',
            style: AppTypography.subtitle02,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '슬립레디가 내 수면과 회복 상태를 계산할 수 있도록 다음 건강 데이터를 읽어요.',
                style: AppTypography.body02,
              ),
              const SizedBox(height: AppSpacing.lg),
              const _HealthConsentLine(
                icon: Icons.bedtime_outlined,
                text: '수면 시작·종료 및 수면 단계',
              ),
              const SizedBox(height: AppSpacing.sm),
              const _HealthConsentLine(
                icon: Icons.monitor_heart_outlined,
                text: '심박변이도 HRV',
              ),
              const SizedBox(height: AppSpacing.sm),
              const _HealthConsentLine(
                icon: Icons.favorite_outline_rounded,
                text: '안정시 심박수',
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '데이터는 읽기 전용이며 건강 앱에 새 기록을 작성하지 않아요. '
                '연결하지 않아도 근무표 기반 기능은 사용할 수 있어요.',
                style: AppTypography.caption02.copyWith(
                  color: AppColors.textTertiary,
                  height: 1.45,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('나중에'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('$_healthPlatformName 연결하기'),
            ),
          ],
        ),
      );
      if (agreed != true || !mounted) return;
      AppState.instance.saveWearableConsent(true);
      setState(() {});
    }

    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const WearableConnectionScreen()));
    if (mounted) setState(() {});
  }

  Future<void> _updateAiConsent(bool value) async {
    AppState.instance.saveConsent(
      privacy: AppState.instance.privacyConsent,
      ai: value,
    );
    setState(() {});
    // 게스트도 AI 인사이트를 사용한다. 동의는 로컬에 저장하되 Supabase
    // 세션이 없는 게스트에게 서버 프로필 업데이트를 요구하지 않는다.
    if (!AuthService.isAuthenticated) return;
    try {
      await AuthService.updateConsent(
        privacyConsent: AppState.instance.privacyConsent,
        aiConsent: value,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('동의 설정을 서버에 저장하지 못했어요. 다시 시도해주세요.')),
      );
    }
  }

  Future<void> _handleSignOut() async {
    final name = AppState.instance.userName;
    final isGuest = name == null || name == '게스트';

    if (isGuest) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('게스트 모드 로그아웃', style: AppTypography.subtitle02),
          content: Text(
            '게스트 모드에서 로그아웃하면 근무표와 수면 기록 등 저장된 데이터가 삭제될 수 있어요. 그래도 로그아웃하시겠습니까?',
            style: AppTypography.body02,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                '그래도 로그아웃',
                style: AppTypography.button03.copyWith(
                  color: AppColors.error01,
                ),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    await AuthService.signOut();
    AppState.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

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
                      Text(
                        AppState.instance.userName ?? '게스트',
                        style: AppTypography.subtitle02,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '3교대 간호사·무료 플랜',
                        style: AppTypography.caption01.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textTertiary,
                  ),
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
                      MaterialPageRoute(
                        builder: (_) => const RosterUploadScreen(),
                      ),
                    ),
                    child: _SettingsRow(
                      label: '근무표 관리',
                      value: '',
                      showChevron: true,
                    ),
                  ),
                  const Divider(
                    height: AppSpacing.xxl,
                    color: AppColors.gray100,
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openWearableConnection,
                    child: _SettingsRow(
                      label: '웨어러블 연동',
                      value: AppState.instance.wearableConsent ? '연동됨' : '연결하기',
                      showChevron: true,
                    ),
                  ),
                  const Divider(
                    height: AppSpacing.xxl,
                    color: AppColors.gray100,
                  ),
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
                  const Divider(
                    height: AppSpacing.xxl,
                    color: AppColors.gray100,
                  ),
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
                            Text(
                              '근무·수면 요약이 Google(Gemini)로 전송돼요',
                              style: AppTypography.caption02.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: AppState.instance.aiConsent,
                        onChanged: _updateAiConsent,
                      ),
                    ],
                  ),
                  const Divider(
                    height: AppSpacing.xxl,
                    color: AppColors.gray100,
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    ),
                    child: _SettingsRow(
                      label: '개인정보 처리방침',
                      value: '',
                      showChevron: true,
                    ),
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
                  const Divider(
                    height: AppSpacing.xxl,
                    color: AppColors.gray100,
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _handleSignOut,
                    child: Row(
                      children: [
                        Text(
                          '로그아웃',
                          style: AppTypography.body02.copyWith(
                            color: AppColors.error01,
                          ),
                        ),
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

class _HealthConsentLine extends StatelessWidget {
  const _HealthConsentLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary900),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: AppTypography.caption01)),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: AppSpacing.sm,
        left: AppSpacing.sm,
      ),
      child: Text(
        label,
        style: AppTypography.subtitle04.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    required this.value,
    this.showChevron = false,
  });
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
              Text(
                value,
                style: AppTypography.body02.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            if (showChevron || value.isNotEmpty) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textTertiary,
              ),
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
