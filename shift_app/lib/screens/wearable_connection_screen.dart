import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_card.dart';

class WearableConnectionScreen extends StatefulWidget {
  const WearableConnectionScreen({super.key});

  @override
  State<WearableConnectionScreen> createState() =>
      _WearableConnectionScreenState();
}

class _WearableConnectionScreenState extends State<WearableConnectionScreen> {
  bool _syncing = false;
  DateTime _lastSync = DateTime.now().subtract(const Duration(minutes: 2));

  Future<void> _sync() async {
    setState(() => _syncing = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _lastSync = DateTime.now();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('최근 Apple Health 데이터를 동기화했어요.')),
    );
  }

  String get _syncLabel {
    final difference = DateTime.now().difference(_lastSync);
    if (difference.inMinutes < 1) return '방금 동기화';
    return '${difference.inMinutes}분 전 동기화';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('웨어러블 연동')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF6EE),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.grayWhite,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.watch_outlined,
                      size: 38,
                      color: AppColors.gray900,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('Apple Watch 연결됨', style: AppTypography.heading04),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF34C759),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _syncLabel,
                        style: AppTypography.caption01
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text('최근 동기화 데이터', style: AppTypography.subtitle03),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: const [
                Expanded(
                  child: _HealthMetric(
                    icon: Icons.bedtime_outlined,
                    label: '최근 수면',
                    value: '6h 31m',
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _HealthMetric(
                    icon: Icons.monitor_heart_outlined,
                    label: 'HRV',
                    value: '-0.3σ',
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _HealthMetric(
                    icon: Icons.favorite_border_rounded,
                    label: '안정심박',
                    value: '65bpm',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text('가져오는 정보', style: AppTypography.subtitle03),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: Column(
                children: const [
                  _HealthPermissionRow(
                    icon: Icons.nights_stay_outlined,
                    title: '수면 시작·종료 및 수면 단계',
                    description: '필요 수면량과 수면 부족을 계산해요',
                  ),
                  Divider(height: AppSpacing.xxl, color: AppColors.gray100),
                  _HealthPermissionRow(
                    icon: Icons.show_chart_rounded,
                    title: '심박변이도 HRV',
                    description: '평소 대비 회복 변화를 확인해요',
                  ),
                  Divider(height: AppSpacing.xxl, color: AppColors.gray100),
                  _HealthPermissionRow(
                    icon: Icons.favorite_outline_rounded,
                    title: '안정시 심박수',
                    description: '피로 누적 신호를 함께 읽어요',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.gray50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '시연 환경에서는 Apple Health 형식의 데모 데이터를 사용해요. '
                      '실기기 배포 시 같은 화면에서 HealthKit 데이터로 전환됩니다.',
                      style: AppTypography.caption02.copyWith(
                        color: AppColors.textTertiary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _syncing ? null : _sync,
                icon: _syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                label: Text(_syncing ? '동기화 중...' : '데이터 다시 동기화'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthMetric extends StatelessWidget {
  const _HealthMetric({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.grayWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray100),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.primary900),
          const SizedBox(height: 7),
          Text(label, style: AppTypography.caption03.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: 3),
          Text(value, style: AppTypography.subtitle04),
        ],
      ),
    );
  }
}

class _HealthPermissionRow extends StatelessWidget {
  const _HealthPermissionRow({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary900),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.body02),
              const SizedBox(height: 2),
              Text(
                description,
                style: AppTypography.caption02.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
        const Icon(Icons.check_circle_rounded, color: Color(0xFF34C759), size: 21),
      ],
    );
  }
}
