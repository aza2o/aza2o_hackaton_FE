import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'root_shell.dart';
import 'roster_upload_screen.dart';

/// 권한 온보딩 (`SHIFT_개발기획서.md` §7-2). 알림·정확 알람(Android)·배터리
/// 최적화 예외를 요청하는 화면. 배터리 최적화 예외 요청 호출은 아직 안
/// 붙였다(TODO) — 알림 권한은 `NotificationService`로 실제 요청한다.
/// HealthKit/Health Connect 권한은
/// 온보딩 4단계(`onboarding_flow.dart`의 `_CalibrationStep`)에서 이미
/// 요청하므로 여기서는 다루지 않는다.
class PermissionScreen extends StatelessWidget {
  const PermissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    return Scaffold(
      appBar: AppBar(title: const Text('권한 설정')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text('알림이 제때 오려면 필요해요', style: AppTypography.heading04),
                  const SizedBox(height: AppSpacing.sm),
                  Text('넛지는 타이밍이 곧 효과예요 — 아래 권한이 있어야 정확한 시각에 알려드릴 수 있어요',
                      style: AppTypography.body02.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.xxl),
                  const _PermissionCard(
                    icon: Icons.notifications_active_outlined,
                    title: '알림 권한',
                    desc: '넛지·주간 리포트 알림을 위해 필요해요',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (isAndroid) ...[
                    const _PermissionCard(
                      icon: Icons.alarm_outlined,
                      title: '정확한 알람',
                      desc: 'Android 12 이상에서 정확한 시각에 알림을 보내려면 별도 허용이 필요해요',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const _PermissionCard(
                      icon: Icons.battery_charging_full_outlined,
                      title: '배터리 최적화 예외',
                      desc: '절전 기능이 알림을 지연·차단할 수 있어요. 예외로 등록해주세요',
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.gray50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '나중에 설정 > 근무·데이터에서 다시 요청할 수 있어요.',
                      style: AppTypography.caption01.copyWith(color: AppColors.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary500,
                    foregroundColor: AppColors.gray900,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () async {
                    // 거부돼도 예외 없이 false만 반환한다 — 선택 권한이라
                    // 결과와 무관하게 항상 다음 화면으로 진행한다.
                    await NotificationService.instance.requestPermission();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const RosterUploadScreen()),
                      (route) => false,
                    );
                  },
                  child: Text('권한 허용하고 계속하기', style: AppTypography.button03),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const RootShell()),
                    (route) => false,
                  );
                },
                child: Text('나중에 하기',
                    style: AppTypography.body02.copyWith(color: AppColors.textTertiary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.icon, required this.title, required this.desc});
  final IconData icon;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.grayWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.primary50, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppColors.primary900),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.subtitle04),
                const SizedBox(height: 2),
                Text(desc, style: AppTypography.caption02.copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
