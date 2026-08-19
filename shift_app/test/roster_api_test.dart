// `RosterParseResult.fromJson`이 §4-2-1의 세 가지 응답 모양을 정확히
// 해석하는지 확인한다. 실제 HTTP 왕복은 서버 쪽(`logic/test_main_roster_parse.py`)에서
// 이미 검증하므로, 여기선 JSON 파싱 로직만 순수하게 본다.
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_app/services/roster_api.dart';

void main() {
  test('ok 응답을 shifts(day->code) 맵으로 해석한다', () {
    final r = RosterParseResult.fromJson({
      'status': 'ok',
      'year': 2026,
      'month': 8,
      'shifts': {'1': 'D', '2': 'N'},
      'unmapped_codes': ['연차'],
    });

    expect(r.isOk, isTrue);
    expect(r.year, 2026);
    expect(r.month, 8);
    expect(r.shifts, {1: 'D', 2: 'N'});
    expect(r.unmappedCodes, ['연차']);
  });

  test('needs_row_selection 응답을 후보 목록으로 해석한다', () {
    final r = RosterParseResult.fromJson({
      'status': 'needs_row_selection',
      'candidates': [
        {'row': 3, 'name': '이수정'},
        {'row': 7, 'name': '이수정'},
      ],
    });

    expect(r.needsRowSelection, isTrue);
    expect(r.candidates, hasLength(2));
    expect(r.candidates!.first.row, 3);
    expect(r.candidates!.first.name, '이수정');
  });

  test('error 응답을 message로 해석한다', () {
    final r = RosterParseResult.fromJson({'status': 'error', 'message': '파일을 읽을 수 없어요'});

    expect(r.status, 'error');
    expect(r.message, '파일을 읽을 수 없어요');
  });

  test('RosterParseResult.error()는 클라이언트 측(네트워크 등) 실패를 담는다', () {
    final r = RosterParseResult.error('서버에 연결할 수 없어요');
    expect(r.status, 'error');
    expect(r.isOk, isFalse);
  });
}
