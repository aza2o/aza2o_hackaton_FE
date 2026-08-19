/// 실제 `messages.json`(레포 루트) 대조 테스트 — `resolveNudgeMessage`가
/// 키 조립·폴백·결정적 변형 선택을 문서 규칙대로 하는지 확인한다.
library nudge_messages_test;

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../lib/roster/constants.dart';
import '../lib/nudge/nudge_constants.dart';
import '../lib/nudge/nudge_messages.dart';

void main() {
  final raw = jsonDecode(File('../messages.json').readAsStringSync()) as Map<String, dynamic>;
  final catalog = raw.map((k, v) => MapEntry(k, v as String));

  test('구체 키가 있으면 그중 하나를 반환 (night_caffeineCutoff_normal_1/2)', () {
    final msg = resolveNudgeMessage(
      catalog, NudgeKind.caffeineCutoff, ShiftType.night,
      highDebt: false, dayIndex: 0,
    );
    expect(
      [catalog['night_caffeineCutoff_normal_1'], catalog['night_caffeineCutoff_normal_2']],
      contains(msg),
    );
  });

  test('debtState가 high면 다른 키 그룹(_high_*)을 참조한다', () {
    final msg = resolveNudgeMessage(
      catalog, NudgeKind.caffeineCutoff, ShiftType.night,
      highDebt: true, dayIndex: 0,
    );
    expect(
      [catalog['night_caffeineCutoff_high_1'], catalog['night_caffeineCutoff_high_2']],
      contains(msg),
    );
  });

  test('day_sunglassesCommute처럼 구체 키가 없으면 {kind}_fallback_1로 폴백', () {
    expect(catalog.containsKey('day_sunglassesCommute_normal_1'), isFalse);
    final msg = resolveNudgeMessage(
      catalog, NudgeKind.sunglassesCommute, ShiftType.day,
      highDebt: false, dayIndex: 0,
    );
    expect(msg, catalog['sunglassesCommute_fallback_1']);
  });

  test('day_napStart처럼 구체 키가 없으면 폴백 (day는 낮잠 분기 자체가 없음)', () {
    expect(catalog.containsKey('day_napStart_normal_1'), isFalse);
    final msg = resolveNudgeMessage(
      catalog, NudgeKind.napStart, ShiftType.day,
      highDebt: false, dayIndex: 0,
    );
    expect(msg, catalog['napStart_fallback_1']);
  });

  test('같은 (kind, shift, debt, dayIndex)는 항상 같은 문구 (결정적)', () {
    final a = resolveNudgeMessage(
      catalog, NudgeKind.lightBlock, ShiftType.evening,
      highDebt: false, dayIndex: 12,
    );
    final b = resolveNudgeMessage(
      catalog, NudgeKind.lightBlock, ShiftType.evening,
      highDebt: false, dayIndex: 12,
    );
    expect(a, b);
  });

  test('dayIndex가 바뀌면 변형이 로테이션될 수 있다 (2개 변형 -> 인접일에 번갈아 나옴)', () {
    final day0 = resolveNudgeMessage(
      catalog, NudgeKind.windDown, ShiftType.off,
      highDebt: false, dayIndex: 0,
    );
    final day1 = resolveNudgeMessage(
      catalog, NudgeKind.windDown, ShiftType.off,
      highDebt: false, dayIndex: 1,
    );
    expect(day0, isNot(day1));
  });

  test('없는 kind/shift/debt 조합이고 폴백 키도 없으면 예외', () {
    final empty = <String, String>{};
    expect(
      () => resolveNudgeMessage(empty, NudgeKind.windDown, ShiftType.off,
          highDebt: false, dayIndex: 0),
      throwsArgumentError,
    );
  });
}
