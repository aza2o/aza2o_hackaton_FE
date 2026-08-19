"""
Process S — 수면압력, 그리고 각성도 합성.

⚠️ 이 모듈은 Song/Hong 계열(CSS)의 재현이 아니다.
   교과서 Two-Process(Borbély/Daan)의 열화 근사이며, 다음이 다르다.

     | 항목    | 여기(교과서 S)        | Song/Hong (CSS)              |
     |---------|----------------------|------------------------------|
     | 입력    | 수면/각성 이진 타임라인 | 수면패턴 + 광프로파일 + WASO |
     | 파라미터 | 집단 상수 고정        | 교대근무자 대상 적합 추정      |
     | 출력    | 압력 스칼라 시계열     | CSS (에피소드별 충분도)       |
     | 배포    | 의존성 0             | MATLAB ode15s → 백엔드 불가   |

   발표 표현: "Two-Process 기반 각성도 추정, CSS 통합은 로드맵"
   금지 표현: "Song 2023 모델 탑재"

[왜 위상만으로는 부족한가]
  같은 새벽 4시라도 —
    나이트 1일차, 저녁 낮잠 후 출근 → S 낮음 / C 최저점 → 각성도 중간
    나이트 3일차, 낮잠 실패로 20시간 각성 → S·C 동시 최악 → 붕괴
  위상만 보면 두 상황이 동일하게 출력된다.
  즉 Process C 단독으로는 나이트 연속일의 위험 구간을 탐지할 수 없다.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .constants import (
    SE_FLOOR,
    SE_REFERENCE,
    S_LOWER,
    S_UPPER,
    TAU_DECAY,
    TAU_RISE,
)
from .light import SleepWindow


def se_discount(sleep_efficiency: float | None) -> float:
    """
    수면효율 → 감쇠율 할인 계수.

    [문제] 교과서 S는 WASO 90분짜리 6시간 주간수면과 통잠 6시간을 동일 처리한다.
           방향이 나쁘다 — 회복을 과대추정하므로 나이트 연속일 각성도를 실제보다
           낙관적으로 그린다. 위험 구간을 못 잡는 것은 위상만 쓸 때와 같고,
           "각성도를 본다"는 착시만 추가된다.

    [보정] 워치 수면효율로 감쇠율을 할인한다.
           Lee 2025 메타분석: 수면효율 편향 -4.69%. 단 방향이 일관되어
           개인 내 비교에서 상쇄된다.

    ⚠️ 따라서 절대 회복량을 주장하면 안 된다.
       허용: "이번 주간수면은 지난번보다 회복이 덜 됐습니다"
       금지: "6시간 중 4.2시간분만 회복됐습니다"

    ⚠️ ASSUMPTION: 선형 할인과 바닥값은 임의 설정이며 검증되지 않았다.
    """
    if sleep_efficiency is None:
        return 1.0
    return float(np.clip(sleep_efficiency / SE_REFERENCE, SE_FLOOR, 1.0))


@dataclass
class PressureResult:
    time: np.ndarray
    S: np.ndarray
    awake: np.ndarray  # bool mask

    def at(self, t: float) -> float:
        return float(np.interp(t, self.time, self.S))


def simulate_pressure(t: np.ndarray, sleep: list[SleepWindow],
                      sleep_efficiency: dict[int, float] | None = None,
                      s0: float = 0.4) -> PressureResult:
    """
    수면압력 시계열.

    각성 중: S → S_UPPER 로 시상수 TAU_RISE 로 포화
    수면 중: S → S_LOWER 로 시상수 TAU_DECAY 로 감쇠 (수면효율로 할인)

    sleep_efficiency: {sleep window index: 0~1}. None이면 할인 없음.
    """
    dt = float(t[1] - t[0])
    awake = np.ones(len(t), dtype=bool)
    disc = np.ones(len(t))

    for i, w in enumerate(sleep):
        mask = (t >= w.start) & (t < w.end)
        awake[mask] = False
        if sleep_efficiency and i in sleep_efficiency:
            disc[mask] = se_discount(sleep_efficiency[i])

    S = np.empty(len(t))
    s = s0
    for i in range(len(t)):
        if awake[i]:
            s += (S_UPPER - s) * (dt / TAU_RISE)
        else:
            s += (S_LOWER - s) * (dt / TAU_DECAY) * disc[i]
        S[i] = s

    return PressureResult(time=t, S=S, awake=awake)


def alertness(t: np.ndarray, S: np.ndarray, dlmos: np.ndarray,
              w_c: float = 0.5) -> np.ndarray:
    """
    각성도 = -(Process S) + w_c * (Process C 진동)

    Process C는 DLMO에서 추정한 위상으로 코사인 근사한다.
    CBTmin ≈ DLMO + 7h 부근에서 각성도 최저.

    ⚠️ 출력은 임의 스케일의 상대값이다. 절대 각성도 수치를 UI에 노출하지 말 것.
       "지금이 오늘 중 가장 낮은 구간" 같은 상대 표현만 허용된다.
    """
    if len(dlmos) == 0:
        C = np.zeros(len(t))
    else:
        ref = float(dlmos[0]) + 7.0            # CBTmin 근사
        period = 24.0
        if len(dlmos) > 1:
            period = float(np.median(np.diff(dlmos)))
            if not (20.0 < period < 28.0):
                period = 24.0
        C = -np.cos(2 * np.pi * (t - ref) / period)

    a = -S + w_c * C
    rng = a.max() - a.min()
    return (a - a.min()) / rng if rng > 0 else np.zeros_like(a)


def risk_windows(t: np.ndarray, alert: np.ndarray,
                 percentile: float = 15.0) -> list[tuple[float, float]]:
    """각성도 하위 N% 구간을 위험 창으로 반환. 근무 중 넛지 배치 근거."""
    thr = float(np.percentile(alert, percentile))
    low = alert <= thr
    out: list[tuple[float, float]] = []
    start = None
    for i, v in enumerate(low):
        if v and start is None:
            start = t[i]
        elif not v and start is not None:
            if t[i] - start >= 0.5:
                out.append((float(start), float(t[i])))
            start = None
    if start is not None:
        out.append((float(start), float(t[-1])))
    return out
