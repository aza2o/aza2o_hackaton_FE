// AI 리포트 `POST /functions/v1/report` 클라이언트 (Supabase Edge Function,
// Gemini 기반 코멘트 생성).
//
// gapMinutes/sleepDebtMin은 지금 교대근무를 가정한 변동형 데모 수면 패턴으로
// 계산한다. 실제
// HealthKit/Health Connect 연동은 아직 미검증 상태라(`health/health_signal_source.dart`
// 참고) 이 화면도 데모값을 쓴다 — 연동이 붙으면 데모 세션을 실측 세션으로
// 교체해야 한다.
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shift_circadian_engine/nudge/nudge_engine.dart';
import 'package:shift_circadian_engine/roster/constants.dart';

import '../engine/gap_service.dart';
import 'auth_service.dart';
import '../state/app_state.dart';

// 2026-08-20: 원래 프로젝트(zfwmwplxezqtxxbgmieb) 오너 초대가 막혀서 새
// 프로젝트로 옮김 — 함수 소스는 `shift_app/supabase/functions/report/index.ts`
// 참고. 원 함수가 쓰던 v1beta/interactions 엔드포인트는 지금 API 키
// 형식으로 401이 나서 표준 generateContent로 교체했다. 다만 이 함수는
// 아직 gapMinutes/sleepDebtMin/shiftPattern 3개만 읽는다 — 클라이언트가
// 같이 보내는 skinRoutineContext/stateNote 등은 아직 프롬프트에 안 실림.
const _reportUrl =
    'https://fthdvkrufjolrfuopvma.supabase.co/functions/v1/report';
const _reportWindowDays = 14;

class AiReportResult {
  const AiReportResult(this.comment);
  final String comment;
}

String _briefComment(String raw) {
  final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= 220) return normalized;
  final sentences = RegExp(r'[^.!?。]+[.!?。]?')
      .allMatches(normalized)
      .map((m) => m.group(0)!.trim())
      .where((s) => s.isNotEmpty)
      .take(3)
      .join(' ');
  final candidate = sentences.isEmpty ? normalized : sentences;
  return candidate.length <= 220
      ? candidate
      : '${candidate.substring(0, 217).trimRight()}...';
}

