/// `logic/constants.py`의 로스터·조도 관련 상수를 그대로 옮긴 것.
/// 값을 바꾸려면 Python 원본을 먼저 바꾸고 여기에 다시 반영할 것
/// (두 엔진이 같은 상수를 쓴다는 전제가 무너지면 안 된다).
library roster_constants;

enum ShiftType { day, evening, night, off }

ShiftType shiftTypeFromCode(String code) {
  switch (code.toUpperCase()) {
    case 'D':
      return ShiftType.day;
    case 'E':
      return ShiftType.evening;
    case 'N':
      return ShiftType.night;
    case 'O':
      return ShiftType.off;
    default:
      throw ArgumentError('알 수 없는 근무 코드: $code');
  }
}

/// 근무 시작·종료 시각 (소수 시간, 0~24).
/// 하드코딩 금지 — 병원마다 다르므로 온보딩에서 사용자가 입력한 값을 쓴다.
/// 아래 기본값은 국내 3교대 통용 패턴일 뿐, 반드시 사용자 입력으로 덮어쓸 것.
class ShiftTiming {
  const ShiftTiming(this.start, this.end);
  final double start;
  final double end;

  bool get crossesMidnight => end <= start;

  double get duration {
    final d = (end - start) % 24.0;
    return d == 0 ? 24.0 : d;
  }
}

final Map<ShiftType, ShiftTiming> defaultShiftTimings = {
  ShiftType.day: const ShiftTiming(7.0, 15.0),
  ShiftType.evening: const ShiftTiming(15.0, 23.0),
  ShiftType.night: const ShiftTiming(23.0, 7.0),
};

// ── 조도 상수 (lux) ──────────────────────────────────────────
// [설계 근거] light.py와 동일 — 손목 광센서는 교대근무자의 실제 노출을
// 관측하지 못하므로, 광 프로파일은 "측정"이 아니라 근무표에서 "연역"한다.
// ⚠️ ASSUMPTION: 실측치가 아니다. 온보딩 3지선다로 사용자가 선택한다.

const Map<String, double> indoorLux = {'bright': 500.0, 'normal': 300.0, 'dim': 150.0};
const Map<String, double> bedroomLux = {'blackout': 1.0, 'curtain': 30.0, 'none': 200.0};

const double homeAwakeLux = 200.0; // ASSUMPTION: 재실 중 일반 가정 조도
const double outdoorDayLux = 10000.0;
const double outdoorNightLux = 5.0;
const double defaultCommuteMinutes = 20.0;

/// 온보딩에서 수집하는 값. 센서로 관측 불가한 항목들 (`logic/constants.py`의
/// `UserProfile`에 대응).
class UserProfile {
  UserProfile({
    Map<ShiftType, ShiftTiming>? shiftTimings,
    this.workplaceLighting = 'normal', // bright | normal | dim
    this.bedroomLighting = 'curtain', // blackout | curtain | none
    this.commuteMinutes = defaultCommuteMinutes,
    this.latitude = 35.87, // 기본값: 대구
    this.longitude = 128.60,
  }) : shiftTimings = shiftTimings ?? Map.of(defaultShiftTimings);

  final Map<ShiftType, ShiftTiming> shiftTimings;
  final String workplaceLighting;
  final String bedroomLighting;
  final double commuteMinutes;
  final double latitude;
  final double longitude;
}
