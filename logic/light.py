"""
근무표 → 광 스케줄 생성.

SHIFT의 구조적 전제: **근무표가 이미 광 스케줄이다.**

기존 선행연구(Cheng 2021, Huang 2021)가 액티그래프로 광을 "측정"한 이유는
사후 분석이라 미래 스케줄이 없었기 때문이다. 관측이 유일한 수단이었다.
SHIFT는 확정된 미래 근무표를 갖고 있으므로 광 프로파일을 "생성"할 수 있다.
이는 열등한 대체재가 아니라 다른 종류의 입력이다.

센서의 역할은 입력이 아니라 검증으로 재정의된다 (verify.py 참조).
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import date, timedelta

import numpy as np

from .constants import (
    BEDROOM_LUX,
    HOME_AWAKE_LUX,
    INDOOR_LUX,
    OUTDOOR_DAY_LUX,
    OUTDOOR_NIGHT_LUX,
    ShiftType,
    UserProfile,
)


# ─────────────────────────────────────────────────────────────
# 일출 / 일몰
# ─────────────────────────────────────────────────────────────

def sun_times(d: date, lat: float, lon: float, tz_offset: float = 9.0
              ) -> tuple[float, float]:
    """
    NOAA 근사식 기반 일출·일몰 (현지 소수 시간).

    외부 API 불필요 — 날짜와 위경도만으로 계산된다.
    극야/백야 구간에서는 (nan, nan) 반환.
    """
    n = d.toordinal() - date(2000, 1, 1).toordinal() + 0.0008
    J_star = n - lon / 360.0
    M = (357.5291 + 0.98560028 * J_star) % 360.0
    Mr = math.radians(M)
    C = 1.9148 * math.sin(Mr) + 0.02 * math.sin(2 * Mr) + 0.0003 * math.sin(3 * Mr)
    lam = math.radians((M + C + 180 + 102.9372) % 360.0)
    J_transit = 2451545.0 + J_star + 0.0053 * math.sin(Mr) - 0.0069 * math.sin(2 * lam)

    decl = math.asin(math.sin(lam) * math.sin(math.radians(23.4397)))
    latr = math.radians(lat)
    cos_w = (math.sin(math.radians(-0.833)) - math.sin(latr) * math.sin(decl)) / (
        math.cos(latr) * math.cos(decl)
    )
    if not -1.0 <= cos_w <= 1.0:
        return float("nan"), float("nan")

    w = math.degrees(math.acos(cos_w))
    j_set = J_transit + w / 360.0
    j_rise = J_transit - w / 360.0

    def to_local(j: float) -> float:
        return ((j - 2451545.0 + 0.5) % 1.0) * 24.0 + tz_offset

    return to_local(j_rise) % 24.0, to_local(j_set) % 24.0


def is_daylight(t_abs: float, start: date, lat: float, lon: float) -> bool:
    """절대시간 t_abs(h)가 해당 날짜의 일출~일몰 사이인지."""
    day_idx = int(t_abs // 24)
    hour = t_abs % 24
    rise, set_ = sun_times(start + timedelta(days=day_idx), lat, lon)
    if math.isnan(rise):
        return False
    return rise <= hour < set_


# ─────────────────────────────────────────────────────────────
# 수면 계획 (광 스케줄의 전제)
# ─────────────────────────────────────────────────────────────

@dataclass
class SleepWindow:
    """수면 구간. 절대시간(h), roster 시작일 00:00 기준."""
    start: float
    end: float
    kind: str  # main | prophylactic_nap | strategic_nap

    @property
    def duration(self) -> float:
        return self.end - self.start


def plan_sleep(roster: list[ShiftType], profile: UserProfile) -> list[SleepWindow]:
    """
    근무표에서 기본 수면 계획을 만든다.

    ⚠️ 이것은 최종 권고가 아니라 광 스케줄 생성을 위한 "예상 수면"이다.
       최종 권고는 위상 추정 결과를 반영해 phase.py 이후 단계에서 확정된다.

    적용 전략 (AASM 2025 / NIOSH):
      - Night 전날: 예방적 낮잠(prophylactic nap) — AASM 권고 5
      - Night 후: 귀가 직후 주간수면 — NIOSH
      - Night 연속: split sleep — Song 2023의 'adaptive circadian split sleep'
    """
    windows: list[SleepWindow] = []
    T = profile.shift_timings

    for i, s in enumerate(roster):
        day0 = i * 24.0
        nxt = roster[i + 1] if i + 1 < len(roster) else None
        prv = roster[i - 1] if i > 0 else None

        if s == ShiftType.NIGHT:
            # 나이트 후 주간수면: 퇴근 + 통근시간부터
            end_h = T[ShiftType.NIGHT].end
            wake_at = day0 + 24.0 + end_h + profile.commute_minutes / 60.0
            windows.append(SleepWindow(wake_at, wake_at + 5.5, "main"))

            if nxt == ShiftType.NIGHT:
                # 연속 나이트: 출근 전 예방적 낮잠 (split sleep)
                on = day0 + 24.0 + T[ShiftType.NIGHT].start
                windows.append(SleepWindow(on - 3.0, on - 1.5, "prophylactic_nap"))

        elif s == ShiftType.OFF and prv == ShiftType.NIGHT:
            pass  # 직전 나이트의 주간수면이 이 날로 이미 넘어와 있음

        else:
            if s == ShiftType.DAY:
                bed, wake = 22.5, T[ShiftType.DAY].start - 1.0
            elif s == ShiftType.EVENING:
                bed, wake = 25.5, T[ShiftType.EVENING].start - 4.0
            else:  # OFF
                bed, wake = 24.0, 8.0
            windows.append(SleepWindow(day0 + bed, day0 + 24.0 + wake, "main"))

            if nxt == ShiftType.NIGHT:
                on = day0 + 24.0 + T[ShiftType.NIGHT].start
                windows.append(SleepWindow(on - 4.0, on - 1.5, "prophylactic_nap"))

    return sorted(windows, key=lambda w: w.start)


# ─────────────────────────────────────────────────────────────
# 광 스케줄 생성
# ─────────────────────────────────────────────────────────────

def build_light_fn(roster: list[ShiftType], profile: UserProfile,
                   start_date: date, sleep: list[SleepWindow] | None = None):
    """
    근무표 → lux(t) callable.

    ⚠️ circadian v1.0.3의 LightSchedule.ShiftWork() / SlamShift()는
       타입 불일치로 동작하지 않는다. 우회로 raw Python callable을
       LightSchedule()로 감싼다. 이 우회는 여기 한 곳에만 존재해야 한다.

    우선순위 (위에서부터 덮어씀):
      1) 수면 중        → 침실 조도 (암막 설정에 좌우)
      2) 근무 중        → 근무지 실내 조도
      3) 통근 중        → 일출·일몰 기준 실외/야간
      4) 그 외 각성 시간 → 실외면 주광, 아니면 가정 조도
    """
    sleep = sleep if sleep is not None else plan_sleep(roster, profile)
    T = profile.shift_timings
    work_lux = INDOOR_LUX[profile.workplace_lighting]
    bed_lux = BEDROOM_LUX[profile.bedroom_lighting]
    commute = profile.commute_minutes / 60.0

    work_blocks: list[tuple[float, float, ShiftType]] = []
    for i, s in enumerate(roster):
        if s == ShiftType.OFF:
            continue
        t = T[s]
        on = i * 24.0 + t.start
        off = on + t.duration
        work_blocks.append((on, off, s))

    def lux(t: float) -> float:
        for w in sleep:
            if w.start <= t < w.end:
                return bed_lux

        for on, off, _s in work_blocks:
            if on <= t < off:
                return work_lux
            if on - commute <= t < on or off <= t < off + commute:
                return (OUTDOOR_DAY_LUX
                        if is_daylight(t, start_date, profile.latitude, profile.longitude)
                        else OUTDOOR_NIGHT_LUX)

        if is_daylight(t, start_date, profile.latitude, profile.longitude):
            return HOME_AWAKE_LUX
        return HOME_AWAKE_LUX if (t % 24) < 23.0 else OUTDOOR_NIGHT_LUX

    return lux


def light_series(roster: list[ShiftType], profile: UserProfile,
                 start_date: date, dt: float = 0.1,
                 sleep: list[SleepWindow] | None = None
                 ) -> tuple[np.ndarray, np.ndarray]:
    """모델 입력용 (time, lux) 배열."""
    fn = build_light_fn(roster, profile, start_date, sleep)
    t = np.arange(0.0, len(roster) * 24.0, dt)
    return t, np.array([fn(x) for x in t])


# ─────────────────────────────────────────────────────────────
# 차광 / 광노출 개입 창
# ─────────────────────────────────────────────────────────────

@dataclass
class LightWindow:
    """개입 가능한 광 관련 시간창. 센서 없이 근무표만으로 산출된다."""
    start: float
    end: float
    action: str      # blue_blocker | bright_light | blackout
    reason: str


def intervention_windows(roster: list[ShiftType], profile: UserProfile,
                         start_date: date,
                         sleep: list[SleepWindow] | None = None
                         ) -> list[LightWindow]:
    """
    AASM 2025 권고 2 / 17~19 에 대응하는 개입 창을 근무표에서 연역한다.

    ⚠️ 해당 권고는 모두 Conditional / Very low certainty (GRADE 최하위).
       Moderate 등급은 아르모다피닐·모다피닐뿐이며 SHIFT 범위 밖이다.
       따라서 카피는 "생체리듬 교정"이 아니라 "증상 관리" 수준을 유지한다.
    """
    sleep = sleep if sleep is not None else plan_sleep(roster, profile)
    T = profile.shift_timings
    out: list[LightWindow] = []

    for i, s in enumerate(roster):
        if s != ShiftType.NIGHT:
            continue

        on = i * 24.0 + T[ShiftType.NIGHT].start
        off = on + T[ShiftType.NIGHT].duration

        # 근무 전반부 밝은 빛 — AASM 권고 2
        out.append(LightWindow(on, on + T[ShiftType.NIGHT].duration / 2.0,
                               "bright_light", "야간근무 전반부 각성 유지"))

        # 귀가 구간 차광 — AASM 권고 19
        home = off + profile.commute_minutes / 60.0
        rise, _ = sun_times(start_date + timedelta(days=int(off // 24)),
                            profile.latitude, profile.longitude)
        if not math.isnan(rise):
            sunrise_abs = (off // 24) * 24.0 + rise
            if sunrise_abs <= home:  # 퇴근 시점에 이미 해가 떠 있음
                out.append(LightWindow(off, home, "blue_blocker",
                                       f"일출 {rise:.2f}h — 귀가 중 광노출 차단"))

        # 주간수면 암막 — AASM 권고 18
        for w in sleep:
            if w.kind == "main" and off <= w.start < off + 6.0:
                out.append(LightWindow(w.start, w.end, "blackout", "주간수면 진입 보조"))
                break

    return out
