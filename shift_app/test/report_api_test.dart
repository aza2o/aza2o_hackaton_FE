import 'package:flutter_test/flutter_test.dart';
import 'package:shift_app/services/report_api.dart';

void main() {
  test('긴 수면 부채를 사람이 읽는 시간 단위로 바꾼다', () {
    expect(formatSleepDurationMinutes(1320), '22시간');
    expect(formatSleepDurationMinutes(95), '1시간 35분');
    expect(formatSleepDurationMinutes(40), '40분');
  });
}
