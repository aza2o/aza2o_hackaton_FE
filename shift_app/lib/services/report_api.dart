// AI 리포트 `POST /functions/v1/report` 클라이언트 (Supabase Edge Function,
// Gemini 기반 코멘트 생성).
//
// gapMinutes/sleepDebtMin은 지금 `nudge_service.dart`의 _demoRecentSessions와
// 동일한 데모 수면 패턴(매일 22:00 취침, 7시간 수면)으로 계산한다. 실제
// HealthKit/Health Connect 연동은 아직 미검증 상태라(`health/health_signal_source.dart`
// 참고) 이 화면도 데모값을 쓴다 — 연동이 붙으면 데모 세션을 실측 세션으로
// 교체해야 한다.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shift_circadian_engine/nudge/nudge_engine.dart';
import 'package:shift_circadian_engine/roster/constants.dart';
import '../engine/gap_service.dart';

// 2026-08-20: 원래 프로젝트(zfwmwplxezqtxxbgmieb) 오너 초대가 막혀서 새
// 프로젝트(aza2o-shift-report, ap-northeast-2)로 옮김 — 함수 소스는
// `supabase/functions/report/index.ts` 참고. 원 프로젝트 접근 가능해지면
// 다시 합칠지 결정할 것.
const _reportUrl = 'https://fthdvkrufjolrfuopvma.supabase.co/functions/v1/report';
const _reportWindowDays = 14;

class AiReportResult {
  const AiReportResult(this.comment);
  final String comment;
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
}) async {
  final windowDays = roster.length < _reportWindowDays ? roster.length : _reportWindowDays;

  final gapMinutes = gapMinutesSeries(
    roster: roster,
    shiftTimings: profile.shiftTimings,
    commuteMinutes: profile.commuteMinutes,
    windowDays: windowDays,
  );

  final sessions = demoSessionsForWindow(windowDays);
  final sleepDebtMin = computeSleepDebtMin(sessions, windowDays * 24.0).round();
  final shiftPattern = roster.take(windowDays).map((s) => s.name).toList();

  final res = await http.post(
    Uri.parse(_reportUrl),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'gapMinutes': gapMinutes,
      'sleepDebtMin': sleepDebtMin,
      'shiftPattern': shiftPattern,
      if (stateNote != null && stateNote.trim().isNotEmpty)
        'stateNote': stateNote.trim().length > stateNoteMaxLength
            ? stateNote.trim().substring(0, stateNoteMaxLength)
            : stateNote.trim(),
    }),
  );
  if (res.statusCode != 200) {
    throw Exception('AI 리포트 서버 오류 (HTTP ${res.statusCode})');
  }
  final json = jsonDecode(res.body) as Map<String, dynamic>;
  return AiReportResult(json['comment'] as String? ?? '');
}
