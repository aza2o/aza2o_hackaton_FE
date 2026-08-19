"""
SHIFT 엔진 공통 상수 및 타입.

모든 매직넘버는 이 파일에 모은다. 근거가 있는 값은 출처를 주석으로 남기고,
근거가 없는 값은 ASSUMPTION 태그를 붙인다. 데모 전 이 파일만 읽으면
"무엇이 검증됐고 무엇이 가정인지"가 전부 드러나야 한다.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


# ─────────────────────────────────────────────────────────────
# 시프트 정의
# ─────────────────────────────────────────────────────────────

class ShiftType(str, Enum):
    DAY = "D"
    EVENING = "E"
    NIGHT = "N"
    OFF = "O"


@dataclass(frozen=True)
class ShiftTiming:
    """
    근무 시작·종료 시각 (소수 시간, 0~24).

    하드코딩 금지 — 병원마다 다르므로 온보딩에서 사용자가 입력한다.
    아래 값은 국내 3교대 간호사 통용 패턴을 기본값으로 둔 것일 뿐이며,
    반드시 사용자 입력으로 덮어써야 한다.
    """
    start: float
    end: float

    @property
    def crosses_midnight(self) -> bool:
        return self.end <= self.start

    @property
    def duration(self) -> float:
        return (self.end - self.start) % 24 or 24.0


DEFAULT_SHIFT_TIMINGS: dict[ShiftType, ShiftTiming] = {
    ShiftType.DAY: ShiftTiming(7.0, 15.0),
    ShiftType.EVENING: ShiftTiming(15.0, 23.0),
    ShiftType.NIGHT: ShiftTiming(23.0, 7.0),
}


# ─────────────────────────────────────────────────────────────
# 조도 상수 (lux)
# ─────────────────────────────────────────────────────────────
#
# [설계 근거] 손목 광센서는 교대근무자의 실제 노출을 관측하지 못한다.
#   - Apple TimeInDaylight는 "실외 판별기"라 실내 근무 구간이 전부 0이 된다.
#     새벽 3시 병동(300~500 lux)과 암막 침실(~1 lux)이 동일하게 0으로 기록됨.
#   - Fitbit / Garmin은 광 데이터를 API로 제공하지 않는다.
#   - Wrist-Worn IoT 광센서(PMC11100858): 소매 가림으로 손목 측정값이
#     이마 착용 센서보다 유의하게 낮음.
#
# 따라서 광 프로파일은 "측정"이 아니라 근무표에서 "연역"한다.
# 근무표 = 광 스케줄이라는 것이 SHIFT의 구조적 전제.
#
# ⚠️ ASSUMPTION: 아래 lux 값은 일반적 실내 조도 범위에서 잡은 것이며
#    측정치가 아니다. 온보딩 3지선다(밝음/보통/어두움)로 사용자가 선택한다.

INDOOR_LUX = {"bright": 500.0, "normal": 300.0, "dim": 150.0}

BEDROOM_LUX = {"blackout": 1.0, "curtain": 30.0, "none": 200.0}

HOME_AWAKE_LUX = 200.0     # ASSUMPTION: 재실 중 일반 가정 조도
OUTDOOR_DAY_LUX = 10000.0  # 흐린 날 실외도 실내보다 압도적으로 밝음
OUTDOOR_NIGHT_LUX = 5.0
COMMUTE_MINUTES = 20.0     # ASSUMPTION: 온보딩에서 사용자 입력으로 대체


# ─────────────────────────────────────────────────────────────
# Process S (수면압력) 파라미터
# ─────────────────────────────────────────────────────────────
#
# ⚠️ 이 구현은 Song/Hong 계열(CSS)의 재현이 아니라 교과서 Two-Process의
#    열화 근사다. 데모에서 "Song 2023 모델 탑재"라고 말하면 과장이며,
#    "Two-Process 기반 각성도 추정, CSS 통합은 로드맵"이 정확한 표현.
#
# ⚠️ UNVERIFIED: 아래 시상수는 원논문(Daan, Beersma & Borbély 1984) 직접
#    확인이 필요하다. 현재 값은 문헌에서 통용되는 근사치로, 발표 전 검증할 것.

TAU_RISE = 18.2      # UNVERIFIED: 각성 중 압력 상승 시상수 (h)
TAU_DECAY = 4.2      # UNVERIFIED: 수면 중 압력 감쇠 시상수 (h)
S_UPPER = 1.0        # 점근 상한
S_LOWER = 0.0        # 점근 하한


# ─────────────────────────────────────────────────────────────
# 수면효율 기반 감쇠 할인
# ─────────────────────────────────────────────────────────────
#
# [문제] 교과서 S는 "자면 정해진 속도로 압력이 빠진다"고 가정한다.
#        WASO 90분짜리 6시간 주간수면과 통잠 6시간을 동일 처리한다.
#        방향이 나쁘다 — 회복을 과대추정하므로 나이트 연속일 각성도를
#        실제보다 낙관적으로 그린다.
#
# [보정] 워치 수면효율로 감쇠율을 할인한다.
#        Lee 2025 메타분석 기준 수면효율 편향은 -4.69%이나 방향이 일관되어
#        개인 내 비교에서 상쇄된다. 따라서 절대 회복량을 주장하지 않고
#        "지난번 대비" 상대 비교까지만 허용한다.
#
# ⚠️ ASSUMPTION: 할인 함수 형태(선형)와 바닥값은 임의 설정. 검증되지 않음.

SE_REFERENCE = 0.85   # 이 수면효율에서 할인 계수 1.0
SE_FLOOR = 0.40       # 할인 계수 하한 (과도한 페널티 방지)


# ─────────────────────────────────────────────────────────────
# 넛지 발화 정책
# ─────────────────────────────────────────────────────────────
#
# 반사실 시뮬레이션 결과: Day 시프트는 개입 효과가 사실상 0(≤12분),
# Night는 근무 전 저녁 구간에서만 유의(최대 ~42분).
# 효과 없는 알림은 이탈만 유발한다 — Nahum-Shani 2018의 "law of attrition"
# (한 RCT에서 로그인 중앙값 1개월차 8회 → 2개월차 1회, 6개월차 64% 감소).

MAX_NUDGES_PER_DAY = {
    ShiftType.DAY: 1,
    ShiftType.EVENING: 2,
    ShiftType.NIGHT: 3,
    ShiftType.OFF: 1,
}

MIN_EFFECT_MINUTES = 10.0  # 이 미만의 예측 효과는 발화하지 않는다


# ─────────────────────────────────────────────────────────────
# 모델 설정
# ─────────────────────────────────────────────────────────────
#
# Huang 2021: 동일 입력이면 네 모델 간 성능 차이 없음 (Friedman, p>0.05).
#   → 4모델 병렬은 성능 목적이 아니라 "분산 노출" 목적.
# 단 활동량 입력 시 오차 120분 미만 피험자 비율이 Hannay 모델에서 20%p 우위.
#   → 기본 모델은 Hannay19.

PRIMARY_MODEL = "Hannay19"
ALL_MODELS = ["Hannay19", "Hannay19TP", "Forger99", "Jewett99"]

DT_HOURS = 0.1        # 적분 스텝
WARMUP_DAYS = 10      # 초기조건 equilibrate용 워밍업

# [초기조건] PMC12694990: 정확도가 초기화 방식·기록 기간·광노출에 좌우됨.
#   bioRxiv 2025도 ODE 기반 위상 추정의 근본 한계로 초기조건 설정을 지목.
#   → 해커톤에서는 상태 이월(state carry-over) 대신 매번 재적분한다.
#     느리지만 결정론적이고, 같은 입력에 항상 같은 출력이 나온다.
#     데모 중 값이 이상할 때 원인 추적이 가능한 것이 최적화보다 중요하다.


@dataclass
class UserProfile:
    """온보딩에서 수집하는 값. 센서로 관측 불가한 항목들."""
    shift_timings: dict[ShiftType, ShiftTiming] = field(
        default_factory=lambda: dict(DEFAULT_SHIFT_TIMINGS)
    )
    workplace_lighting: str = "normal"   # bright | normal | dim
    bedroom_lighting: str = "curtain"    # blackout | curtain | none
    commute_minutes: float = COMMUTE_MINUTES
    latitude: float = 35.87              # 기본값: 대구
    longitude: float = 128.60
