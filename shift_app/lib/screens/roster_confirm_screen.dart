import 'package:flutter/material.dart';
import 'package:shift_circadian_engine/roster/constants.dart' show shiftTypeFromCode;
import '../engine/nudge_service.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/roster_calendar.dart';
import 'root_shell.dart';

/// 로스터 확인 (Figma 신규 파일 `12:2`). 파싱 결과를 캘린더로 보여주고
/// 셀을 눌러 수정할 수 있어야 한다(`SHIFT_개발기획서.md` §5-2, 자동화보다
/// 정확성 우선) — 셀 탭 시 순환 편집(D→E→N→O). `POST /roster/parse`가
/// 못 알아본 코드는 전부 'O'로 들어와 있을 수 있으니, 이 화면의 편집
/// 기능이 파서의 약점을 흡수한다(`roster_parse.py` 모듈 docstring 참고).
///
/// [initialShifts]/[year]/[month]가 없으면(예: 위젯 테스트에서 단독으로
/// 열 때, 또는 로스터 입력의 "2차: 패턴 선택" 폴백 경로) 기존 8월 데모
/// 패턴을 그대로 보여준다.
class RosterConfirmScreen extends StatefulWidget {
  const RosterConfirmScreen({
    super.key,
    this.year,
    this.month,
    this.initialShifts,
    this.unmappedCodes = const [],
    this.userName = '게스트',
  });

  final int? year;
  final int? month;
  final Map<int, String>? initialShifts; // day(1-based) -> D/E/N/O
  final List<String> unmappedCodes;
  final String userName;

  @override
  State<RosterConfirmScreen> createState() => _RosterConfirmScreenState();
}

class _RosterConfirmScreenState extends State<RosterConfirmScreen> {
  static const _demoPattern = ['D', 'D', 'E', 'E', 'N', 'N', 'O'];

  bool get _isDemo => widget.initialShifts == null;

  // 데모(2차: 패턴 선택) 경로도 더 이상 "8월 1일이 토요일"로 고정하지
  // 않는다 — AppState.saveRoster()가 이 연·월을 실제 날짜 앵커로 저장하고
  // 홈 화면이 그걸로 "오늘"을 찾기 때문에, 여기서 실제 오늘이 속한 달을
  // 안 쓰면 데모 경로로 들어온 로스터는 홈과 영영 안 맞게 된다.
  late final int _year = widget.year ?? DateTime.now().year;
  late final int _month = widget.month ?? DateTime.now().month;
  late final int _startOffset = (DateTime(_year, _month, 1).weekday - 1) % 7;
  late final int _daysInMonth = DateTime(_year, _month + 1, 0).day;

  late final List<String> _shifts = _isDemo
      ? List.generate(_daysInMonth, (i) => _demoPattern[i % _demoPattern.length])
      : List.generate(_daysInMonth, (i) => widget.initialShifts![i + 1] ?? 'O');

  late final int _unmappedCodeCount =
      _isDemo ? 2 : widget.unmappedCodes.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$_year년 $_month월 근무표 확인',
          style: AppTypography.subtitle03.copyWith(color: AppColors.textPrimary),
        ),
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              '$_year년 $_month월',
              style: AppTypography.heading04,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('${widget.userName} 간호사 · 잘못된 날짜는 눌러서 수정하세요',
                style: AppTypography.body02.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.lg),
            const WeekdayHeader(),
            const SizedBox(height: AppSpacing.xs),
            CalendarGrid(
              shifts: _shifts,
              startOffset: _startOffset,
              onTapDay: (day) {
                setState(() {
                  _shifts[day] = nextShiftCode(_shifts[day]);
                });
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            const ShiftLegend(),
            if (_unmappedCodeCount > 0) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.warning03,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isDemo
                          ? '⚠️ "연차" 코드 $_unmappedCodeCount건을 찾았어요'
                          : '⚠️ "${widget.unmappedCodes.join(", ")}" 코드 $_unmappedCodeCount건을 찾았어요',
                      style: AppTypography.subtitle04,
                    ),
                    const SizedBox(height: 4),
                    Text('일단 오프(O)로 표시해뒀어요 — 날짜를 눌러 실제 근무로 바꿔주세요',
                        style: AppTypography.caption01
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary500,
                  foregroundColor: AppColors.gray900,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () async {
                  AppState.instance.saveRoster(
                    _shifts.map(shiftTypeFromCode).toList(),
                    startDate: DateTime(_year, _month, 1),
                  );
                  // 오늘·내일치 넛지를 실제 알림으로 재예약한다(§7-2).
                  // 실패해도(권한 거부 등) 다음 화면 진행을 막지 않는다.
                  await NotificationService.instance
                      .rescheduleAll(await loadUpcomingNudgeTriggers());
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const RootShell()),
                    (route) => false,
                  );
                },
                child: Text('확인하고 넛지 받기', style: AppTypography.button03),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
