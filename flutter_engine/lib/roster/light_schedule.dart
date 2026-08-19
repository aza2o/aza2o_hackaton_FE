/// 근무표 → 광 스케줄 생성. Python `logic/light.py`의 1:1 포팅.
///
/// SHIFT의 구조적 전제: **근무표가 이미 광 스케줄이다.** 센서로 측정하지
/// 않고, 확정된 미래 로스터에서 lux(t)를 연역한다 — 그래서 미래에 대해
/// 계산 가능하다. 센서의 역할은 입력이 아니라 검증(§3-2)이다.
///
/// 검증 상태: 아직 Python 원본 대비 골든 벡터 검증 전. `plan_sleep`은
/// 순수 산술이라 위험도가 낮지만, `sunTimes`(NOAA 근사식)는 삼각함수가
/// 많아 반드시 골든 벡터로 대조할 것 — `circadian_model.dart` 포팅 때도
/// 시간축 부동소수점 문제로 첫 시도가 전부 틀렸었다.
library light_schedule;

import 'dart:math' as math;
import 'constants.dart';

double _deg2rad(double d) => d * math.pi / 180.0;
double _rad2deg(double r) => r * 180.0 / math.pi;

/// 1970-01-01 UTC 기준 정수 일수. Python `date.toordinal()` 차이 계산과
/// 동등한 값을 얻기 위해, 두 날짜의 UTC 자정 간 일수 차이로 계산한다.
int _daysSinceEpoch(DateTime d) {
  final utcMidnight = DateTime.utc(d.year, d.month, d.day);
  return utcMidnight.difference(DateTime.utc(1970, 1, 1)).inDays;
}

// 2000-01-01은 1970-01-01로부터 10957일 뒤 (Python date(2000,1,1).toordinal()
// 기준과 동일한 상대 오프셋을 만들기 위한 상수).
const int _epoch2000OffsetDays = 10957;

/// NOAA 근사식 기반 일출·일몰 (현지 소수 시간). 외부 API 불필요.
/// 극야/백야 구간에서는 (NaN, NaN) 반환.
(double, double) sunTimes(DateTime d, double lat, double lon, {double tzOffset = 9.0}) {
  final n = (_daysSinceEpoch(d) - _epoch2000OffsetDays).toDouble() + 0.0008;
  final jStar = n - lon / 360.0;
  final m = (357.5291 + 0.98560028 * jStar) % 360.0;
  final mr = _deg2rad(m);
  final c = 1.9148 * math.sin(mr) + 0.02 * math.sin(2 * mr) + 0.0003 * math.sin(3 * mr);
  final lam = _deg2rad((m + c + 180 + 102.9372) % 360.0);
  final jTransit = 2451545.0 + jStar + 0.0053 * math.sin(mr) - 0.0069 * math.sin(2 * lam);

  final decl = math.asin(math.sin(lam) * math.sin(_deg2rad(23.4397)));
  final latr = _deg2rad(lat);
  final cosW = (math.sin(_deg2rad(-0.833)) - math.sin(latr) * math.sin(decl)) /
      (math.cos(latr) * math.cos(decl));
  if (cosW < -1.0 || cosW > 1.0) {
    return (double.nan, double.nan);
  }

  final w = _rad2deg(math.acos(cosW));
  final jSet = jTransit + w / 360.0;
  final jRise = jTransit - w / 360.0;

  double toLocal(double j) => ((j - 2451545.0 + 0.5) % 1.0) * 24.0 + tzOffset;

  double wrap24(double h) => ((h % 24.0) + 24.0) % 24.0;
  return (wrap24(toLocal(jRise)), wrap24(toLocal(jSet)));
}

/// 절대시간 tAbs(h)가 해당 날짜의 일출~일몰 사이인지.
bool isDaylight(double tAbs, DateTime start, double lat, double lon) {
  final dayIdx = (tAbs / 24.0).floor();
  final hour = tAbs % 24.0;
  final (rise, set) = sunTimes(start.add(Duration(days: dayIdx)), lat, lon);
  if (rise.isNaN) return false;
  return rise <= hour && hour < set;
}

/// 수면 구간. 절대시간(h), roster 시작일 00:00 기준.
class SleepWindow {
  const SleepWindow(this.start, this.end, this.kind);
  final double start;
  final double end;
  final String kind; // main | prophylactic_nap

  double get duration => end - start;
}

/// 근무표에서 기본 수면 계획을 만든다.
///
/// ⚠️ 최종 권고가 아니라 광 스케줄 생성을 위한 "예상 수면"이다.
///
/// 적용 전략 (AASM 2025 / NIOSH):
///   - Night 전날: 예방적 낮잠(prophylactic nap)
///   - Night 후: 귀가 직후 주간수면
List<SleepWindow> planSleep(List<ShiftType> roster, UserProfile profile) {
  final windows = <SleepWindow>[];
  final t = profile.shiftTimings;

  for (var i = 0; i < roster.length; i++) {
    final s = roster[i];
    final day0 = i * 24.0;
    final nxt = i + 1 < roster.length ? roster[i + 1] : null;
    final prv = i > 0 ? roster[i - 1] : null;

    if (s == ShiftType.night) {
      final endH = t[ShiftType.night]!.end;
      final wakeAt = day0 + 24.0 + endH + profile.commuteMinutes / 60.0;
      windows.add(SleepWindow(wakeAt, wakeAt + 5.5, 'main'));

      if (nxt == ShiftType.night) {
        final on = day0 + 24.0 + t[ShiftType.night]!.start;
        windows.add(SleepWindow(on - 3.0, on - 1.5, 'prophylactic_nap'));
      }
    } else if (s == ShiftType.off && prv == ShiftType.night) {
      // 직전 나이트의 주간수면이 이 날로 이미 넘어와 있음
    } else {
      double bed, wake;
      if (s == ShiftType.day) {
        bed = 22.5;
        wake = t[ShiftType.day]!.start - 1.0;
      } else if (s == ShiftType.evening) {
        bed = 25.5;
        wake = t[ShiftType.evening]!.start - 4.0;
      } else {
        bed = 24.0;
        wake = 8.0;
      }
      windows.add(SleepWindow(day0 + bed, day0 + 24.0 + wake, 'main'));

      if (nxt == ShiftType.night) {
        final on = day0 + 24.0 + t[ShiftType.night]!.start;
        windows.add(SleepWindow(on - 4.0, on - 1.5, 'prophylactic_nap'));
      }
    }
  }

  windows.sort((a, b) => a.start.compareTo(b.start));
  return windows;
}

