/// 근무표 + 실측 수면 → 넛지 스케줄. `룰엔진_규칙_v2.md` §2~§5의 1:1 구현.
///
/// `circadian_model.dart`(4모델 DLMO 엔진)와 `roster/light_schedule.dart`
/// (로스터→광스케줄)에 이어지는 세 번째 계산층이지만, 이 둘의 출력을 입력으로
/// 받지는 않는다 — 로스터 자체와 워치 실측 수면만으로 넛지를 뽑아낸다.
/// "DLMO 이동량"은 여기서는 ODE 적분이 아니라 "실측 위상(§2-②) vs 근무표
/// 기반 목표 위상(§2-①)의 격차를 하루 최대 60분으로 clamp"(§2-③)하는
/// 방식으로 근사한다. 4모델로 DLMO를 직접 추정해 개입 전후 반사실
/// 차이를 재는 처치효과 랭킹(`logic/nudge.py`)은 의도적으로 분리된
/// 별도 층이며 Python 백엔드 전용이다(그 파일 docstring 참고).
///
/// 절대시간(h) 관례는 `roster/light_schedule.dart`와 동일하게 로스터
/// 시작일 00:00을 0으로 둔다.
library nudge_engine;

import 'circular_time.dart';
import 'nudge_constants.dart';
import '../roster/constants.dart';

/// 실측(워치) 수면 세션. 절대시간(h), 로스터 시작일 00:00 기준.
/// `roster/light_schedule.dart`의 `SleepWindow`는 광 스케줄 생성을 위해
/// "예상"한 수면이고, 이건 그 반대로 실제 관측값이다 — 섞어 쓰지 말 것.
class SleepSession {
  const SleepSession(this.startAt, this.endAt);
  final double startAt;
  final double endAt;

  double get midpoint => (startAt + endAt) / 2.0;
  double get durationMin => (endAt - startAt) * 60.0;
}

class Nudge {
  const Nudge(this.kind, this.at);
  final NudgeKind kind;
  final double at; // 절대시간(h)
}

class SleepPlan {
  const SleepPlan({
    required this.type,
    this.targetBedtime,
    this.targetWake,
    this.napStart,
    this.napEnd,
  });
  final PlanType type;
  final double? targetBedtime;
  final double? targetWake;
  final double? napStart;
  final double? napEnd;
}

class NudgePlan {
  const NudgePlan(this.sleep, this.nudges);
  final SleepPlan sleep;
  final List<Nudge> nudges;
}

double _clamp(double x, double lo, double hi) => x < lo ? lo : (x > hi ? hi : x);

double _shiftStartAbs(int dayIndex, ShiftType s, Map<ShiftType, ShiftTiming> t) =>
    dayIndex * 24.0 + t[s]!.start;

double _shiftEndAbs(int dayIndex, ShiftType s, Map<ShiftType, ShiftTiming> t) =>
    _shiftStartAbs(dayIndex, s, t) + t[s]!.duration;

/// 최근 [windowDays]일 실측 수면 대비 부족분(분).
///
/// 문서 §1의 `defaultNeedSleepMin` 설명("7시간은 목표치이자 부채 계산
/// 기준")을 근거로 한 구현이며, 명시적 공식은 문서에 없다 — 하루 목표
/// 수면량 × 창 일수에서 실측 수면 합을 뺀 값을 부채로 삼는다.
double computeSleepDebtMin(
  List<SleepSession> sessions,
  double now, {
  int windowDays = debtWindowDays,
  double needSleepMin = defaultNeedSleepMin,
}) {
  final windowStart = now - windowDays * 24.0;
  var actualMin = 0.0;
  for (final s in sessions) {
    final start = s.startAt < windowStart ? windowStart : s.startAt;
    final end = s.endAt > now ? now : s.endAt;
    if (end > start) actualMin += (end - start) * 60.0;
  }
  final debt = windowDays * needSleepMin - actualMin;
  return debt > 0.0 ? debt : 0.0;
}

