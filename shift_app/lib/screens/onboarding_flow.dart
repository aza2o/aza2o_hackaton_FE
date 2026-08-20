import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shift_circadian_engine/roster/constants.dart' show ShiftType;
import '../health/health_signal_source.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'permission_screen.dart';

/// 온보딩 (`SHIFT_개발기획서.md` §5-1). Figma 시안이 없어 텍스트 스펙 기준
/// 으로 직접 구현: 근무 시각 → 조명 환경 → 크로노타입 → 카페인 습관 →
/// 캘리브레이션 진행도. 근무 시각은 하드코딩 금지 원칙(§2)에 따라 항상
/// 사용자 입력값으로 시작한다(기본값은 문헌상 흔한 패턴만 프리필).
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, this.healthSource});

  // 테스트에서 실기기 플랫폼 채널 대신 DemoHealthSource를 주입하기 위한 훅.
  // null이면 플랫폼에 맞는 실제 어댑터를 쓴다.
  final HealthSignalSource? healthSource;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _controller = PageController();
  int _step = 0;
  static const _totalSteps = 4;

  // 온보딩에서 수집하는 값들 (UserProfile에 대응 — logic/constants.py 참고)
  final Map<ShiftType, (TimeOfDay, TimeOfDay)> _shiftTimings = {
    ShiftType.day: (const TimeOfDay(hour: 7, minute: 0), const TimeOfDay(hour: 15, minute: 0)),
    ShiftType.evening: (const TimeOfDay(hour: 15, minute: 0), const TimeOfDay(hour: 23, minute: 0)),
    ShiftType.night: (const TimeOfDay(hour: 23, minute: 0), const TimeOfDay(hour: 7, minute: 0)),
  };
  String _workplaceLighting = 'normal'; // bright | normal | dim
  String _bedroomLighting = 'curtain'; // blackout | curtain | none
  String _chronotype = 'neutral'; // morning | neutral | evening
  TimeOfDay _caffeineCutoff = const TimeOfDay(hour: 14, minute: 0);

  // 헬스 연동 체크(§4단계에 병합, 로드맵 "온보딩 — 권한 요청 직후 7일치
  // 조회 → 비면 안내 화면 분기"). 플랫폼별 실기기 어댑터 사용.
  late final HealthSignalSource _healthSource = widget.healthSource ??
      (defaultTargetPlatform == TargetPlatform.android ? AndroidHealthSource() : IosHealthSource());
  bool _healthCheckLoading = false;
  List<HealthSleepSession>? _healthSessions; // null = 아직 확인 안 함

  Future<void> _checkHealthData() async {
    setState(() => _healthCheckLoading = true);
    List<HealthSleepSession> sessions;
    try {
      await _healthSource.requestAuthorization();
      final now = DateTime.now();
      sessions = await _healthSource.sleepSessions(
        DateRange(now.subtract(const Duration(days: 7)), now),
      );
    } catch (_) {
      // 권한 거부, Health Connect 미설치 등도 "데이터 없음"과 동일하게
      // 처리한다 — iOS는 애초에 원인을 구분해서 알려주지 않는다(§6-3-c).
      sessions = const [];
    }
    if (!mounted) return;
    setState(() {
      _healthSessions = sessions;
      _healthCheckLoading = false;
    });
  }

  void _next() {
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
      _controller.nextPage(
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      AppState.instance.saveOnboarding(
        shiftTimings: _shiftTimings,
        workplaceLighting: _workplaceLighting,
        bedroomLighting: _bedroomLighting,
        chronotype: _chronotype,
        caffeineCutoff: _caffeineCutoff,
      );
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PermissionScreen()));
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
      _controller.previousPage(
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _step > 0
            ? IconButton(icon: const Icon(Icons.chevron_left), onPressed: _back)
            : null,
        title: LinearProgressIndicator(
          value: (_step + 1) / _totalSteps,
          backgroundColor: AppColors.gray100,
          color: AppColors.primary500,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _ShiftTimingStep(
                    timings: _shiftTimings,
                    onChanged: (shift, start, end) =>
                        setState(() => _shiftTimings[shift] = (start, end)),
                  ),
                  _LightingStep(
                    workplace: _workplaceLighting,
                    bedroom: _bedroomLighting,
                    onWorkplaceChanged: (v) => setState(() => _workplaceLighting = v),
                    onBedroomChanged: (v) => setState(() => _bedroomLighting = v),
                  ),
                  _ChronotypeCaffeineStep(
                    chronotype: _chronotype,
                    caffeineCutoff: _caffeineCutoff,
                    onChronotypeChanged: (v) => setState(() => _chronotype = v),
                    onCaffeineChanged: (v) => setState(() => _caffeineCutoff = v),
                  ),
                  _CalibrationStep(
                    healthChecked: _healthSessions != null,
                    healthLoading: _healthCheckLoading,
                    healthSessionCount: _healthSessions?.length ?? 0,
                    onCheckHealth: _checkHealthData,
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _next,
                  child: Text(_step == _totalSteps - 1 ? '시작하기' : '다음',
                      style: AppTypography.button03),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(title, style: AppTypography.heading04),
        const SizedBox(height: AppSpacing.sm),
        Text(subtitle, style: AppTypography.body02.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.xxl),
        child,
      ],
    );
  }
}