/// 근무표 → lux(t) 함수.
///
/// 우선순위 (위에서부터 덮어씀):
///   1) 수면 중        → 침실 조도
///   2) 근무 중        → 근무지 실내 조도
///   3) 통근 중        → 일출·일몰 기준 실외/야간
///   4) 그 외 각성 시간 → 실외면 주광, 아니면 가정 조도
double Function(double) buildLightFn(
  List<ShiftType> roster,
  UserProfile profile,
  DateTime startDate, {
  List<SleepWindow>? sleep,
}) {
  final resolvedSleep = sleep ?? planSleep(roster, profile);
  final t = profile.shiftTimings;
  final workLux = indoorLux[profile.workplaceLighting]!;
  final bedLux = bedroomLux[profile.bedroomLighting]!;
  final commute = profile.commuteMinutes / 60.0;

  final workBlocks = <(double, double)>[];
  for (var i = 0; i < roster.length; i++) {
    final s = roster[i];
    if (s == ShiftType.off) continue;
    final timing = t[s]!;
    final on = i * 24.0 + timing.start;
    final off = on + timing.duration;
    workBlocks.add((on, off));
  }

  double lux(double time) {
    for (final w in resolvedSleep) {
      if (w.start <= time && time < w.end) return bedLux;
    }
    for (final (on, off) in workBlocks) {
      if (on <= time && time < off) return workLux;
      if ((on - commute <= time && time < on) || (off <= time && time < off + commute)) {
        return isDaylight(time, startDate, profile.latitude, profile.longitude)
            ? outdoorDayLux
            : outdoorNightLux;
      }
    }
    if (isDaylight(time, startDate, profile.latitude, profile.longitude)) {
      return homeAwakeLux;
    }
    return (time % 24.0) < 23.0 ? homeAwakeLux : outdoorNightLux;
  }

  return lux;
}

/// 모델 입력용 (time, lux) 배열. dt는 시간(h) 단위 스텝.
({List<double> time, List<double> light}) lightSeries(
  List<ShiftType> roster,
  UserProfile profile,
  DateTime startDate, {
  double dt = 0.1,
  List<SleepWindow>? sleep,
}) {
  final fn = buildLightFn(roster, profile, startDate, sleep: sleep);
  final totalHours = roster.length * 24.0;
  final n = (totalHours / dt).round();
  final time = List<double>.generate(n, (i) => i * dt);
  final light = time.map(fn).toList();
  return (time: time, light: light);
}

/// 개입 가능한 광 관련 시간창. 센서 없이 근무표만으로 산출된다.
class LightWindow {
  const LightWindow(this.start, this.end, this.action, this.reason);
  final double start;
  final double end;
  final String action; // blue_blocker | bright_light | blackout
  final String reason;
}

/// AASM 2025 권고 2/17~19에 대응하는 개입 창을 근무표에서 연역한다.
///
/// ⚠️ 해당 권고는 전부 Conditional / Very low certainty다. 카피는
/// "생체리듬 교정"이 아니라 "증상 관리" 수준을 유지할 것.
List<LightWindow> interventionWindows(
  List<ShiftType> roster,
  UserProfile profile,
  DateTime startDate, {
  List<SleepWindow>? sleep,
}) {
  final resolvedSleep = sleep ?? planSleep(roster, profile);
  final t = profile.shiftTimings;
  final out = <LightWindow>[];

  for (var i = 0; i < roster.length; i++) {
    if (roster[i] != ShiftType.night) continue;

    final timing = t[ShiftType.night]!;
    final on = i * 24.0 + timing.start;
    final off = on + timing.duration;

    // 근무 전반부 밝은 빛 — AASM 권고 2
    out.add(LightWindow(on, on + timing.duration / 2.0, 'bright_light', '야간근무 전반부 각성 유지'));

    // 귀가 구간 차광 — AASM 권고 19
    final home = off + profile.commuteMinutes / 60.0;
    final (rise, _) = sunTimes(
      startDate.add(Duration(days: (off / 24.0).floor())),
      profile.latitude,
      profile.longitude,
    );
    if (!rise.isNaN) {
      final sunriseAbs = (off / 24.0).floor() * 24.0 + rise;
      if (sunriseAbs <= home) {
        out.add(LightWindow(
          off,
          home,
          'blue_blocker',
          '일출 ${rise.toStringAsFixed(2)}h — 귀가 중 광노출 차단',
        ));
      }
    }

    // 주간수면 암막 — AASM 권고 18
    for (final w in resolvedSleep) {
      if (w.kind == 'main' && off <= w.start && w.start < off + 6.0) {
        out.add(LightWindow(w.start, w.end, 'blackout', '주간수면 진입 보조'));
        break;
      }
    }
  }

  return out;
}
