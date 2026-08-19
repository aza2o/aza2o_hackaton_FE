/// `룰엔진_규칙_v2.md` §1의 상수표·enum을 그대로 옮긴 것.
/// 값을 바꾸려면 문서를 먼저 갱신하고 여기에 다시 반영할 것.
library nudge_constants;

/// 문서 §6 "인터페이스 변경 요청"의 Dart 스니펫과 동일.
enum NudgeKind {
  caffeineCutoff,
  lightBlock,
  lightExposure,
  windDown,
  napStart,
  sunglassesCommute,
  brightLightAtWork,
}

enum PlanType { bedtime, nap }

// ── §1 상수표 (분 단위) ──────────────────────────────────────────

/// 메타분석(Gardiner 2023) 근거: 취침 8.8시간 전까지 카페인 마감.
const double caffeineCutoffBeforeMin = 528.0;

/// 임상 권고 범위(60~120) 내: 취침 전 광 노출 차단 시작 시점.
const double lightBlockBeforeMin = 120.0;

/// 임의값 유지 (문서 §1).
const double windDownBeforeMin = 60.0;

/// 임의값 유지 (문서 §1).
const double lightExposureAfterMin = 30.0;

/// 생체시계는 하루 약 1시간만 이동한다 — §2-③ 이동량 clamp 상한.
const double maxShiftPerDayMin = 60.0;

/// 수면 관성이 덜한 낮잠 길이. 이 두 값만 반환할 것 (§1, §3).
const double napShortMin = 20.0;
const double napLongMin = 90.0;

/// 이 부채(분) 이상이면 90분 낮잠, 미만이면 20분 (§3).
const double napLongDebtThresholdMin = 120.0;

/// 근무 시작 2~4시간 전 낮잠이 가장 근거가 탄탄함(§1). 낮잠 분기 임계값이자
/// "낮잠_종료~근무 시작" 최소 여유시간(§3).
const double napBeforeShiftMinMin = 180.0;

/// 목표치이자 부채 계산 기준(§1).
const double defaultNeedSleepMin = 420.0;

/// ASSUMPTION: §2-① 이상적 시각 역산에 필요하지만 문서 상수표에는 없는 값.
/// 근무 전후 준비시간(샤워·환복 등). 검증되지 않음 — 온보딩 입력으로 대체 권장.
const double prepMinutes = 20.0;

/// §2-②③, §2-① 오프 폴백에 쓰는 순환평균 관측 기간(일).
const int phaseWindowDays = 5;

/// §3 낮잠 파라미터의 수면부채 계산 창(일).
const int debtWindowDays = 7;
