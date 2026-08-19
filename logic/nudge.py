"""
넛지 랭킹 — 반사실(counterfactual) 처치효과 기반.

각 후보 개입에 대해 "그 개입을 했을 때"와 "안 했을 때"의 광 스케줄을 각각
모델에 태우고, DLMO 이동량 차이를 처치효과로 삼아 순위를 매긴다.

⚠️ 이것은 PRC(Phase Response Curve)가 아니다.
   circadian v1.0.3의 PRCFinder는 Czeisler Type 0 constant-routine 프로토콜을
   재현하는 연구용 유틸리티로, 사용자 로스터/광 데이터를 입력받지 못한다.
   여기서 쓰는 것은 반사실 시뮬레이션이며 둘은 다른 것이다.

[발화 정책의 근거]
  자체 반사실 시뮬레이션 결과 —
    Day 시프트: 개입 효과 사실상 0 (≤12분)
    Night 시프트: 근무 전 저녁 구간에서만 유의 (최대 ~42분)
  효과 없는 알림은 이탈만 유발한다.
  Nahum-Shani 2018 "law of attrition": 한 RCT에서 로그인 중앙값이
  1개월차 8회 → 2개월차 1회, 6개월차 사용자 64% 감소.

[검증 설계]
  JITAI 마이크로랜덤화 시험(JMIR 2024)이 직접 선례이자 MRT 설계 템플릿.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date

import numpy as np

from .constants import (
    MAX_NUDGES_PER_DAY,
    MIN_EFFECT_MINUTES,
    OUTDOOR_DAY_LUX,
    PRIMARY_MODEL,
    ShiftType,
    UserProfile,
)
from .light import LightWindow, SleepWindow, intervention_windows, light_series, plan_sleep
from .phase import PhaseResult, estimate_phase


@dataclass
class Nudge:
    at: float                 # 절대시간(h)
    action: str
    message: str
    effect_minutes: float     # 반사실 처치효과 (DLMO 이동, 분)
    shift: ShiftType
    evidence: str = ""        # AASM 권고 번호 등


@dataclass
class NudgePlan:
    nudges: list[Nudge] = field(default_factory=list)
    suppressed: list[str] = field(default_factory=list)  # 발화 안 한 이유 로그

    def by_day(self) -> dict[int, list[Nudge]]:
        out: dict[int, list[Nudge]] = {}
        for n in self.nudges:
            out.setdefault(int(n.at // 24), []).append(n)
        return out


# ─────────────────────────────────────────────────────────────
# 반사실 처치효과
# ─────────────────────────────────────────────────────────────

def _apply(light: np.ndarray, t: np.ndarray, w: LightWindow) -> np.ndarray:
    """개입을 광 시계열에 적용한 반사실 버전을 만든다."""
    out = light.copy()
    mask = (t >= w.start) & (t < w.end)
    if w.action == "bright_light":
        out[mask] = np.maximum(out[mask], 2500.0)
    elif w.action == "blue_blocker":
        out[mask] = out[mask] * 0.10   # ASSUMPTION: 차광안경 투과율
    elif w.action == "blackout":
        out[mask] = 1.0
    return out


def treatment_effect(t: np.ndarray, base_light: np.ndarray, w: LightWindow,
                     base_dlmos: np.ndarray, ic: np.ndarray | None) -> float:
    """
    개입 적용 전후의 DLMO 이동량(분).

    기본 모델(Hannay19) 단독으로 계산한다 — 4모델 전체를 후보마다 돌리면
    연산량이 후보수 × 4배가 되고, Huang 2021 기준 모델 간 차이는
    유의하지 않으므로(Friedman p>0.05) 랭킹 목적에는 불필요하다.

    기저는 한 번만 계산해 재사용하고, 반사실은 기저와 동일한 초기조건에서
    적분한다. 속도 문제만이 아니라 — 개입은 같은 이력 위의 섭동이므로
    동일 초기조건 비교가 올바른 반사실이다.

    ⚠️ 한계: 효과 지표가 'DLMO 이동량'이다. 위상을 옮기는 개입(밝은 빛)에는
       맞지만, 암막·차광처럼 위상이 아니라 수면의 질을 지키는 개입은 이
       지표로 과소평가된다. gate_by_effect 참조.
    """
    cf = estimate_phase(t, _apply(base_light, t, w), models=[PRIMARY_MODEL],
                        initial_conditions={PRIMARY_MODEL: ic} if ic is not None else None
                        ).primary.dlmos
    n = min(len(base_dlmos), len(cf))
    if n == 0:
        return 0.0
    return float(np.mean(cf[:n] - base_dlmos[:n]) * 60.0)


# 위상 이동이 목적이 아닌 개입 — 반사실 게이트를 적용하지 않는다.
# 암막/차광은 DLMO를 옮기려는 것이 아니라 주간수면의 질을 지키는 것이므로
# DLMO 이동량으로 평가하면 항상 0에 가깝게 나와 부당하게 억제된다.
PHASE_SHIFTING_ACTIONS = {"bright_light"}


# ─────────────────────────────────────────────────────────────
# 메시지
# ─────────────────────────────────────────────────────────────
#
# ⚠️ 표현 가드레일 — AASM 2025의 비약물 개입은 전부
#    Conditional / Very low certainty (GRADE 최하위)다.
#    Moderate 등급은 아르모다피닐·모다피닐뿐이며 SHIFT 범위 밖.
#    따라서 "생체리듬 교정"이 아니라 "증상 관리"로 프레이밍한다.

_TEMPLATES = {
    "bright_light": ("근무 전반부입니다. 밝은 곳에서 시간을 보내면 "
                     "졸림이 덜할 수 있어요.", "AASM 2025 권고 2"),
    "blue_blocker": ("퇴근길에 햇빛을 받으면 잠들기 어려워집니다. "
                     "선글라스를 착용해 주세요.", "AASM 2025 권고 19"),
    "blackout": ("잠들기 전 암막을 확인해 주세요. 아침 햇살이 들어오면 "
                 "중간에 깨기 쉽습니다.", "AASM 2025 권고 18 / NIOSH"),
}


def _message(action: str) -> tuple[str, str]:
    return _TEMPLATES.get(action, ("", ""))


# ─────────────────────────────────────────────────────────────
# 플랜 생성
# ─────────────────────────────────────────────────────────────

def build_nudges(roster: list[ShiftType], profile: UserProfile,
                 start_date: date,
                 sleep: list[SleepWindow] | None = None,
                 evaluate_effects: bool = True,
                 t: np.ndarray | None = None,
                 base_light: np.ndarray | None = None,
                 base_res: PhaseResult | None = None) -> NudgePlan:
    """
    근무표 → 넛지 스케줄.

    evaluate_effects=False 로 두면 반사실 시뮬레이션을 건너뛰고
    문헌 상수 기반으로만 발화한다. 콜드스타트 첫 주에 사용한다.

    t/base_light/base_res: 호출자가 이미 계산해둔 값이 있으면 넘겨서
    광 스케줄 생성과 위상 적분(가장 비싼 연산)의 중복 실행을 피한다.
    """
    sleep = sleep if sleep is not None else plan_sleep(roster, profile)
    windows = intervention_windows(roster, profile, start_date, sleep)
    if t is None or base_light is None:
        t, base_light = light_series(roster, profile, start_date, sleep=sleep)

    plan = NudgePlan()
    scored: list[Nudge] = []

    if evaluate_effects and base_res is None:
        base_res = estimate_phase(t, base_light, models=[PRIMARY_MODEL]).primary

    for w in windows:
        day = int(w.start // 24)
        shift = roster[day] if day < len(roster) else ShiftType.OFF

        if evaluate_effects and w.action in PHASE_SHIFTING_ACTIONS:
            eff = abs(treatment_effect(t, base_light, w,
                                       base_res.dlmos, base_res.initial_condition))
            if eff < MIN_EFFECT_MINUTES:
                plan.suppressed.append(
                    f"day{day} {w.action}: 효과 {eff:.1f}분 < 임계 {MIN_EFFECT_MINUTES}분"
                )
                continue
        else:
            eff = float("nan")

        msg, ev = _message(w.action)
        scored.append(Nudge(at=w.start, action=w.action, message=msg,
                            effect_minutes=eff, shift=shift, evidence=ev))

    # 일별 상한 적용 — 효과 큰 것부터
    per_day: dict[int, list[Nudge]] = {}
    for n in scored:
        per_day.setdefault(int(n.at // 24), []).append(n)

    for day, items in per_day.items():
        shift = roster[day] if day < len(roster) else ShiftType.OFF
        cap = MAX_NUDGES_PER_DAY[shift]
        # 미평가(NaN) 개입(암막·차광)은 DLMO 이동량으로 평가받지 않기로 한
        # 설계이므로(PHASE_SHIFTING_ACTIONS 참조) 0점 취급해 밀리면 안 된다.
        # 미평가 항목을 항상 우선 배치하고, 그 다음 측정된 효과 큰 순으로 채운다.
        items.sort(key=lambda x: (
            0 if x.effect_minutes != x.effect_minutes else 1,
            -(x.effect_minutes if x.effect_minutes == x.effect_minutes else 0),
        ))
        plan.nudges.extend(items[:cap])
        for extra in items[cap:]:
            plan.suppressed.append(f"day{day} {extra.action}: 일일 상한({cap}) 초과")

    plan.nudges.sort(key=lambda x: x.at)
    return plan
