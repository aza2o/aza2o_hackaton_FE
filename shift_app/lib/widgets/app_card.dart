import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Figma "glass" 카드의 근사치. 네이티브 GLASS 이펙트는 Flutter에 대응
/// API가 없어서, 옅은 그림자 + 흰 배경으로 대체했다
/// (`SHIFT_프론트엔드_기획서.md` §3-3 참고 — 실기기에서 톤 튜닝 필요).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.grayWhite,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
