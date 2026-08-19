import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_card.dart';

/// 피부·손 루틴 (Figma 신규 파일 `17:2`). `SHIFT_skin_track_plan.md`의
/// F1(생체 루틴 타이밍)/F2(퇴근길 자외선 알림)만 반영한다. F3(손 보습)은
/// 기능에서 제외하기로 결정됨(2026-08-18).
/// **점수·게이지·진단성 문구를 절대 넣지 않는다** — 근거 문서 §2, §5가
/// 명시적으로 금지한 패턴.
class SkinRoutineScreen extends StatelessWidget {
  const SkinRoutineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('피부·손 루틴')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('벽시계가 아니라 오늘 당신의 기상·취침 시각 기준으로 제안해요',
                style: AppTypography.body02.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.xxl),
            Text('오늘의 루틴 타이밍', style: AppTypography.subtitle03),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _RoutineCard(
                    icon: '🌤️',
                    badgeColor: AppColors.primary50,
                    tag: '기상 직후 · AM',
                    time: '14:30',
                    label: '주간 보호 루틴',
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _RoutineCard(
                    icon: '🌙',
                    badgeColor: AppColors.information03,
                    tag: '취침 전 · PM',
                    time: '07:00',
                    label: '야간 보습 루틴',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text('퇴근길 자외선 알림', style: AppTypography.subtitle03),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.warning03,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: const Text('🕶️', style: TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('오늘 07:00 퇴근 · 자외선지수 보통(4)',
                            style: AppTypography.subtitle04),
                        const SizedBox(height: 4),
                        Text('선글라스 하나로 리듬 보호와 자외선 차단을 함께',
                            style: AppTypography.caption01
                                .copyWith(color: AppColors.textSecondary)),
                        const SizedBox(height: AppSpacing.sm),
                        Text('위상 전진 방지 + UV 차단 · 나이트 근무 전용',
                            style: AppTypography.caption03
                                .copyWith(color: AppColors.textPlaceholder)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.gray50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('우리가 하는 것 · 하지 않는 것',
                      style: AppTypography.subtitle04
                          .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '무엇을 바르는지가 아니라 언제 바르는지를 제안해요. '
                    '피부 상태를 진단하거나 성분 효과를 주장하지 않습니다.',
                    style: AppTypography.caption01
                        .copyWith(color: AppColors.textTertiary),
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

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.icon,
    required this.badgeColor,
    required this.tag,
    required this.time,
    required this.label,
  });

  final String icon;
  final Color badgeColor;
  final String tag;
  final String time;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text(icon, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(tag, style: AppTypography.caption03.copyWith(color: AppColors.textPlaceholder, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(time, style: AppTypography.subtitle01),
          const SizedBox(height: 4),
          Text(label, style: AppTypography.caption01.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