/// §2-① 이상적 취침·기상(절대시간, h).
///
/// 근무표에서 역산하는 것이 핵심이다 — 워치 실측(§2-②)과는 다른 입력.
/// 근무 유형별로 앵커가 다르다:
///   - Night: 퇴근 후 주간수면이므로 근무 **종료**시각 + 통근 + 준비.
///   - Day/Evening: 근무 전 수면이므로 근무 **시작**시각에서 준비시간을
///     뺀 기상시각을 먼저 구하고, 거기서 needSleepMin을 빼 취침을 역산.
///     (문서 원문은 종료시각 기준 단일 공식이지만, Day/Evening까지 그걸
///     적용하면 §2-③의 순환 최단거리 계산에서 방향이 사실상 랜덤해진다
///     — 대신 이 앵커를 씀.)
/// 내일·오늘 둘 다 근무가 없으면(OFF) 최근 [phaseWindowDays]일 실측
/// 평균 취침시각으로 대체한다.
({double bedtime, double wake}) idealSleepTimes({
  required List<ShiftType> roster,
  required int todayIndex,
  required Map<ShiftType, ShiftTiming> shiftTimings,
  required double commuteMinutes,
  required List<SleepSession> recentSessions,
  double needSleepMin = defaultNeedSleepMin,
}) {
  ShiftType? refShift;
  int? refIndex;
  final tomorrowIndex = todayIndex + 1;
  if (tomorrowIndex < roster.length && roster[tomorrowIndex] != ShiftType.off) {
    refShift = roster[tomorrowIndex];
    refIndex = tomorrowIndex;
  } else if (todayIndex < roster.length && roster[todayIndex] != ShiftType.off) {
    refShift = roster[todayIndex];
    refIndex = todayIndex;
  }

  if (refShift == null) {
    final todayStart = todayIndex * 24.0;
    final windowStart = todayStart - phaseWindowDays * 24.0;
    final bedtimes = recentSessions
        .where((s) => s.startAt >= windowStart && s.startAt < todayStart)
        .map((s) => s.startAt % 24.0)
        .toList();
    if (bedtimes.isEmpty) {
      throw ArgumentError('양쪽 다 OFF인데 폴백에 쓸 최근 취침 기록이 없음');
    }
    final bedtime = todayStart + circularMeanHours(bedtimes);
    return (bedtime: bedtime, wake: bedtime + needSleepMin / 60.0);
  }

  if (refShift == ShiftType.night) {
    final end = _shiftEndAbs(refIndex!, refShift, shiftTimings);
    final bedtime = end + commuteMinutes / 60.0 + prepMinutes / 60.0;
    return (bedtime: bedtime, wake: bedtime + needSleepMin / 60.0);
  }

  final start = _shiftStartAbs(refIndex!, refShift, shiftTimings);
  final wake = start - prepMinutes / 60.0;
  return (bedtime: wake - needSleepMin / 60.0, wake: wake);
}

/// §2-② 현재 리듬 위상 — 최근 [phaseWindowDays]일 수면 세션 중간점의
/// 순환평균. 절대시간으로 반환하되, [now]에 가장 가까운 날짜에 결부시킨다
/// (§2-③에서 그대로 이동량을 더해 "오늘 목표 중간점"을 만들기 위함).
///
/// 날짜 앵커를 임의의 "오늘" 인덱스에 고정하면 안 된다 — 예를 들어 위상
/// 시각(순환평균)이 새벽 1시 반이고 지금이 오후라면, "오늘 새벽"에 고정된
/// 결과는 이미 지난 시각이 되어 §2-③에서 나온 목표 취침이 항상 과거로
/// 계산되고 §5에서 오늘 취침 관련 넛지가 전부 걸러지는 문제가 생긴다.
/// [now] 기준 어제/오늘/내일 중 가장 가까운 발생 시점에 앵커링해야
/// "지금과 가장 가까운 리듬 상태"라는 의미가 유지된다.
double currentPhase({
  required List<SleepSession> recentSessions,
  required double now,
}) {
  final windowStart = now - phaseWindowDays * 24.0;
  final midpoints = recentSessions
      .where((s) => s.midpoint >= windowStart && s.midpoint < now)
      .map((s) => s.midpoint % 24.0)
      .toList();
  if (midpoints.isEmpty) {
    throw ArgumentError('현재 위상 계산에 쓸 최근 수면 세션이 없음');
  }
  final clock = circularMeanHours(midpoints);
  final base = (now / 24.0).floor() * 24.0; // now가 속한 날의 00:00
  final candidates = [base - 24.0 + clock, base + clock, base + 24.0 + clock];
  candidates.sort((a, b) => (a - now).abs().compareTo((b - now).abs()));
  return candidates.first;
}

/// §2-③ 단계적 이동 — 오늘 목표 취침·기상(절대시간, h).
/// 격차 계산은 반드시 순환 최단거리를 써야 한다(문서 경고 참고).
({double bedtime, double wake}) stepTowardTarget({
  required double idealBedtime,
  required double currentPhaseAbs,
  double needSleepMin = defaultNeedSleepMin,
}) {
  final idealMidpoint = idealBedtime + needSleepMin / 60.0 / 2.0;
  final gapHours = circularShortestDiffHours(
    currentPhaseAbs % 24.0,
    idealMidpoint % 24.0,
  );
  final shiftMin = _clamp(gapHours * 60.0, -maxShiftPerDayMin, maxShiftPerDayMin);
  final todayMidpoint = currentPhaseAbs + shiftMin / 60.0;
  final bedtime = todayMidpoint - needSleepMin / 60.0 / 2.0;
  return (bedtime: bedtime, wake: bedtime + needSleepMin / 60.0);
}

