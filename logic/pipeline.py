"""
전체 파이프라인 오케스트레이션.

  근무표 + 온보딩 프로필
      ↓ light.py      근무표 → 광 스케줄 (센서 아님, 연역)
      ↓ phase.py      4모델 병렬 → DLMO
      ↓ pressure.py   Process S → 각성도
      ↓ nudge.py      반사실 처치효과 → 넛지 랭킹
      ↓ plot.py       PNG
  플랜

재적분 방식이라 같은 입력 → 같은 출력이 보장된다. 따라서 입력 해시를
키로 캐싱하면 데모 중 두 번째 호출부터는 즉시 응답한다.
발표장 네트워크가 느려도 안전하다.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass
from datetime import date

import numpy as np

from .constants import DT_HOURS, ShiftType, UserProfile
from .light import light_series, plan_sleep
from .nudge import NudgePlan, build_nudges
from .phase import PhaseEnsemble, estimate_phase
from .plot import actogram, alertness_curve, spread_chart
from .pressure import alertness, risk_windows, simulate_pressure


@dataclass
class Plan:
    roster: list[str]
    start_date: str
    sleep: list[dict]
    dlmo_clock: list[float]
    model_spread_hours: list[float]
    risk_windows: list[tuple[float, float]]
    nudges: list[dict]
    suppressed: list[str]
    warnings: list[str]

    def to_dict(self) -> dict:
        return asdict(self)


_CACHE: dict[str, tuple[Plan, dict]] = {}


def cache_key(roster: list[ShiftType], profile: UserProfile, start: date,
              sleep_efficiency: dict[int, float] | None) -> str:
    payload = {
        "roster": [s.value for s in roster],
        "start": start.isoformat(),
        "profile": {
            "timings": {k.value: [v.start, v.end]
                        for k, v in profile.shift_timings.items()},
            "workplace": profile.workplace_lighting,
            "bedroom": profile.bedroom_lighting,
            "commute": profile.commute_minutes,
            "lat": profile.latitude,
            "lon": profile.longitude,
        },
        "se": sleep_efficiency or {},
    }
    return hashlib.sha256(
        json.dumps(payload, sort_keys=True).encode()
    ).hexdigest()[:16]


def run(roster: list[ShiftType], profile: UserProfile, start_date: date,
        sleep_efficiency: dict[int, float] | None = None,
        evaluate_effects: bool = True,
        render: bool = True,
        use_cache: bool = True) -> tuple[Plan, dict]:
    """
    전체 실행. (Plan, images) 반환.

    evaluate_effects=False → 반사실 시뮬레이션 생략, 문헌 상수 기반 발화만.
      콜드스타트 첫 주에 사용한다. 최소 기록기간 요구는 PMC12694990이
      정확도가 초기화 방식·기록기간에 좌우된다고 명시한 데 근거한다.
    """
    key = cache_key(roster, profile, start_date, sleep_efficiency)
    if use_cache and key in _CACHE:
        return _CACHE[key]

    warns: list[str] = []

    sleep = plan_sleep(roster, profile)
    t, light = light_series(roster, profile, start_date, dt=DT_HOURS, sleep=sleep)

    ensemble: PhaseEnsemble = estimate_phase(t, light)
    for name, res in ensemble.results.items():
        if not res.equilibrated:
            warns.append(f"{name}: equilibrate 미수렴 — 위상 추정 신뢰도 낮음")

    spread = ensemble.spread_hours()
    if spread and max(spread) > 1.0:
        warns.append(
            f"모델 간 DLMO 최대 편차 {max(spread):.2f}h — 권고 신뢰구간을 넓게 표시할 것"
        )

    pres = simulate_pressure(t, sleep, sleep_efficiency)
    alert = alertness(t, pres.S, ensemble.primary.dlmos)
    risks = risk_windows(t, alert)

    plan = build_nudges(roster, profile, start_date, sleep=sleep,
                        evaluate_effects=evaluate_effects,
                        t=t, base_light=light,
                        base_res=ensemble.primary if evaluate_effects else None)

    images: dict = {}
    if render:
        images = {
            "actogram": actogram(t, light, ensemble),
            "alertness": alertness_curve(t, alert, risks),
            "spread": spread_chart(ensemble),
        }

    result = Plan(
        roster=[s.value for s in roster],
        start_date=start_date.isoformat(),
        sleep=[{"start": w.start, "end": w.end, "kind": w.kind} for w in sleep],
        dlmo_clock=ensemble.primary.dlmo_clock(),
        model_spread_hours=spread,
        risk_windows=risks,
        nudges=[{
            "at": n.at,
            "action": n.action,
            "message": n.message,
            "effect_minutes": (None if n.effect_minutes != n.effect_minutes
                               else round(n.effect_minutes, 1)),
            "shift": n.shift.value,
            "evidence": n.evidence,
        } for n in plan.nudges],
        suppressed=plan.suppressed,
        warnings=warns,
    )

    _CACHE[key] = (result, images)
    return result, images


def parse_roster(s: str) -> list[ShiftType]:
    """'DDEENNOO' → [D, D, E, E, N, N, O, O]"""
    return [ShiftType(c.upper()) for c in s if c.upper() in "DENO"]
