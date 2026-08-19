/// `messages.json` 문구 카탈로그에서 넛지에 맞는 문구를 고른다.
///
/// 키 규칙(파일 상단 `_comment` 참고): `{shiftType}_{nudgeKind}_{debtState}_{n}`.
/// debtState는 `nudge_constants.dart`의 `napLongDebtThresholdMin`(120분)과
/// 같은 기준: 부채 120분 이상이면 high, 미만이면 normal. 없는 키는
/// `{nudgeKind}_fallback_1`로 폴백한다.
///
/// [catalog]는 이 파일 밖에서 읽어온다 — 이 패키지는 Flutter 의존성이 없는
/// 순수 Dart라 파일/에셋 I/O를 직접 하지 않는다(패키지 설명 참고). 호출부
/// (앱)에서 messages.json을 읽어 `Map<String, String>`으로 넘긴다.
///
/// 변형(_1, _2 ...)이 여럿이면 결정적으로 고른다 — 이 엔진 전체가 "같은
/// 입력엔 같은 출력"을 원칙으로 하기 때문(phase.py/circadian_model.dart의
/// 재적분 방식 참고). 같은 날 다시 열어도 같은 문구가 뜨고, 날짜가 바뀌면
/// 자연히 로테이션된다.
library nudge_messages;

import 'nudge_constants.dart';
import '../roster/constants.dart';

String _shiftKey(ShiftType s) => switch (s) {
      ShiftType.day => 'day',
      ShiftType.evening => 'evening',
      ShiftType.night => 'night',
      ShiftType.off => 'off',
    };

/// [dayIndex]는 로스터 기준 절대 일자 — 변형 선택의 결정적 시드로 쓰인다.
/// [highDebt]는 `computeSleepDebtMin(...) >= napLongDebtThresholdMin` 결과를 그대로 넘기면 된다.
String resolveNudgeMessage(
  Map<String, String> catalog,
  NudgeKind kind,
  ShiftType shiftType, {
  required bool highDebt,
  required int dayIndex,
}) {
  final debtState = highDebt ? 'high' : 'normal';
  final prefix = '${_shiftKey(shiftType)}_${kind.name}_${debtState}_';

  final variants = <String>[];
  for (var n = 1; catalog.containsKey('$prefix$n'); n++) {
    variants.add(catalog['$prefix$n']!);
  }

  if (variants.isEmpty) {
    final fallback = catalog['${kind.name}_fallback_1'];
    if (fallback == null) {
      throw ArgumentError(
        '넛지 문구 없음: kind=${kind.name} shift=$shiftType debt=$debtState (폴백도 없음)',
      );
    }
    return fallback;
  }

  final seed = dayIndex * 31 + kind.index; // 날짜+종류 해시 -> 결정적 선택
  return variants[seed % variants.length];
}