const _shiftLabels = {ShiftType.day: 'Day', ShiftType.evening: 'Evening', ShiftType.night: 'Night'};

// TimeOfDay.format(context)는 로케일에 따라 "7:00 AM"처럼 길어져 좁은
// 화면에서 오버플로우가 난다. 앱의 나머지 시각 표기가 전부 24시간제라
// (예: 홈 화면 "07:00 근무") 여기도 로케일 무관하게 24시간제로 고정한다.
String _fmt24(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Step 1 — 근무 시각. 하드코딩 금지: 병원마다 D/E/N 시각이 다르므로
/// 사용자 정의가 기본이다. 시작·종료 각각 탭하면 시간 선택기가 뜬다.
class _ShiftTimingStep extends StatelessWidget {
  const _ShiftTimingStep({required this.timings, required this.onChanged});

  final Map<ShiftType, (TimeOfDay, TimeOfDay)> timings;
  final void Function(ShiftType shift, TimeOfDay start, TimeOfDay end) onChanged;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: '근무 시각을 알려주세요',
      subtitle: '병원마다 달라서, 직접 입력한 시각을 기준으로 계산해요',
      child: Column(
        children: [
          for (final shift in [ShiftType.day, ShiftType.evening, ShiftType.night]) ...[
            _ShiftTimingRow(
              label: _shiftLabels[shift]!,
              start: timings[shift]!.$1,
              end: timings[shift]!.$2,
              onStartTap: () async {
                final picked =
                    await showTimePicker(context: context, initialTime: timings[shift]!.$1);
                if (picked != null) onChanged(shift, picked, timings[shift]!.$2);
              },
              onEndTap: () async {
                final picked =
                    await showTimePicker(context: context, initialTime: timings[shift]!.$2);
                if (picked != null) onChanged(shift, timings[shift]!.$1, picked);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _ShiftTimingRow extends StatelessWidget {
  const _ShiftTimingRow({
    required this.label,
    required this.start,
    required this.end,
    required this.onStartTap,
    required this.onEndTap,
  });
  final String label;
  final TimeOfDay start;
  final TimeOfDay end;
  final VoidCallback onStartTap;
  final VoidCallback onEndTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.grayWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gray100),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.subtitle04),
          Row(
            children: [
              GestureDetector(
                onTap: onStartTap,
                child: Text(_fmt24(start),
                    style: AppTypography.body02.copyWith(color: AppColors.primary900)),
              ),
              Text(' – ', style: AppTypography.body02.copyWith(color: AppColors.textSecondary)),
              GestureDetector(
                onTap: onEndTap,
                child: Text(_fmt24(end),
                    style: AppTypography.body02.copyWith(color: AppColors.primary900)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Step 2 — 조명 환경 3지선다 (근무지 조도, 침실 암막 여부).
class _LightingStep extends StatelessWidget {
  const _LightingStep({
    required this.workplace,
    required this.bedroom,
    required this.onWorkplaceChanged,
    required this.onBedroomChanged,
  });

  final String workplace;
  final String bedroom;
  final ValueChanged<String> onWorkplaceChanged;
  final ValueChanged<String> onBedroomChanged;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: '조명 환경을 알려주세요',
      subtitle: '손목 센서보다 정확한 광 스케줄 계산에 쓰여요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('근무지 밝기', style: AppTypography.subtitle04),
          const SizedBox(height: AppSpacing.sm),
          _ChoiceRow(
            options: const {'bright': '밝음', 'normal': '보통', 'dim': '어두움'},
            value: workplace,
            onChanged: onWorkplaceChanged,
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('침실 암막', style: AppTypography.subtitle04),
          const SizedBox(height: AppSpacing.sm),
          _ChoiceRow(
            options: const {'blackout': '암막 있음', 'curtain': '일반 커튼', 'none': '없음'},
            value: bedroom,
            onChanged: onBedroomChanged,
          ),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.options, required this.value, required this.onChanged});
  final Map<String, String> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.entries.map((e) {
        final selected = e.key == value;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: GestureDetector(
              onTap: () => onChanged(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary50 : AppColors.grayWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: selected ? AppColors.primary500 : AppColors.gray100,
                      width: selected ? 1.5 : 1),
                ),
                alignment: Alignment.center,
                child: Text(e.value,
                    style: AppTypography.caption01.copyWith(
                        color: selected ? AppColors.primary900 : AppColors.textSecondary,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Step 3 — 크로노타입 축약형 설문 + 카페인 습관.
class _ChronotypeCaffeineStep extends StatelessWidget {
  const _ChronotypeCaffeineStep({
    required this.chronotype,
    required this.caffeineCutoff,
    required this.onChronotypeChanged,
    required this.onCaffeineChanged,
  });

  final String chronotype;
  final TimeOfDay caffeineCutoff;
  final ValueChanged<String> onChronotypeChanged;
  final ValueChanged<TimeOfDay> onCaffeineChanged;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: '평소 스타일도 알려주세요',
      subtitle: '몇 가지만 더 여쭤볼게요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('쉬는 날 자연스러운 기상 시각은?', style: AppTypography.subtitle04),
          const SizedBox(height: AppSpacing.sm),
          _ChoiceRow(
            options: const {'morning': '이른 편', 'neutral': '보통', 'evening': '늦은 편'},
            value: chronotype,
            onChanged: onChronotypeChanged,
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('카페인은 보통 몇 시까지 마시나요?', style: AppTypography.subtitle04),
          const SizedBox(height: AppSpacing.sm),
          Builder(builder: (context) {
            return OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.gray200),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final picked = await showTimePicker(
                    context: context, initialTime: caffeineCutoff);
                if (picked != null) onCaffeineChanged(picked);
              },
              child: Text(caffeineCutoff.format(context), style: AppTypography.body02),
            );
          }),
        ],
      ),
    );
  }
}

/// Step 4 — 캘리브레이션 진행도 노출(리텐션 장치, §5-1) + 헬스 연동 체크
/// (로드맵 "온보딩 — 권한 요청 직후 7일치 조회 → 비면 안내 화면 분기"를
/// 별도 화면이 아니라 이 단계에 병합하기로 함).
class _CalibrationStep extends StatelessWidget {
  const _CalibrationStep({
    required this.healthChecked,
    required this.healthLoading,
    required this.healthSessionCount,
    required this.onCheckHealth,
  });

  final bool healthChecked;
  final bool healthLoading;
  final int healthSessionCount;
  final VoidCallback onCheckHealth;

  bool get _hasHealthData => healthChecked && healthSessionCount > 0;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: '첫 주는 이렇게 진행돼요',
      subtitle: '문헌 상수 기반으로 시작하고, 데이터가 쌓이면 점점 개인화돼요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HealthCheckCard(
            checked: healthChecked,
            loading: healthLoading,
            hasData: _hasHealthData,
            sessionCount: healthSessionCount,
            onCheck: onCheckHealth,
          ),
          const SizedBox(height: AppSpacing.xxl),
          for (final (label, done) in [
            ('로스터 입력', true),
            ('첫 넛지 발송', false),
            ('웨어러블 연동(선택)', _hasHealthData),
            ('개인화 위상 추정 시작', false),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                children: [
                  Icon(
                    done ? Icons.check_circle : Icons.circle_outlined,
                    color: done ? AppColors.success01 : AppColors.gray300,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(label, style: AppTypography.body02),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 권한 요청(스텁) → 최근 7일 수면 세션 조회 → 있음/없음 분기를 카드 하나로.
class _HealthCheckCard extends StatelessWidget {
  const _HealthCheckCard({
    required this.checked,
    required this.loading,
    required this.hasData,
    required this.sessionCount,
    required this.onCheck,
  });

  final bool checked;
  final bool loading;
  final bool hasData;
  final int sessionCount;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Apple Health 연동 (선택)', style: AppTypography.subtitle04),
          const SizedBox(height: 4),
          Text(
            checked
                ? (hasData
                    ? '최근 7일 중 $sessionCount건의 수면 기록을 찾았어요. 이 데이터로 더 정확하게 계산할게요.'
                    : '최근 7일치 수면 기록이 없어요 — 괜찮아요. 첫 주는 문헌 기반 기본값으로 시작하고, '
                        '기록이 쌓이면 자동으로 반영돼요.')
                : '연동하면 최근 수면 데이터를 확인해서 첫 주부터 더 정확하게 계산할 수 있어요. 나중에 설정에서도 할 수 있어요.',
            style: AppTypography.caption01.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.primary500),
              foregroundColor: AppColors.primary900,
            ),
            onPressed: loading ? null : onCheck,
            child: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(checked ? '다시 확인하기' : '지금 확인하기', style: AppTypography.caption02),
          ),
        ],
      ),
    );
  }
}
