import 'dart:io';

import 'package:flutter/material.dart';

import '../health/health_signal_source.dart';
import '../state/app_state.dart';
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
  bool _connected = AppState.instance.isDemoAccount;
  bool _usingDemo = true;
  DateTime _lastSync = DateTime.now().subtract(const Duration(minutes: 2));
  String _sleepValue = '6h 31m';
  String _hrvValue = '-0.3σ';
  String _heartRateValue = '65bpm';

  bool get _isAndroid => Platform.isAndroid;
  String get _wearableName => _isAndroid ? 'Galaxy Watch' : 'Apple Watch';
  String get _healthPlatform => _isAndroid ? 'Health Connect' : 'Apple Health';

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final source = AppState.instance.isDemoAccount
          ? const SyncedHealthSource()
          : _isAndroid
          ? AndroidHealthSource()
          : IosHealthSource();
      final authorized = await source.requestAuthorization();
      if (!authorized) {
        throw const FormatException('건강 데이터 읽기 권한이 필요해요.');
      }

      final now = DateTime.now();
      final range = DateRange(now.subtract(const Duration(days: 14)), now);
      final results = await Future.wait<Object?>([
        source.sleepSessions(range),
        source.hrvNormalized(range),
        source.restingHeartRate(range),
      ]);
      final sessions = results[0] as List<HealthSleepSession>;
      final hrv = results[1] as HrvSeries?;
      final heartRate = results[2] as HeartRateSeries?;
      final hasMeasuredData =
          sessions.isNotEmpty ||
          hrv?.points.isNotEmpty == true ||
          heartRate?.points.isNotEmpty == true;

      if (!mounted) return;
      setState(() {
        _syncing = false;
        _connected = true;
        _usingDemo = !hasMeasuredData;
        _lastSync = DateTime.now();
        if (sessions.isNotEmpty) {
          final latest = sessions.last;
          final minutes = latest.end.difference(latest.start).inMinutes;
          _sleepValue = '${minutes ~/ 60}h ${minutes % 60}m';
        }
        if (hrv?.points.isNotEmpty == true) {
          _hrvValue = '${hrv!.points.last.$2.toStringAsFixed(1)}σ';
        }
        if (heartRate?.points.isNotEmpty == true) {
          _heartRateValue = '${heartRate!.points.last.$2.round()}bpm';
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasMeasuredData
                ? '$_healthPlatform의 최근 건강 데이터를 동기화했어요.'
                : '연결은 완료됐지만 최근 데이터가 없어 데모값을 표시해요.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('연동하지 못했어요. $error')));
    }
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
                  Text(
                    _connected
                        ? '$_wearableName 연결됨'
                        : '$_wearableName · $_healthPlatform',
                    style: AppTypography.heading04,
                  ),
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
                        _connected ? _syncLabel : '연동 확인 필요',
                        style: AppTypography.caption01.copyWith(
                          color: AppColors.textSecondary,
                        ),
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
              children: [
                Expanded(
                  child: _HealthMetric(
                    icon: Icons.bedtime_outlined,
                    label: '최근 수면',
                    value: _sleepValue,
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _HealthMetric(
                    icon: Icons.monitor_heart_outlined,
                    label: 'HRV',
                    value: _hrvValue,
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _HealthMetric(
                    icon: Icons.favorite_border_rounded,
                    label: '안정심박',
                    value: _heartRateValue,
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
                      _isAndroid
                          ? (AppState.instance.isDemoAccount
                                ? '심사용 계정에는 Galaxy Watch와 Health Connect에서 가져온 형식의 데모 데이터가 연결돼 있어요.'
                                : _connected && !_usingDemo
                                ? 'Galaxy Watch의 데이터가 Samsung Health와 Health Connect를 거쳐 동기화됐어요.'
                                : 'Samsung Health > 설정 > Health Connect에서 수면과 심박 공유를 허용한 뒤 동기화해주세요. 데이터가 없으면 데모값이 표시돼요.')
                          : (AppState.instance.isDemoAccount
                                ? '심사용 계정에는 Apple Watch와 HealthKit에서 가져온 형식의 데모 데이터가 연결돼 있어요.'
                                : 'Apple Health 권한을 허용하면 HealthKit 데이터를 동기화해요. 데이터가 없으면 데모값이 표시돼요.'),
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
                label: Text(
                  _syncing
                      ? '동기화 중...'
                      : _connected
                      ? '데이터 다시 동기화'
                      : '$_healthPlatform 연동하기',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthMetric extends StatelessWidget {
  const _HealthMetric({
    required this.icon,
    required this.label,
    required this.value,
  });
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
          Text(
            label,
            style: AppTypography.caption03.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
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
                style: AppTypography.caption02.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const Icon(
          Icons.check_circle_rounded,
          color: Color(0xFF34C759),
          size: 21,
        ),
      ],
    );
  }
}