String _clockLabel(double hours) {
  final inDay = hours % 24.0;
  final h = inDay.floor();
  final m = ((inDay - h) * 60).round() % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

bool _isActionable(String comment) {
  const actionWords = [
    '해보세요',
    '해주세요',
    '줄여',
    '낮추',
    '피해',
    '멈추',
    '준비',
    '착용',
    '바르',
    '세안',
    '보습',
    '쉬어',
    '누워',
  ];
  return actionWords.any(comment.contains);
}

bool _looksLikeRepeatedTemplate(String comment, String? previousComment) {
  if (previousComment != null && previousComment.trim() == comment.trim()) {
    return true;
  }
  return comment.contains('목표 취침 1시간 전부터 조명을 낮추고') &&
      comment.contains('세안과 장벽 보습');
}

String _actionFallback({
  required int averageTargetMin,
  required int averageActualMin,
  required int upcomingNightCount,
  String? stateNote,
}) {
  final deficit = averageTargetMin - averageActualMin;
  final note = stateNote?.trim() ?? '';
  final deficitLabel = deficit >= 60
      ? '${deficit ~/ 60}시간 ${deficit % 60}분'
      : '$deficit분';
  final sleepLead = deficit >= 60
      ? '최근 실제 수면이 권장량보다 하루 평균 $deficitLabel 부족해요. 오늘은 목표 취침 40분 전부터 할 일을 멈추고 수면 준비를 시작하세요.'
      : upcomingNightCount > 0
      ? '앞으로 2주 나이트 $upcomingNightCount회에 대비해 첫 나이트 전 90분 낮잠을 확보하고 카페인은 근무 초반에만 드세요.'
      : '최근 수면량은 비교적 안정적이지만 취침 시각을 일정하게 지키는 것이 우선이에요. 오늘도 목표 취침 30분 전부터 밝은 빛을 줄이세요.';

  late final List<String> options;
  if (note.contains('턱') || note.contains('귀')) {
    options = [
      '귀·턱처럼 한쪽에 반복되는 트러블은 베개·마스크·손 접촉의 영향 가능성이 있어요. 오늘은 베개 커버를 바꾸고 이어 루프가 닿는 부위에는 무거운 크림을 피해주세요.',
      '나이트 후 세안이 늦어지면 마스크에 닿은 턱 주변 자극이 길어져요. 퇴근 직후 30초만 세안하고, 트러블 부위에는 유분감 많은 제품을 겹치지 마세요.',
      '귀와 턱의 반복 자극을 확인하려면 오늘은 제품을 새로 더하지 말고 휴대폰·이어폰을 닦아주세요. 3일간 같은 위치에 생기는지도 함께 기록해보세요.',
    ];
  } else if (note.contains('건조') ||
      note.contains('당김') ||
      note.contains('각질')) {
    options = [
      '장시간 마스크와 수면 부족 뒤 당김이 커졌다면 수분 증발 영향 가능성이 있어요. 세안 직후 3분 안에 가벼운 보습제를 두 번 얇게 나눠 발라보세요.',
      '건조·각질이 있는 날은 스크럽보다 세안 온도와 시간이 더 중요해요. 미지근한 물로 30초 이내 세안하고 당기는 부위에만 크림을 덧발라주세요.',
    ];
  } else if (note.contains('유분') ||
      note.contains('번들') ||
      note.contains('면포') ||
      note.contains('여드름')) {
    options = [
      '유분과 면포가 고민이라면 보습을 더 쌓기보다 무거운 오일·크림 단계를 줄여보세요. 세안은 하루 두 번을 넘기지 말고 가벼운 로션 한 단계만 남겨주세요.',
      '번들거림 때문에 반복 세안하면 오히려 자극이 늘 수 있어요. 오늘은 과세안을 멈추고 턱·이마처럼 막히는 부위에는 유분감 높은 제품을 겹치지 마세요.',
    ];
  } else if (note.contains('붉') || note.contains('민감') || note.contains('따가')) {
    options = [
      '붉음·따가움은 자극 누적 신호일 수 있어요. 오늘은 레티놀·각질제거제·고농도 비타민 제품을 쉬고, 사용 중인 제품을 새로 바꾸지 마세요.',
      '피부가 예민한 날에는 단계를 추가하기보다 원인을 분리해야 해요. 향이 강한 제품과 활성 성분을 48시간 쉬면서 붉음이 줄어드는지 확인해보세요.',
    ];
  } else if (note.contains('트러블') || note.contains('피부')) {
    options = [
      '피부 고민의 위치와 양상이 아직 부족해요. 오늘은 새 제품을 추가하지 말고 건조·유분·붉음 중 무엇이 두드러지는지 기록하면 다음 추천을 더 정확히 좁힐 수 있어요.',
    ];
  } else if (deficit >= 60) {
    final nightContext = upcomingNightCount > 0
        ? '앞으로 2주 나이트 $upcomingNightCount회까지 고려하면'
        : '이번 근무 흐름에서는';
    options = [
      '최근 실제 수면이 권장량보다 평균 $deficitLabel 짧아요. $nightContext 오늘은 알림이 울리면 샤워를 10분 안에 끝내고 목표 취침을 30분 앞당겨보세요.',
      '평균 $deficitLabel의 수면 부족이 누적되고 있어요. $nightContext 퇴근 후 미룰 일 한 가지만 내일로 넘기고 바로 수면 준비를 시작해보세요.',
      '하루 평균 $deficitLabel이 부족해 회복 시간을 먼저 확보해야 해요. 피부 상태 정보가 없으므로 제품을 임의 추천하지 않고, 오늘은 나이트 퇴근길 선케어 여부만 챙겨주세요.',
    ];
  } else if (upcomingNightCount > 0) {
    options = [
      '앞으로 2주에 나이트가 $upcomingNightCount회 있어요. 다음 근무 전에는 밝은 빛을 미리 쬐고, 퇴근용 선글라스와 선케어를 준비해보세요.',
      '예정된 나이트 $upcomingNightCount회 중 첫 근무 전에 짧은 낮잠 시간을 확보해보세요. 아침 퇴근 후에는 순한 세안과 장벽 보습으로 마무리해보세요.',
      '다음 2주 나이트 $upcomingNightCount회에 맞춰 카페인은 근무 초반에만 마셔보세요. 퇴근 후 피부 루틴은 세안과 보습으로 짧게 끝내세요.',
    ];
  } else {
    options = [
      '안내된 목표 시각에 맞춰 조명을 미리 낮춰보세요. 주 수면 전에는 순한 세안과 보습으로 루틴을 짧게 마무리해주세요.',
      '오늘은 목표 취침 30분 전부터 휴대폰을 멀리 두어보세요. 피부 루틴은 세안 뒤 보습과 선케어 순서만 기억하면 돼요.',
      '기상 직후 밝은 빛을 받고 취침 전에는 방을 어둡게 만들어보세요. 피부는 생체 기상 후 보습과 자외선 차단을 챙겨주세요.',
    ];
  }
  final selected = options[math.Random().nextInt(options.length)];
  final hasSkinSignal =
      note.contains('피부') ||
      note.contains('트러블') ||
      note.contains('턱') ||
      note.contains('귀') ||
      note.contains('건조') ||
      note.contains('당김') ||
      note.contains('유분') ||
      note.contains('면포') ||
      note.contains('여드름') ||
      note.contains('붉') ||
      note.contains('민감') ||
      note.contains('따가');
  return hasSkinSignal ? _briefComment('$sleepLead $selected') : selected;
}

/// 사용자가 직접 적는 "지금 상태" 메모의 최대 길이. 프롬프트로 그대로
/// 들어가므로 길이를 제한해 토큰 비용과 남용을 함께 막는다.
const stateNoteMaxLength = 200;

/// [stateNote]는 사용자가 직접 입력한 현재 컨디션(선택). 계정 정보는
/// 보내지 않는다 — 무엇을 보내는지는 `privacy_policy_screen.dart` §4에
/// 적힌 내용과 정확히 일치해야 한다.
///
/// ⚠️ 서버(Supabase Edge Function) 소스가 이 저장소에 없다. 클라이언트는
/// stateNote를 실어 보내지만, 배포된 함수가 이 필드를 프롬프트에 넣도록
/// 수정되기 전까지는 리포트 문구에 반영되지 않는다.
Future<AiReportResult> fetchAiReport({
  required List<ShiftType> roster,
  required UserProfile profile,
  String? stateNote,
  String? previousComment,
}) async {
  final personalState = AppState.instance;
  final recentCheckIns = personalState.recentCheckIns(days: 14);
  final repeatedStateCounts = {
    for (final tag in {for (final entry in recentCheckIns) ...entry.tags})
      tag: recentCheckIns.where((entry) => entry.tags.contains(tag)).length,
  };
  final effectiveStateNote = [
    if (stateNote != null && stateNote.trim().isNotEmpty)
      '오늘: ${stateNote.trim()}',
    '피부: ${personalState.skinType}',
    if (personalState.skinConcerns.isNotEmpty)
      '평소 고민: ${personalState.skinConcerns.join('/')}',
    if (personalState.skinSensitivities.isNotEmpty)
      '민감 요인: ${personalState.skinSensitivities.join('/')}',
    if (repeatedStateCounts.isNotEmpty)
      '최근 14일 반복: ${repeatedStateCounts.entries.map((e) => '${e.key} ${e.value}회').join(', ')}',
  ].join('; ');
  final windowDays = roster.length < _reportWindowDays
      ? roster.length
      : _reportWindowDays;

  final gapMinutes = gapMinutesSeries(
    roster: roster,
    shiftTimings: profile.shiftTimings,
    commuteMinutes: profile.commuteMinutes,
    windowDays: windowDays,
  );

  final sessions = demoSessionsForWindow(windowDays);
  final sleepDebtMin = computeSleepDebtMin(sessions, windowDays * 24.0).round();
  final shiftPattern = roster.take(windowDays).map((s) => s.name).toList();
  final sleepDays = sleepDurationSeries(roster: roster, windowDays: windowDays);
  final averageTargetMin = sleepDays.isEmpty
      ? 0
      : sleepDays.fold<int>(0, (sum, d) => sum + d.targetMinutes) ~/
            sleepDays.length;
  final averageActualMin = sleepDays.isEmpty
      ? 0
      : sleepDays.fold<int>(0, (sum, d) => sum + d.actualMinutes) ~/
            sleepDays.length;
  final totalDeficitMin = sleepDays.fold<int>(
    0,
    (sum, d) => sum + (d.deficitMinutes > 0 ? d.deficitMinutes : 0),
  );
  final upcomingNightCount = roster
      .take(windowDays)
      .where((shift) => shift == ShiftType.night)
      .length;
  final shiftCounts = {
    for (final shift in ShiftType.values)
      shift.name: shiftPattern.where((name) => name == shift.name).length,
  };
  final averageDailyDeficitMin = sleepDays.isEmpty
      ? 0
      : sleepDays.fold<int>(
              0,
              (sum, d) => sum + (d.deficitMinutes > 0 ? d.deficitMinutes : 0),
            ) ~/
            sleepDays.length;
  String? recommendedBedtime;
  try {
    final ideal = idealSleepTimes(
      roster: roster,
      todayIndex: 0,
      shiftTimings: profile.shiftTimings,
      commuteMinutes: profile.commuteMinutes,
      recentSessions: sessions,
    );
    recommendedBedtime = _clockLabel(ideal.bedtime);
  } on ArgumentError {
    recommendedBedtime = null;
  }
  const variationFocuses = [
    '취침 준비 순서',
    '카페인 섭취 시점',
    '퇴근길 빛 관리',
    '기상 직후 빛과 선케어',
    '주 수면 전 피부 루틴',
  ];
  final variationFocus =
      variationFocuses[math.Random().nextInt(variationFocuses.length)];

  final res = await http.post(
    Uri.parse(_reportUrl),
    headers: {
      'Content-Type': 'application/json',
      'apikey': AuthService.publishableKey,
      'Authorization': 'Bearer ${AuthService.publishableKey}',
    },
    body: jsonEncode({
      'gapMinutes': gapMinutes,
      'sleepDebtMin': sleepDebtMin,
      'shiftPattern': shiftPattern,
      'sleepSummary': {
        'averageTargetMin': averageTargetMin,
        'averageActualMin': averageActualMin,
        'totalDeficitMin': totalDeficitMin,
      },
      'skinRoutineContext': {
        'savedSkinProfile': {
          'type': personalState.skinType,
          'concerns': personalState.skinConcerns,
          'sensitivities': personalState.skinSensitivities,
        },
        'todayShift': roster.isEmpty ? 'unknown' : roster.first.name,
        'upcomingNightCount': upcomingNightCount,
        'recoveryMode':
            sleepDays.isNotEmpty && sleepDays.first.deficitMinutes >= 60,
        'availableProductSlots': [
          '저자극 클렌저',
          '가벼운 진정 미스트',
          '수분 장벽 세럼',
          '유분감 있는 회복 크림',
          '휴대용 선케어',
        ],
        'recommendationRules': {
          'jawOrEarBreakout': '마스크·베개·이어폰·손 접촉과 세안 지연을 우선 점검하고 무거운 크림 중첩을 피한다',
          'dryOrTight': '세안 직후 3분 이내 보습을 얇게 두 번 적용한다',
          'oilyOrComedonal': '보습을 추가하지 말고 오일·무거운 크림과 과세안을 줄인다',
          'redOrSensitive': '레티놀·각질제거제·고농도 활성 성분을 48시간 중단한다',
          'noSkinSignal':
              '피부 상태를 추측하지 말고 근무 중 마찰·퇴근길 자외선처럼 데이터로 확인 가능한 행동만 제안한다',
        },
      },
      'variation': {
        'focus': variationFocus,
        'requestId': DateTime.now().microsecondsSinceEpoch.toString(),
        'avoidPreviousAnswer': ?previousComment,
      },
      'personalizationBrief': {
        'recentDailyCheckIns': [
          for (final entry in recentCheckIns.take(14))
            {
              'date': entry.at.toIso8601String().substring(0, 10),
              'tags': entry.tags,
              if (entry.note.isNotEmpty) 'note': entry.note,
            },
        ],
        'repeatedStateCounts': repeatedStateCounts,
        'periodDays': windowDays,
        'shiftCounts': shiftCounts,
        'upcomingNightCount': upcomingNightCount,
        'averageTargetSleepMin': averageTargetMin,
        'averageActualSleepMin': averageActualMin,
        'averageDailyDeficitMin': averageDailyDeficitMin,
        'totalDeficitMin': totalDeficitMin,
        'recommendedBedtime': ?recommendedBedtime,
        'userState': effectiveStateNote,
      },
      'responseInstruction':
          '당신은 교대근무 간호사의 일주기·수면·피부 루틴을 돕는 개인 웰니스 코치입니다. '
          '이 서비스의 최우선 기능은 수면 관리입니다. 답변의 첫 두 문장은 반드시 수면 인사이트와 실행 행동이어야 하며 피부 이야기로 시작하거나 피부 조언만 제공하면 안 됩니다. '
          '반드시 personalizationBrief와 userState를 근거로 이 사용자에게만 해당하는 답을 한국어 3문장, 200자 이내로 작성하세요. '
          'recentDailyCheckIns에서 같은 상태가 2회 이상 반복되면 오늘만의 증상처럼 다루지 말고, 정확한 반복 일수와 함께 근무·수면 패턴의 연관 가능성을 짚으세요. '
          'savedSkinProfile의 피부 타입, 반복 고민, 자극 상황과 오늘 userState가 충돌하면 오늘 상태를 우선하되 평소 프로필과 무엇이 달라졌는지 설명하세요. '
          '첫 문장에는 평균 필요 수면 대비 실제 수면 부족분, 누적 수면 부채, 취침 시각 변동 또는 나이트 횟수 중 의미 있는 숫자 하나를 사용해 수면 상태와 원인을 짚으세요. '
          '둘째 문장에는 recommendedBedtime, 다음 근무 시각, 카페인 마감 또는 낮잠 시각을 사용해 오늘 실행할 수면 행동을 정확한 시각과 함께 제안하세요. '
          '셋째 문장에만 피부 행동을 하나 제안하되, 피부 고민이 없으면 피부 문장을 생략하고 수면 회복 행동을 하나 더 제안하세요. '
          '피부 추천은 userState의 위치와 증상에 따라 달라야 합니다. 턱·귀 트러블은 마스크·베개·이어폰 접촉, 건조·당김은 보습 적용 시점, 유분·면포는 무거운 단계 축소, 붉음·민감은 활성 성분 중단을 우선하세요. '
          'userState에 피부 신호가 없으면 피부 상태를 추측하거나 제품을 추천하지 말고, 나이트 퇴근길 자외선이나 장시간 마스크 마찰처럼 근무 데이터로 확인 가능한 행동만 말하세요. '
          '모든 피부에 통용되는 진정·장벽 보습을 기본 답으로 사용하지 마세요. 무엇을 추가할지뿐 아니라 무엇을 빼거나 쉬어야 하는지도 명시하세요. '
          '항상 조명을 낮추고 카페인을 피하라는 동일 문구를 반복하지 말고 variation.focus에 맞춰 행동을 바꾸세요. '
          '데이터를 장황하게 해설하거나 일반적인 건강 상식만 말하지 마세요. 사용자가 입력한 불편이 있으면 가장 먼저 반영하세요. '
          '피부 진단, 효능 단정, 점수, 죄책감을 주는 명령조와 존재하지 않는 제품명은 사용하지 마세요.',
      'stateNote': effectiveStateNote.length > stateNoteMaxLength
          ? effectiveStateNote.substring(0, stateNoteMaxLength)
          : effectiveStateNote,
    }),
  );
  if (res.statusCode != 200) {
    throw Exception('AI 리포트 서버 오류 (HTTP ${res.statusCode})');
  }
  final json = jsonDecode(res.body) as Map<String, dynamic>;
  final generated = _briefComment(json['comment'] as String? ?? '');
  final comment =
      _isActionable(generated) &&
          !_looksLikeRepeatedTemplate(generated, previousComment)
      ? generated
      : _actionFallback(
          averageTargetMin: averageTargetMin,
          averageActualMin: averageActualMin,
          upcomingNightCount: upcomingNightCount,
          stateNote: effectiveStateNote,
        );
  return AiReportResult(comment);
}
