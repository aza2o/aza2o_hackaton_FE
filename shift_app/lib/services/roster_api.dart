// `POST /roster/parse` 클라이언트. 계약은 `SHIFT_프론트엔드_기획서.md`
// §4-2-1, 서버 구현은 `logic/main.py` + `logic/roster_parse.py`.
//
// year_hint/month_hint는 항상 보낸다 — 그러면 "연도 누락" 분기(needs_year)
// 자체가 생기지 않는다는 게 계약 문서의 권장 사항이라, 서버도 이 두 값을
// required로 받게 구현해뒀다.
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

// Railway 배포 주소(logic/ 패키지, `railway.app` 프로젝트 `shift-roster-api`).
// 로컬 개발 중 맥 LAN IP(`uvicorn ... --host 0.0.0.0 --port 8001`)로 되돌리고
// 싶으면 이 상수만 바꾸면 된다.
const _baseUrl = 'https://shift-roster-api-production.up.railway.app';

class RosterRowCandidate {
  const RosterRowCandidate({required this.row, required this.name});
  final int row;
  final String name;
}

class RosterParseResult {
  const RosterParseResult._({
    required this.status,
    this.year,
    this.month,
    this.shifts,
    this.unmappedCodes,
    this.candidates,
    this.message,
  });

  final String status; // ok | needs_row_selection | error
  final int? year;
  final int? month;
  final Map<int, String>? shifts; // day -> D/E/N/O
  final List<String>? unmappedCodes;
  final List<RosterRowCandidate>? candidates;
  final String? message;

  bool get isOk => status == 'ok';
  bool get needsRowSelection => status == 'needs_row_selection';

  factory RosterParseResult.fromJson(Map<String, dynamic> json) {
    switch (json['status']) {
      case 'ok':
        final shiftsJson = json['shifts'] as Map<String, dynamic>;
        return RosterParseResult._(
          status: 'ok',
          year: json['year'] as int,
          month: json['month'] as int,
          shifts: shiftsJson.map((k, v) => MapEntry(int.parse(k), v as String)),
          unmappedCodes: (json['unmapped_codes'] as List).cast<String>(),
        );
      case 'needs_row_selection':
        final candidates = (json['candidates'] as List)
            .map((c) => RosterRowCandidate(
                  row: (c as Map<String, dynamic>)['row'] as int,
                  name: c['name'] as String? ?? '',
                ))
            .toList();
        return RosterParseResult._(status: 'needs_row_selection', candidates: candidates);
      default:
        return RosterParseResult._(
          status: 'error',
          message: json['message'] as String? ?? '알 수 없는 오류예요',
        );
    }
  }

  factory RosterParseResult.error(String message) =>
      RosterParseResult._(status: 'error', message: message);
}

/// [bytes]는 `file_picker`의 `PlatformFile.bytes`(웹 포함 모든 플랫폼에서
/// 동작하도록 경로가 아니라 바이트를 받는다). [rowIndex]는
/// `needs_row_selection` 응답을 받은 뒤 사용자가 행을 고르면 채워서
/// 재요청할 때만 쓴다.
Future<RosterParseResult> parseRosterFile({
  required Uint8List bytes,
  required String filename,
  required String userName,
  required int year,
  required int month,
  Map<String, String> knownCodeMappings = const {},
  int? rowIndex,
}) async {
  try {
    final req = http.MultipartRequest('POST', Uri.parse('$_baseUrl/roster/parse'))
      ..fields['user_name'] = userName
      ..fields['year_hint'] = year.toString()
      ..fields['month_hint'] = month.toString()
      ..fields['known_code_mappings'] = jsonEncode(knownCodeMappings)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    if (rowIndex != null) req.fields['row_index'] = rowIndex.toString();

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      return RosterParseResult.error('서버 오류예요 (HTTP ${res.statusCode})');
    }
    return RosterParseResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  } catch (e) {
    return RosterParseResult.error('서버에 연결할 수 없어요: $e');
  }
}
