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

const _reportUrl = 'https://zfwmwplxezqtxxbgmieb.supabase.co/functions/v1/report';
const _reportWindowDays = 14;

class AiReportResult {
  const AiReportResult(this.comment);
  final String comment;
}

Future<AiReportResult> fetchAiReport({
  required List<ShiftType> roster,
  required UserProfile profile,
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
    }),
  );
  if (res.statusCode != 200) {
    throw Exception('AI 리포트 서버 오류 (HTTP ${res.statusCode})');
  }
  final json = jsonDecode(res.body) as Map<String, dynamic>;
  return AiReportResult(json['comment'] as String? ?? '');
}
