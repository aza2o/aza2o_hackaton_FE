import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_app/services/report_api.dart';
import 'package:shift_app/state/app_state.dart';
import 'package:shift_circadian_engine/roster/constants.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.signOut();
  });

  test('긴 수면 부채를 사람이 읽는 시간 단위로 바꾼다', () {
    expect(formatSleepDurationMinutes(1320), '22시간');
    expect(formatSleepDurationMinutes(95), '1시간 35분');
    expect(formatSleepDurationMinutes(40), '40분');
  });

  test('일반 계정은 수면 기록이 부족하면 데모 분석을 사용하지 않는다', () async {
    AppState.instance.setAuthenticatedUser(
      name: '신규 사용자',
      email: 'new-user@example.com',
    );

    final result = await fetchAiReport(
      roster: const [ShiftType.day, ShiftType.off, ShiftType.night],
      profile: UserProfile(),
    );

    expect(result.comment, insufficientSleepDataMessage);
    expect(result.comment, isNot(contains('데모 수면 기록')));
  });

  test('계정이 바뀌면 이전 계정의 AI와 건강 데이터가 제거된다', () {
    final state = AppState.instance;
    state.setAuthenticatedUser(name: '첫 사용자', email: 'first@example.com');
    state.saveAiComment('이전 계정 분석');
    state.replaceSyncedHealthMetrics([
      SyncedHealthMetric(
        date: DateTime(2026, 8, 20),
        sleepStart: DateTime(2026, 8, 20),
        sleepEnd: DateTime(2026, 8, 20, 7),
        sleepMinutes: 420,
        hrvZ: null,
        restingHeartRate: null,
        source: 'test',
      ),
    ]);

    state.setAuthenticatedUser(name: '둘째 사용자', email: 'second@example.com');

    expect(state.aiComment, isNull);
    expect(state.syncedHealthMetrics, isEmpty);
  });
}
