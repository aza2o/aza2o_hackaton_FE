// `shift_circadian_engine`(계산 엔진) ↔ 화면 연결부.
//
// 로스터·프로필은 `AppState`(온보딩·로스터 확인 화면이 채워 넣음)에서
// 읽는다. 아직 아무것도 안 채워졌으면(첫 실행 전, 또는 화면을 단독으로
// 여는 위젯 테스트) 데모 로스터로 대체한다 — 워치 수면 이력은 헬스 연동
// 전까지 항상 데모값을 쓴다(`docs/SHIFT_프론트엔드_구현체크리스트.md` §1).
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shift_circadian_engine/nudge/nudge_engine.dart';
import 'package:shift_circadian_engine/nudge/nudge_constants.dart';
import 'package:shift_circadian_engine/nudge/nudge_messages.dart';
import 'package:shift_circadian_engine/roster/constants.dart';

import '../state/app_state.dart';

/// 화면이 그대로 그릴 수 있게 추린 결과.
class TodayNudges {
  const TodayNudges({
    required this.isNightMood,
    required this.headerLabel,
    required this.planLabel,
    required this.summary,
    required this.actions,
  });

  final bool isNightMood;
  final String headerLabel; // 예: "오늘 23:00 나이트 근무"
  final String planLabel; // 예: "19:40 낮잠" / "23:40 취침"
  final String summary; // 최우선 넛지 문구(messages.json)
  final List<NudgeAction> actions;
}

class NudgeAction {
  const NudgeAction({
    required this.time,
    required this.label,
    required this.message,
    required this.isPast,
  });
  final String time; // 예: "22:00"
  final String label; // 예: "조명 낮추기"
  final String message;
  final bool isPast; // 계산 시점(now) 기준으로 이미 지난 시각인지 — 완료 여부와는 별개
}

const _kindLabel = {
  NudgeKind.caffeineCutoff: '카페인 중단',
  NudgeKind.lightBlock: '조명 낮추기',
  NudgeKind.lightExposure: '빛 쬐기',
  NudgeKind.windDown: '취침 준비',
  NudgeKind.napStart: '낮잠',
  NudgeKind.sunglassesCommute: '선글라스 착용',
  NudgeKind.brightLightAtWork: '밝은 빛 쬐기',
};

const _shiftLabel = {
  ShiftType.day: '데이',
  ShiftType.evening: '이브닝',
  ShiftType.night: '나이트',
  ShiftType.off: '오프',
};

