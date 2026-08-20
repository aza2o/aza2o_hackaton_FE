import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'home_screen.dart';
import 'roster_calendar_screen.dart';

/// 하단 탭바(홈/근무 달력). 설정은 탭이 아니라 홈 우측 상단 아이콘으로
/// 들어간다 — 매일 여는 화면이 아니라서 탭 한 칸을 차지할 이유가 없고,
/// 그 자리를 이 앱의 핵심 데이터인 근무 달력에 줬다. AI 리포트·피부
/// 루틴도 탭이 아니라 홈 하단 카드에서 진입한다.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    RosterCalendarScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            height: 62,
            decoration: BoxDecoration(
              color: AppColors.grayWhite,
              borderRadius: BorderRadius.circular(31),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TabItem(
                    label: '홈',
                    icon: Icons.home_rounded,
                    selected: _index == 0,
                    onTap: () => setState(() => _index = 0),
                  ),
                ),
                Expanded(
                  child: _TabItem(
                    label: '근무 달력',
                    icon: Icons.calendar_month_rounded,
                    selected: _index == 1,
                    onTap: () => setState(() => _index = 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: selected ? AppColors.gray100 : Colors.transparent,
          borderRadius: BorderRadius.circular(27),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 22,
                color: selected ? AppColors.primary500 : AppColors.textPlaceholder),
            const SizedBox(height: 2),
            Text(label,
                style: AppTypography.caption03.copyWith(
                  color: selected ? AppColors.textPrimary : AppColors.textPlaceholder,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                )),
          ],
        ),
      ),
    );
  }
}
