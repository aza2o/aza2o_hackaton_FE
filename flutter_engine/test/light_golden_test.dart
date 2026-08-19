/// `logic/light.py` 대비 골든 벡터 검증. 생성 스크립트: 대화 기록 참고
/// (roster=[D,D,E,N,N,O,O], UserProfile 기본값, start_date=2026-08-17).
library light_golden_test;

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../lib/roster/constants.dart';
import '../lib/roster/light_schedule.dart';

void expectClose(double actual, double expected, {double tol = 1e-6, String? reason}) {
  expect((actual - expected).abs() < tol, isTrue,
      reason: '${reason ?? ''} expected=$expected actual=$actual diff=${(actual - expected).abs()}');
}

void main() {
  final golden = jsonDecode(File('test/light_golden.json').readAsStringSync()) as Map<String, dynamic>;

  final roster = [
    ShiftType.day, ShiftType.day, ShiftType.evening,
    ShiftType.night, ShiftType.night, ShiftType.off, ShiftType.off,
  ];
  final profile = UserProfile();
  final startDate = DateTime.utc(2026, 8, 17);

  test('sunTimes가 Python NOAA 근사식과 일치', () {
    for (final c in golden['sun_times'] as List) {
      final parts = (c['date'] as String).split('-').map(int.parse).toList();
      final d = DateTime.utc(parts[0], parts[1], parts[2]);
      final (rise, set) = sunTimes(d, (c['lat'] as num).toDouble(), (c['lon'] as num).toDouble());
      expectClose(rise, (c['rise'] as num).toDouble(), tol: 1e-4, reason: '${c['date']} rise');
      expectClose(set, (c['set'] as num).toDouble(), tol: 1e-4, reason: '${c['date']} set');
    }
  });

  test('planSleep이 Python plan_sleep과 동일한 수면창을 낸다', () {
    final sleep = planSleep(roster, profile);
    final expected = golden['sleep'] as List;
    expect(sleep.length, expected.length);
    for (var i = 0; i < sleep.length; i++) {
      expectClose(sleep[i].start, (expected[i]['start'] as num).toDouble(), reason: 'sleep[$i].start');
      expectClose(sleep[i].end, (expected[i]['end'] as num).toDouble(), reason: 'sleep[$i].end');
      expect(sleep[i].kind, expected[i]['kind']);
    }
  });

  test('lightSeries 샘플 지점들이 Python light_series와 일치', () {
    final sleep = planSleep(roster, profile);
    final series = lightSeries(roster, profile, startDate, dt: 0.1, sleep: sleep);
    final ls = golden['light_series'];
    expect(series.time.length, ls['n']);

    final indices = (ls['sample_indices'] as List).cast<int>();
    final expectedLight = (ls['sample_light'] as List).cast<num>();
    for (var k = 0; k < indices.length; k++) {
      expectClose(series.light[indices[k]], expectedLight[k].toDouble(),
          tol: 1e-6, reason: 'light[${indices[k]}]');
    }
  });

  test('interventionWindows가 Python intervention_windows와 일치', () {
    final sleep = planSleep(roster, profile);
    final windows = interventionWindows(roster, profile, startDate, sleep: sleep);
    final expected = golden['intervention_windows'] as List;
    expect(windows.length, expected.length);
    for (var i = 0; i < windows.length; i++) {
      expectClose(windows[i].start, (expected[i]['start'] as num).toDouble(), reason: 'iv[$i].start');
      expectClose(windows[i].end, (expected[i]['end'] as num).toDouble(), reason: 'iv[$i].end');
      expect(windows[i].action, expected[i]['action']);
    }
  });
}
