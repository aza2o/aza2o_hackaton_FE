import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class QuickAdviceResultScreen extends StatelessWidget {
  const QuickAdviceResultScreen({
    super.key,
    required this.userState,
    required this.aiAnalysis,
    required this.nightShiftCount,
  });

  final String userState;
  final String aiAnalysis;
  final int nightShiftCount;

  bool get _hasSkinConcern =>
      userState.contains('피부') ||
      userState.contains('트러블') ||
      userState.contains('귀') ||
      userState.contains('턱');

  String get _likelyCause => _hasSkinConcern
      ? '교대 근무 전후의 수면 부족과 취침 시각 변동으로 회복이 느려진 상태에서, '
          '마스크·베개·손의 마찰이 귀와 턱 주변 자극을 반복시켰을 가능성이 높아요.'
      : '최근 교대 근무로 취침 시각이 흔들리고 필요 수면보다 짧게 자면서, '
          '수면 압력은 높지만 원하는 시간에 잠들지 못하는 패턴일 가능성이 높아요.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 맞춤 조언'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.primary500.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('오늘 입력한 상태', style: AppTypography.caption02),
                  const SizedBox(height: 6),
                  Text(userState, style: AppTypography.subtitle03),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            _ResultSection(
              number: '01',
              title: '가능성이 높은 원인',
              child: Text(
                _likelyCause,
                style: AppTypography.body02
                    .copyWith(color: AppColors.textSecondary, height: 1.55),
              ),
            ),
            _ResultSection(
              number: '02',
              title: '이렇게 판단했어요',
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _EvidenceChip('앞으로 2주 나이트 $nightShiftCount회'),
                  const _EvidenceChip('최근 평균 수면 부족 1시간 34분'),
                  const _EvidenceChip('근무별 취침 시각 변동'),
                  _EvidenceChip('오늘 호소: $userState'),
                ],
              ),
            ),
            _ResultSection(
              number: '03',
              title: 'AI 패턴 분석',
              child: Text(
                aiAnalysis,
                style: AppTypography.body02
                    .copyWith(color: AppColors.textSecondary, height: 1.55),
              ),
            ),
            _ResultSection(
              number: '04',
              title: '오늘의 해결 행동',
              child: Column(
                children: [
                  _ActionRow(
                    time: '지금',
                    text: _hasSkinConcern
                        ? '손과 휴대폰을 닦고 귀·턱에 닿는 베개 커버를 교체해요.'
                        : '카페인을 멈추고 20분 동안 조명을 한 단계 낮춰요.',
                  ),
                  const _ActionRow(
                    time: '취침 전',
                    text: '목표 취침 40분 전부터 밝은 빛을 피하고 루틴을 최소화해요.',
                  ),
                  const _ActionRow(
                    time: '3일간',
                    text: '같은 위치의 증상과 수면 시간을 함께 기록해 반복 패턴을 확인해요.',
                  ),
                ],
              ),
            ),
            if (_hasSkinConcern) ...[
              Text('이 루틴에 맞는 AAC 연결', style: AppTypography.subtitle03),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.gray50,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.gray100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AAC 진정·장벽 보습 제품군', style: AppTypography.subtitle04),
                    const SizedBox(height: 6),
                    Text(
                      '순한 클렌저와 저자극 보습 제품만 사용해 루틴 단계를 줄여보세요.',
                      style: AppTypography.caption01
                          .copyWith(color: AppColors.textSecondary, height: 1.45),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      height: 190,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: const [
                          _DemoProductCard(
                            icon: Icons.water_drop_outlined,
                            type: '클렌저',
                            name: 'Calm Wash',
                            description: '자극을 줄인 약산성 세안',
                            color: Color(0xFFDDEEFF),
                          ),
                          _DemoProductCard(
                            icon: Icons.spa_outlined,
                            type: '진정 미스트',
                            name: 'Reset Mist',
                            description: '마찰 후 열감을 빠르게 진정',
                            color: Color(0xFFE4F2E8),
                          ),
                          _DemoProductCard(
                            icon: Icons.science_outlined,
                            type: '장벽 세럼',
                            name: 'Barrier Drop',
                            description: '건조해진 장벽을 집중 보습',
                            color: Color(0xFFFFE7D7),
                          ),
                          _DemoProductCard(
                            icon: Icons.bubble_chart_outlined,
                            type: '회복 크림',
                            name: 'Night Shield',
                            description: '수면 전 수분 증발을 방지',
                            color: Color(0xFFE8E4F5),
                          ),
                          _DemoProductCard(
                            icon: Icons.wb_sunny_outlined,
                            type: '선케어',
                            name: 'SleepReady UV',
                            description: '퇴근길 빛과 자외선을 함께 차단',
                            color: Color(0xFFFFF0C8),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (context) => Padding(
                          padding: const EdgeInsets.all(AppSpacing.xxl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('추천 사용 순서', style: AppTypography.subtitle03),
                              const SizedBox(height: AppSpacing.lg),
                              const _ActionRow(
                                time: '취침 전',
                                text: '순한 클렌저로 30초 세안 → 진정 보습제를 얇게 바르기',
                              ),
                              const _ActionRow(
                                time: '기상 후',
                                text: '물 세안 → 보습 → 자외선 차단제로 마무리하기',
                              ),
                            ],
                          ),
                        ),
                      ),
                      child: const Text('제품 사용 루틴 보기'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('홈으로 돌아가기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.number, required this.title, required this.child});
  final String number;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(number, style: AppTypography.caption02.copyWith(color: AppColors.primary500)),
          const SizedBox(height: 4),
          Text(title, style: AppTypography.subtitle03),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _EvidenceChip extends StatelessWidget {
  const _EvidenceChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: AppTypography.caption02),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.time, required this.text});
  final String time;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(time, style: AppTypography.subtitle04),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTypography.body02
                  .copyWith(color: AppColors.textSecondary, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoProductCard extends StatelessWidget {
  const _DemoProductCard({
    required this.icon,
    required this.type,
    required this.name,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String type;
  final String name;
  final String description;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 142,
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.grayWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 68,
            width: double.infinity,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                Center(child: Icon(icon, size: 34, color: AppColors.gray700)),
                Positioned(
                  top: 7,
                  right: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.grayWhite.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('DEMO', style: AppTypography.caption03),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(type, style: AppTypography.caption03.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: 2),
          Text(name, style: AppTypography.subtitle04, maxLines: 1),
          const SizedBox(height: 3),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption03.copyWith(color: AppColors.textSecondary, height: 1.3),
          ),
        ],
      ),
    );
  }
}