/// §2~§5 전체 파이프라인. 오늘의 SleepPlan과 우선순위 적용된(최대 3개,
/// 과거 시각 제외) 넛지 목록을 반환한다.
NudgePlan buildNudgePlan({
  required List<ShiftType> roster,
  required int todayIndex,
  required double now,
  required List<SleepSession> recentSessions,
  UserProfile? profile,
  double needSleepMin = defaultNeedSleepMin,
}) {
  final p = profile ?? UserProfile();
  final t = p.shiftTimings;
  final todayShift = todayIndex < roster.length ? roster[todayIndex] : ShiftType.off;
  final isEveningOrNight = todayShift == ShiftType.evening || todayShift == ShiftType.night;

  var wantsNap = false;
  if (isEveningOrNight) {
    final shiftStart = _shiftStartAbs(todayIndex, todayShift, t);
    wantsNap = (shiftStart - now) * 60.0 >= napBeforeShiftMinMin;
  }

  final candidates = <Nudge>[];
  SleepPlan sleepPlan;

  if (wantsNap) {
    final shiftStart = _shiftStartAbs(todayIndex, todayShift, t);
    final debt = computeSleepDebtMin(recentSessions, now, needSleepMin: needSleepMin);
    final napMinutes = debt >= napLongDebtThresholdMin ? napLongMin : napShortMin;
    final napStart = shiftStart - napBeforeShiftMinMin / 60.0 - napMinutes / 60.0;
    final napEnd = napStart + napMinutes / 60.0;

    sleepPlan = SleepPlan(type: PlanType.nap, napStart: napStart, napEnd: napEnd);
    candidates.add(Nudge(NudgeKind.napStart, napStart));
    candidates.add(Nudge(NudgeKind.caffeineCutoff, napStart - caffeineCutoffBeforeMin / 60.0));
    candidates.add(Nudge(NudgeKind.lightExposure, napEnd + 15.0 / 60.0));
  } else {
    final ideal = idealSleepTimes(
      roster: roster,
      todayIndex: todayIndex,
      shiftTimings: t,
      commuteMinutes: p.commuteMinutes,
      recentSessions: recentSessions,
      needSleepMin: needSleepMin,
    );
    final phase = currentPhase(recentSessions: recentSessions, now: now);
    final target = stepTowardTarget(
      idealBedtime: ideal.bedtime,
      currentPhaseAbs: phase,
      needSleepMin: needSleepMin,
    );

    sleepPlan = SleepPlan(
      type: PlanType.bedtime,
      targetBedtime: target.bedtime,
      targetWake: target.wake,
    );
    candidates.add(Nudge(NudgeKind.caffeineCutoff, target.bedtime - caffeineCutoffBeforeMin / 60.0));
    candidates.add(Nudge(NudgeKind.lightBlock, target.bedtime - lightBlockBeforeMin / 60.0));
    candidates.add(Nudge(NudgeKind.windDown, target.bedtime - windDownBeforeMin / 60.0));
    candidates.add(Nudge(NudgeKind.lightExposure, target.wake + lightExposureAfterMin / 60.0));

    if (todayShift == ShiftType.night) {
      final shiftStart = _shiftStartAbs(todayIndex, todayShift, t);
      final shiftEnd = _shiftEndAbs(todayIndex, todayShift, t);
      candidates.add(Nudge(NudgeKind.brightLightAtWork, shiftStart + 30.0 / 60.0));
      candidates.add(Nudge(NudgeKind.sunglassesCommute, shiftEnd - 15.0 / 60.0));
    }
  }

  // §5 우선순위 — 위에서부터 채워 3개가 되면 중단, 과거 시각은 건너뜀.
  final priority = wantsNap
      ? const [NudgeKind.napStart, NudgeKind.caffeineCutoff, NudgeKind.lightExposure]
      : (todayShift == ShiftType.night
          ? const [
              NudgeKind.sunglassesCommute,
              NudgeKind.caffeineCutoff,
              NudgeKind.lightBlock,
              NudgeKind.brightLightAtWork,
              NudgeKind.windDown,
              NudgeKind.lightExposure,
            ]
          : const [
              NudgeKind.caffeineCutoff,
              NudgeKind.lightBlock,
              NudgeKind.windDown,
              NudgeKind.lightExposure,
            ]);

  final byKind = {for (final n in candidates) n.kind: n};
  final selected = <Nudge>[];
  for (final kind in priority) {
    final n = byKind[kind];
    if (n != null && n.at >= now) {
      selected.add(n);
      if (selected.length == 3) break;
    }
  }
  selected.sort((a, b) => a.at.compareTo(b.at));

  return NudgePlan(sleepPlan, selected);
}
