// 근무표 달력 — 온보딩의 "근무표 확인"(roster_confirm_screen)과 하단 탭의
// "근무 달력"(roster_calendar_screen)이 같은 그리드를 쓴다. 색·라벨·순환
// 편집 규칙이 두 곳에서 갈라지면 같은 근무가 화면마다 다른 색으로 보이게
// 되므로 여기 한 곳에만 둔다.
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// 셀을 탭할 때 도는 순서 — D → E → N → O → D.
const shiftCycle = ['D', 'E', 'N', 'O'];

const shiftColor = {
  'D': AppColors.primary400,
  'E': AppColors.information02,
  'N': AppColors.gray800,
  'O': AppColors.gray100,
};

const shiftTextColor = {
  'D': AppColors.textPrimary,
  'E': AppColors.grayWhite,
  'N': AppColors.grayWhite,
  'O': AppColors.textTertiary,
};

const shiftLabel = {'D': '데이', 'E': '이브닝', 'N': '나이트', 'O': '오프'};

/// [code]를 순환 편집의 다음 코드로 바꾼다.
String nextShiftCode(String code) {
  final i = shiftCycle.indexOf(code);
  return shiftCycle[(i + 1) % shiftCycle.length];
}

class WeekdayHeader extends StatelessWidget {
  const WeekdayHeader({super.key});

  @override
  Widget build(BuildContext context) {
    const labels = ['월', '화', '수', '목', '금', '토', '일'];
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(
                labels[i],
                style: AppTypography.caption02.copyWith(
                  color: (i == 5 || i == 6)
                      ? AppColors.textPlaceholder
                      : AppColors.textTertiary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 한 달치 근무 그리드. [shifts]는 1일부터의 코드 목록이고 [startOffset]은
/// 1일이 월요일 기준 몇 칸 뒤인지다.
///
/// [onTapDay]가 null이면 편집 불가 상태로 그린다 — 근무표가 없는 달을
/// 볼 때처럼 "읽기만" 하는 경우에 쓴다.
/// [highlightDay]는 0-based 인덱스이며, 오늘 날짜에 테두리를 그린다.
class CalendarGrid extends StatelessWidget {
  const CalendarGrid({
    super.key,
    required this.shifts,
    required this.startOffset,
    this.onTapDay,
    this.highlightDay,
  });

  final List<String> shifts;
  final int startOffset;
  final ValueChanged<int>? onTapDay;
  final int? highlightDay;

  @override
  Widget build(BuildContext context) {
    final totalCells = startOffset + shifts.length;
    final rows = (totalCells / 7).ceil();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows * 7,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: AppSpacing.xs,
        crossAxisSpacing: AppSpacing.xs,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (context, cellIdx) {
        final day = cellIdx - startOffset;
        if (day < 0 || day >= shifts.length) return const SizedBox.shrink();
        final shift = shifts[day];
        final isMissing = shift.isEmpty;
        final isToday = day == highlightDay;
        return GestureDetector(
          onTap: onTapDay == null ? null : () => onTapDay!(day),
          child: Container(
            decoration: BoxDecoration(
              color: isMissing ? Colors.transparent : shiftColor[shift],
              borderRadius: BorderRadius.circular(10),
              border: isToday
                  ? Border.all(color: AppColors.textPrimary, width: 2)
                  : isMissing
                  ? Border.all(color: AppColors.gray100)
                  : null,
            ),
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${day + 1}',
                  style: AppTypography.caption02.copyWith(
                    color: isMissing
                        ? AppColors.textPlaceholder
                        : shiftTextColor[shift],
                  ),
                ),
                const Spacer(),
                if (!isMissing)
                  Text(
                    shift,
                    style: AppTypography.subtitle03.copyWith(
                      color: shiftTextColor[shift],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ShiftLegend extends StatelessWidget {
  const ShiftLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      children: shiftCycle.map((code) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: shiftColor[code],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$code ${shiftLabel[code]}',
              style: AppTypography.caption02.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}
