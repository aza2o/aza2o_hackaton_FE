"""
Process C — 생체시계 위상 추정.

Arcascope/circadian (Python, MIT, v1.0.3) 사용.
논문 저자(Walch·Hannay)가 직접 개발한 패키지이므로 재현성 논쟁이 없다.
→ Dart로 포팅하면 이 논거가 소멸한다. 반드시 Python 백엔드에 둔다.

4모델 병렬은 성능 목적이 아니다.
  Huang 2021: 동일 입력이면 네 모델 간 성능 차이 없음 (Friedman, p>0.05).
  → 목적은 "분산 노출". 단일 모델에 베팅하지 않고 불확실성을 드러내는 것
    자체가 데모 자산이다.

기본 모델은 Hannay19.
  Huang 2021: 활동량 입력 시 오차 120분 미만 피험자 비율이 20%p 우위.
  Hannay 2019: 1,704개 광노출 조건 중 516개(30.28%)에서 단일집단 모델과
  VDP 모델의 DLMO 예측이 1시간 이상 차이. 대부분 저조도 조건, 특히 위상
  지연이 일어나는 저녁 시간대 → 야간근무자의 실내 저조도 환경이 이 구간.
"""

from __future__ import annotations

import warnings
from dataclasses import dataclass

import numpy as np
from circadian.models import Forger99, Hannay19, Hannay19TP, Jewett99

from .constants import ALL_MODELS, DT_HOURS, PRIMARY_MODEL, WARMUP_DAYS

_REGISTRY = {
    "Hannay19": Hannay19,
    "Hannay19TP": Hannay19TP,
    "Forger99": Forger99,
    "Jewett99": Jewett99,
}


@dataclass
class PhaseResult:
    model: str
    dlmos: np.ndarray        # 절대시간(h)
    cbt_min: np.ndarray      # DLMO + 약 7h 근사
    equilibrated: bool       # equilibrate 수렴 여부
    initial_condition: np.ndarray | None = None  # 반사실 재사용용

    def dlmo_clock(self) -> list[float]:
        """DLMO를 벽시계 시각(0~24)으로."""
        return [float(d % 24.0) for d in self.dlmos]


@dataclass
class PhaseEnsemble:
    """4모델 결과 묶음. 분산 자체가 산출물이다."""
    results: dict[str, PhaseResult]
    time: np.ndarray
    light: np.ndarray

    @property
    def primary(self) -> PhaseResult:
        return self.results[PRIMARY_MODEL]

    def spread_hours(self) -> list[float]:
        """
        같은 날 DLMO에 대한 모델 간 최대-최소 폭(h).
        이 값이 크면 권고 신뢰구간을 넓게 표시해야 한다.

        배열 인덱스로 정렬하면 안 된다 — 모델마다 초기화 직후 경계에서
        검출되는 DLMO 개수가 다를 수 있어(예: Hannay19가 워밍업 직후
        스퓨리어스 크로싱을 하나 더 잡는 경우) 인덱스가 하루씩 밀리면
        서로 다른 날짜의 DLMO를 비교하게 된다. 대신 24h 날짜 버킷으로
        맞춰서, 모든 모델이 공통으로 검출한 날짜만 비교한다.
        """
        by_day: list[dict[int, float]] = []
        for r in self.results.values():
            d: dict[int, float] = {}
            for dl in r.dlmos:
                d[int(dl // 24)] = float(dl)  # 같은 날 중복 검출 시 마지막 값 사용
            by_day.append(d)
        if not by_day:
            return []
        common_days = set.intersection(*(set(d) for d in by_day))
        out = []
        for day in sorted(common_days):
            vals = [d[day] for d in by_day]
            out.append(max(vals) - min(vals))
        return out

    def summary(self) -> dict:
        return {
            "primary_model": PRIMARY_MODEL,
            "dlmo_clock": self.primary.dlmo_clock(),
            "spread_hours": self.spread_hours(),
            "models": {
                k: {"dlmo_clock": v.dlmo_clock(), "equilibrated": v.equilibrated}
                for k, v in self.results.items()
            },
        }


def _run_one(name: str, t: np.ndarray, light: np.ndarray,
             ic: np.ndarray | None = None) -> PhaseResult:
    model = _REGISTRY[name]()

    if ic is not None:
        # 반사실 실행: 기저와 동일한 초기조건을 재사용한다.
        # 속도 때문만이 아니라, 개입은 같은 이력 위의 섭동이므로
        # 동일 초기조건에서 비교하는 것이 올바른 반사실이다.
        equilibrated = True
    else:
        warm = min(int(WARMUP_DAYS * 24 / DT_HOURS), len(t))
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            ic = model.equilibrate(t[:warm], light[:warm], num_loops=15)
            equilibrated = not any(
                "did not equilibrate" in str(w.message) for w in caught
            )

    traj = model.integrate(t, initial_condition=ic, input=light)
    dlmos = np.asarray(model.dlmos(traj))
    dlmos = dlmos[dlmos >= 0.0]  # 워밍업 이전의 음수 시각 제거

    return PhaseResult(
        model=name,
        dlmos=dlmos,
        cbt_min=dlmos + 7.0,  # 근사. 개인차 있음 — 절대값 주장 금지
        equilibrated=equilibrated,
        initial_condition=ic,
    )


def estimate_phase(t: np.ndarray, light: np.ndarray,
                   models: list[str] | None = None,
                   initial_conditions: dict[str, np.ndarray] | None = None
                   ) -> PhaseEnsemble:
    """
    광 시계열 → 위상 앙상블.

    [초기조건] PMC12694990이 지적했듯 정확도가 초기화 방식·기록기간에 좌우된다.
      상태 이월(state carry-over) 대신 매번 재적분한다. 느리지만 결정론적이며,
      같은 입력에 항상 같은 출력이 나온다. 데모 중 값이 이상할 때 원인 추적이
      가능한 것이 최적화보다 중요하다.
    """
    names = models or ALL_MODELS
    ics = initial_conditions or {}
    return PhaseEnsemble(
        results={n: _run_one(n, t, light, ics.get(n)) for n in names},
        time=t,
        light=light,
    )


def scale_steps_to_activity(steps: np.ndarray) -> np.ndarray:
    """
    Apple 걸음 수 → 액티그래프 활동 카운트 근사.

    ⚠️ 단위가 다르므로 스케일링 없이 넣으면 안 된다.
       Huang 2021은 30/mean(steps)를 사용했다.

    [주의] Huang 2021 결론 3: 교대근무자 표본에서는 활동 기반 예측이
      광 기반보다 유의하게 우수. 손목 광 데이터가 부실해도 활동량으로
      대체 가능하며 오히려 더 정확하다.
    """
    steps = np.asarray(steps, dtype=float)
    m = float(np.mean(steps[steps > 0])) if np.any(steps > 0) else 1.0
    return steps * (30.0 / m)