String _formatClock(double absHours) {
  final h = absHours % 24.0;
  final hh = h.floor();
  final mm = ((h - hh) * 60).round();
  return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

/// 데모 수면 이력(워치 데이터 목업). 교대근무자의 취침 이동과 수면 길이
/// 변동을 재현하면서 currentPhase 5일 창과 sleepDebtMin 7일 창을 덮는다.
///
/// 반드시 [todayIndex] 기준으로 생성해야 한다 — 로스터 0일차 기준 고정폭
/// (예전 구현)으로 두면, todayIndex가 0에서 멀어질수록(로스터 시작일이
/// 아닌 오늘) 이 이력 전체가 엔진의 "최근 며칠" 창 밖으로 밀려나
/// `currentPhase()`가 "세션 없음"으로 던진다 — 실제로 이 버그 때문에
/// 로스터·홈 연동이 깨졌었다.
List<SleepSession> _demoRecentSessions(int todayIndex) {
  final base = todayIndex * 24.0;
  const starts = [
    23.3,
    24.1,
    23.7,
    8.6,
    9.1,
    24.4,
    23.2,
    23.8,
    24.0,
    23.5,
    23.4,
  ];
  const durations = [6.9, 6.3, 7.2, 5.9, 6.5, 6.7, 7.1, 6.2, 6.8, 7.0, 6.6];
  return [
    for (var d = -10; d <= 0; d++)
      SleepSession(
        base + d * 24.0 + starts[d + 10],
        base + d * 24.0 + starts[d + 10] + durations[d + 10],
      ),
  ];
}

/// 저장된 실제 Watch 수면을 엔진의 로스터 기준 절대시간으로 변환한다.
/// 실제 기록이 부족한 일반 계정에는 수면 부채를 만들지 않는 중립 기준선을
/// 사용하고, 목업 수면은 심사용 데모 계정에서만 허용한다.
List<SleepSession> sleepSessionsForNudges({
  required AppState app,
  required DateTime anchor,
  required int todayIndex,
}) {
  if (app.isDemoAccount) return _demoRecentSessions(todayIndex);
  final metrics = List<SyncedHealthMetric>.of(app.syncedHealthMetrics)
    ..sort((a, b) => a.sleepStart.compareTo(b.sleepStart));
  if (metrics.length >= 3) {
    return [
      for (final metric in metrics)
        SleepSession(
          metric.sleepStart.difference(anchor).inMinutes / 60.0,
          metric.sleepEnd.difference(anchor).inMinutes / 60.0,
        ),
    ];
  }
  final base = todayIndex * 24.0;
  return [
    for (var day = -7; day <= 0; day++)
      SleepSession(base + day * 24.0 + 23.5, base + day * 24.0 + 31.0),
  ];
}

/// `AppState.roster`가 비어 있을 때(첫 실행 전, 단독 위젯 테스트)만 쓰는 폴백.
const _demoRoster = [
  ShiftType.day,
  ShiftType.day,
  ShiftType.evening,
  ShiftType.night,
  ShiftType.night,
  ShiftType.off,
  ShiftType.off,
];

Map<String, String>? _catalogCache;

Future<Map<String, String>> _loadCatalog() async {
  final cached = _catalogCache;
  if (cached != null) return cached;
  final raw = await rootBundle.loadString('assets/messages.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final catalog = decoded.map((k, v) => MapEntry(k, v as String));
  _catalogCache = catalog;
  return catalog;
}

/// 오늘(실제 달력 날짜 기준)의 SleepPlan + 우선순위 넛지를 계산해 화면용
/// 데이터로 변환한다. `AppState`에 실제 로스터·온보딩 값이 있으면 그걸
/// 쓰고, 없으면 데모값으로 대체한다. `NudgeKind`/`SleepPlan`은 실제
/// `buildNudgePlan` 결과 그대로다.
Future<TodayNudges> loadTodayNudges() async {
  final catalog = await _loadCatalog();
  final app = AppState.instance;
  final roster = app.roster ?? _demoRoster;
  final profile = app.hasProfile ? app.toUserProfile() : null;
  final wallClock = DateTime.now();

  // roster[0]이 어느 날짜인지(rosterStartDate)를 실제 오늘과 비교해서
  // "오늘이 로스터의 몇 번째 칸인지"를 구한다. 예전엔 이걸 항상 0으로
  // 고정해서 로스터가 실제로 저장돼도 홈 화면은 늘 로스터 1일차만 봤다
  // — 로스터가 시작하는 달이 아니면(또는 그 달이 지나면) 그냥 데모
  // 로스터로 되돌아간다. 실제 로스터를 갱신 안 하고 계속 쓰는 문제까지
  // 고치는 건 아니고, 최소한 범위 밖일 땐 조용히 틀린 값을 보여주는 대신
  // 데모로 폴백한다.
  final anchor = app.rosterStartDate;
  int todayIndex;
  if (app.roster != null && anchor != null) {
    final today = DateTime(wallClock.year, wallClock.month, wallClock.day);
    final diff = today.difference(anchor).inDays;
    if (diff >= 0 && diff < roster.length) {
      todayIndex = diff;
    } else {
      todayIndex = 0; // 로스터 범위 밖 — 데모처럼 0일차로 보여줌(정확한 값은 아님)
    }
  } else {
    todayIndex = 0;
  }
  final now = todayIndex * 24.0 + wallClock.hour + wallClock.minute / 60.0;
  final sessionAnchor =
      anchor ?? DateTime(wallClock.year, wallClock.month, wallClock.day);
  final sessions = sleepSessionsForNudges(
    app: app,
    anchor: sessionAnchor,
    todayIndex: todayIndex,
  );

  final plan = buildNudgePlan(
    roster: roster,
    todayIndex: todayIndex,
    now: now,
    recentSessions: sessions,
    profile: profile,
  );

  final todayShift = roster[todayIndex];
  final isNightMood =
      todayShift == ShiftType.evening || todayShift == ShiftType.night;
  final debt = computeSleepDebtMin(sessions, now);
  final highDebt = debt >= napLongDebtThresholdMin;
  final shiftTimings = profile?.shiftTimings ?? defaultShiftTimings;

  final headerLabel = todayShift == ShiftType.off
      ? '오늘은 오프예요'
      : '오늘 ${_formatClock(shiftTimings[todayShift]!.start)} '
            '${_shiftLabel[todayShift]} 근무';

  final planLabel = plan.sleep.type == PlanType.nap
      ? '${_formatClock(plan.sleep.napStart!)} 낮잠'
      : '${_formatClock(plan.sleep.targetBedtime!)} 취침';

  final actions = plan.nudges.map((n) {
    final message = resolveNudgeMessage(
      catalog,
      n.kind,
      todayShift,
      highDebt: highDebt,
      dayIndex: (n.at / 24.0).floor(),
    );
    return NudgeAction(
      time: _formatClock(n.at),
      label: _kindLabel[n.kind]!,
      message: message,
      isPast: n.at <= now,
    );
  }).toList();

  return TodayNudges(
    isNightMood: isNightMood,
    headerLabel: headerLabel,
    planLabel: planLabel,
    summary: actions.isEmpty ? '' : actions.first.message,
    actions: actions,
  );
}

/// 로컬 알림으로 예약할 넛지 하나 — [at]은 로스터 시작일 기준 절대시간(h)이
/// 아니라 실제 달력 시각(DateTime)으로 이미 변환돼 있다.
class ScheduledNudge {
  const ScheduledNudge({
    required this.at,
    required this.title,
    required this.body,
  });
  final DateTime at;
  final String title;
  final String body;
}

/// 오늘부터 [days]일치 넛지를 실제 달력 시각으로 변환해 반환한다
/// (`NotificationService.rescheduleAll`에 그대로 넘기면 됨, §7-2).
/// 로스터가 없으면(데모 모드, 온보딩 전) 빈 리스트 — 알림을 걸 실제
/// 기준 날짜(rosterStartDate)가 없기 때문이다.
Future<List<ScheduledNudge>> loadUpcomingNudgeTriggers({int days = 2}) async {
  final app = AppState.instance;
  final roster = app.roster;
  final anchor = app.rosterStartDate;
  if (roster == null || anchor == null) return const [];

  final wallClock = DateTime.now();
  final today = DateTime(wallClock.year, wallClock.month, wallClock.day);
  final diff = today.difference(anchor).inDays;
  if (diff < 0 || diff >= roster.length) return const [];

  final catalog = await _loadCatalog();
  final profile = app.hasProfile ? app.toUserProfile() : null;
  final todayIndex = diff;
  final now = todayIndex * 24.0 + wallClock.hour + wallClock.minute / 60.0;
  final sessions = sleepSessionsForNudges(
    app: app,
    anchor: anchor,
    todayIndex: todayIndex,
  );
  final highDebt =
      computeSleepDebtMin(sessions, now) >= napLongDebtThresholdMin;

  final triggers = <ScheduledNudge>[];
  for (var offset = 0; offset < days; offset++) {
    final dayIndex = todayIndex + offset;
    if (dayIndex >= roster.length) break;

    final plan = buildNudgePlan(
      roster: roster,
      todayIndex: dayIndex,
      now: now,
      recentSessions: sessions,
      profile: profile,
    );
    final shift = roster[dayIndex];

    for (final n in plan.nudges) {
      final message = resolveNudgeMessage(
        catalog,
        n.kind,
        shift,
        highDebt: highDebt,
        dayIndex: (n.at / 24.0).floor(),
      );
      triggers.add(
        ScheduledNudge(
          at: anchor.add(Duration(minutes: (n.at * 60).round())),
          title: _kindLabel[n.kind]!,
          body: message,
        ),
      );
    }
  }
  return triggers;
}
