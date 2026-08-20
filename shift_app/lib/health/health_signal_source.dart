// 헬스 데이터 어댑터 계약. `SHIFT_개발기획서.md` §6-4를 그대로 옮긴 것.
//
// [IosHealthSource]·[AndroidHealthSource]를 구현했지만, iOS는 Xcode HealthKit
// Capability 설정과 실기기 빌드가, Android는 Health Connect 앱 설치와 실기기가
// 필요해 이 세션에서는 둘 다 동작을 검증할 수 없다
// (`docs/SHIFT_프론트엔드_구현체크리스트.md` §1 참고). 검증 전까지는
// [DemoHealthSource]로 화면·분기 로직을 계속 확인한다.

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:health/health.dart' as hk;

import '../state/app_state.dart';

class DateRange {
  const DateRange(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

class HealthSleepSession {
  const HealthSleepSession(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

class DaylightSeries {
  const DaylightSeries(this.points);
  final List<(DateTime, double)> points; // (시각, lux 근사)
}

class HrvSeries {
  const HrvSeries(this.points);
  final List<(DateTime, double)>
  points; // 개인 내 z-score. 원시 SDNN/RMSSD 금지(§6-3-f)
}

class HeartRateSeries {
  const HeartRateSeries(this.points);
  final List<(DateTime, double)> points; // bpm
}

enum HrvMetric { sdnn, rmssd, none }

class HealthCapabilities {
  const HealthCapabilities({
    required this.hasDaylight,
    required this.canVerifyPermission,
    required this.maxHistory,
    required this.hrvMetric,
  });

  final bool hasDaylight;
  final bool canVerifyPermission; // iOS = false (§6-3-c, 권한 거부 여부를 앱에 안 알려줌)
  final Duration maxHistory; // Android Health Connect 기본 30일
  final HrvMetric hrvMetric;
}

abstract class HealthSignalSource {
  HealthCapabilities get capabilities;

  /// 온보딩 등 첫 진입 시 한 번 호출한다. 거부돼도 예외를 던지지 않는다 —
  /// 이후 조회는 §6-3-c에 따라 빈 결과로만 드러난다.
  Future<bool> requestAuthorization();

  /// iOS: 세션 스티칭 후 반환 / Android: SleepSessionRecord 정규화 + dedup
  Future<List<HealthSleepSession>> sleepSessions(DateRange range);

  /// null = 이 기기가 제공하지 않음 (Android는 항상 null)
  Future<DaylightSeries?> daylight(DateRange range);

  /// 원시값이 아닌 개인 내 z-score. 플랫폼별 정규화는 구현체 책임
  Future<HrvSeries?> hrvNormalized(DateRange range);

  Future<HeartRateSeries?> restingHeartRate(DateRange range);
}

/// 플랫폼 건강 데이터를 날짜별 한 행으로 합쳐 앱의 공통 저장소에 넣는다.
/// 이후 넛지·그래프·AI·피부 루틴은 모두 이 동일한 데이터를 읽는다.
Future<List<SyncedHealthMetric>> syncHealthMetrics(
  HealthSignalSource source, {
  int days = 14,
  bool requestAuthorization = false,
}) async {
  if (requestAuthorization && !await source.requestAuthorization()) {
    return const [];
  }
  final end = DateTime.now();
  final range = DateRange(end.subtract(Duration(days: days + 1)), end);
  final results = await Future.wait<Object?>([
    source.sleepSessions(range),
    source.hrvNormalized(range),
    source.restingHeartRate(range),
  ]);
  final sessions = results[0] as List<HealthSleepSession>;
  final hrv = results[1] as HrvSeries?;
  final heartRate = results[2] as HeartRateSeries?;

  String dayKey(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  final hrvByDay = <String, double>{
    for (final point in hrv?.points ?? const <(DateTime, double)>[])
      dayKey(point.$1): point.$2,
  };
  final heartRateByDay = <String, double>{
    for (final point in heartRate?.points ?? const <(DateTime, double)>[])
      dayKey(point.$1): point.$2,
  };
  sessions.sort((a, b) => a.end.compareTo(b.end));
  final metrics = [
    for (final session in sessions)
      SyncedHealthMetric(
        date: DateTime(session.end.year, session.end.month, session.end.day),
        sleepStart: session.start,
        sleepEnd: session.end,
        sleepMinutes: session.end.difference(session.start).inMinutes,
        hrvZ: hrvByDay[dayKey(session.end)],
        restingHeartRate: heartRateByDay[dayKey(session.end)],
        source: source.runtimeType.toString(),
      ),
  ];
  AppState.instance.replaceSyncedHealthMetrics(metrics);
  return metrics;
}

/// 실기기 연동 전까지 쓰는 데모 구현. [hasData]를 false로 두면 온보딩의
/// "최근 7일치 데이터 없음" 안내 분기를 그대로 재현할 수 있다.
class DemoHealthSource implements HealthSignalSource {
  const DemoHealthSource({this.hasData = true});

  final bool hasData;

  // 월간 데모 로스터(D-D-E-E-N-N-O-O-D-E-N-O)와 같은 순서다.
  // 날짜를 seed로 사용해 재실행해도 값은 유지하되, 매일 완전히 같지는 않다.
  static const _sleepAnchors = [
    (22, 42, 410),
    (22, 58, 392),
    (0, 38, 432),
    (0, 57, 408),
    (8, 34, 375),
    (8, 52, 348),
    (9, 8, 402),
    (23, 48, 478),
    (22, 47, 421),
    (0, 44, 416),
    (8, 41, 363),
    (23, 56, 462),
  ];
  static const _hrvAnchors = [
    -0.10,
    -0.25,
    -0.18,
    -0.38,
    -0.58,
    -0.82,
    -0.45,
    0.28,
    0.04,
    -0.22,
    -0.67,
    0.21,
  ];
  static const _heartRateAnchors = [
    63.0,
    64.0,
    64.0,
    66.0,
    68.0,
    70.0,
    67.0,
    61.0,
    62.0,
    65.0,
    69.0,
    61.0,
  ];

  static int _patternIndex(DateTime day) =>
      (day.day - 1) % _sleepAnchors.length;
  static int _dateSeed(DateTime day, int salt) =>
      day.year * 10000 + day.month * 100 + day.day + salt;

  @override
  HealthCapabilities get capabilities => const HealthCapabilities(
    hasDaylight: false,
    canVerifyPermission: false,
    maxHistory: Duration(days: 3650),
    hrvMetric: HrvMetric.none,
  );

  @override
  Future<bool> requestAuthorization() async => true;

  @override
  Future<List<HealthSleepSession>> sleepSessions(DateRange range) async {
    if (!hasData) return const [];
    final sessions = <HealthSleepSession>[];
    var day = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    ).subtract(const Duration(days: 1));
    final lastDay = DateTime(range.end.year, range.end.month, range.end.day);
    while (!day.isAfter(lastDay)) {
      final random = math.Random(_dateSeed(day, 1709));
      final anchor = _sleepAnchors[_patternIndex(day)];
      final bedtimeJitter = random.nextInt(25) - 12;
      final durationJitter = random.nextInt(31) - 15;
      final sleepMinutes = anchor.$3 + durationJitter;
      final bedtime = day.add(
        Duration(hours: anchor.$1, minutes: anchor.$2 + bedtimeJitter),
      );
      final end = bedtime.add(Duration(minutes: sleepMinutes));
      if (end.isAfter(range.start) && bedtime.isBefore(range.end)) {
        sessions.add(HealthSleepSession(bedtime, end));
      }
      day = day.add(const Duration(days: 1));
    }
    return sessions;
  }

  @override
  Future<DaylightSeries?> daylight(DateRange range) async => null;

  @override
  Future<HrvSeries?> hrvNormalized(DateRange range) async {
    if (!hasData) return null;
    final points = <(DateTime, double)>[];
    var day = DateTime(range.start.year, range.start.month, range.start.day);
    final lastDay = DateTime(range.end.year, range.end.month, range.end.day);
    while (!day.isAfter(lastDay)) {
      final random = math.Random(_dateSeed(day, 3571));
      final anchor = _hrvAnchors[_patternIndex(day)];
      final value = anchor + (random.nextDouble() - 0.5) * 0.16;
      final measuredAt = day.add(const Duration(hours: 7, minutes: 30));
      if (measuredAt.isAfter(range.start) && measuredAt.isBefore(range.end)) {
        points.add((measuredAt, value));
      }
      day = day.add(const Duration(days: 1));
    }
    return HrvSeries(points);
  }

  @override
  Future<HeartRateSeries?> restingHeartRate(DateRange range) async {
    if (!hasData) return null;
    final points = <(DateTime, double)>[];
    var day = DateTime(range.start.year, range.start.month, range.start.day);
    final lastDay = DateTime(range.end.year, range.end.month, range.end.day);
    while (!day.isAfter(lastDay)) {
      final random = math.Random(_dateSeed(day, 6427));
      final anchor = _heartRateAnchors[_patternIndex(day)];
      final value = anchor + random.nextInt(3) - 1;
      final measuredAt = day.add(const Duration(hours: 7, minutes: 35));
      if (measuredAt.isAfter(range.start) && measuredAt.isBefore(range.end)) {
        points.add((measuredAt, value));
      }
      day = day.add(const Duration(days: 1));
    }
    return HeartRateSeries(points);
  }
}

/// 로그인 시 Supabase에서 내려받아 로컬에 캐시한 건강 지표를 제공한다.
/// 서버 데이터가 비어 있으면 시연이 중단되지 않도록 기존 데모 소스로 폴백한다.
class SyncedHealthSource implements HealthSignalSource {
  const SyncedHealthSource();

  static const _fallback = DemoHealthSource();

  @override
  HealthCapabilities get capabilities => _fallback.capabilities;

  @override
  Future<bool> requestAuthorization() async => true;

  List<SyncedHealthMetric> _within(DateRange range) => AppState
      .instance
      .syncedHealthMetrics
      .where(
        (metric) =>
            metric.sleepEnd.isAfter(range.start) &&
            metric.sleepStart.isBefore(range.end),
      )
      .toList();

  @override
  Future<List<HealthSleepSession>> sleepSessions(DateRange range) async {
    final metrics = _within(range);
    if (metrics.isEmpty) return _fallback.sleepSessions(range);
    return [
      for (final metric in metrics)
        HealthSleepSession(metric.sleepStart, metric.sleepEnd),
    ];
  }

  @override
  Future<DaylightSeries?> daylight(DateRange range) async => null;

  @override
  Future<HrvSeries?> hrvNormalized(DateRange range) async {
    final metrics = _within(range).where((metric) => metric.hrvZ != null);
    if (metrics.isEmpty) return _fallback.hrvNormalized(range);
    return HrvSeries([
      for (final metric in metrics) (metric.sleepEnd, metric.hrvZ!),
    ]);
  }

  @override
  Future<HeartRateSeries?> restingHeartRate(DateRange range) async {
    final metrics = _within(range)
        .where((metric) => metric.restingHeartRate != null);
    if (metrics.isEmpty) return _fallback.restingHeartRate(range);
    return HeartRateSeries([
      for (final metric in metrics) (metric.sleepEnd, metric.restingHeartRate!),
    ]);
  }
}

// iOS에서 "asleep"으로 셀 카테고리 값. SLEEP_IN_BED·SLEEP_AWAKE는 제외한다
// (§6-3-a: 침대에 있음/깨어있음은 수면 세션이 아니다).
const _iosAsleepTypes = [
  hk.HealthDataType.SLEEP_ASLEEP,
  hk.HealthDataType.SLEEP_DEEP,
  hk.HealthDataType.SLEEP_LIGHT,
  hk.HealthDataType.SLEEP_REM,
];

// 세션 스티칭 간격 임계값. 문헌 근거 없는 추정값이다 — ASSUMPTION
// (`docs/SHIFT_프론트엔드_구현체크리스트.md` §1 항목 3 참고).
const _sessionStitchGap = Duration(minutes: 30);

// (시각, 값) 시계열로 정렬해 반환 — HRV·안정시 심박 조회에 공통으로 쓴다.
Future<List<(DateTime, double)>> _fetchNumericSeries(
  hk.Health health,
  hk.HealthDataType type,
  DateRange range,
) async {
  final points = await health.getHealthDataFromTypes(
    types: [type],
    startTime: range.start,
    endTime: range.end,
  );
  return points
      .map(
        (p) => (
          p.dateFrom,
          (p.value as hk.NumericHealthValue).numericValue.toDouble(),
        ),
      )
      .toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
}

// 원시 HRV(SDNN/RMSSD)를 인터페이스 밖으로 내보내지 않기 위한 개인 내
// z-score 변환(§6-3-f). 조회 구간 자체를 베이스라인으로 쓰는 건 ASSUMPTION —
// 별도 베이스라인 창을 요구하는 문헌 근거는 없었다.
List<(DateTime, double)> _personalZScore(List<(DateTime, double)> raw) {
  final mean = raw.map((e) => e.$2).reduce((a, b) => a + b) / raw.length;
  final variance =
      raw.map((e) => math.pow(e.$2 - mean, 2)).reduce((a, b) => a + b) /
      raw.length;
  final stddev = math.sqrt(variance);
  if (stddev == 0) return raw.map((e) => (e.$1, 0.0)).toList();
  return raw.map((e) => (e.$1, (e.$2 - mean) / stddev)).toList();
}

/// HealthKit 실기기 어댑터. `TimeInDaylight`만 `health` 패키지에 타입이 없어
/// Swift `MethodChannel`(`shift/health_daylight`, `AppDelegate.swift`)로 조회한다
/// (§7-1). 나머지 신호는 `health` 패키지를 그대로 쓴다.
class IosHealthSource implements HealthSignalSource {
  IosHealthSource({hk.Health? health}) : _health = health ?? hk.Health();

  final hk.Health _health;
  static const _daylightChannel = MethodChannel('shift/health_daylight');
  bool _configured = false;

  @override
  HealthCapabilities get capabilities => const HealthCapabilities(
    hasDaylight: true,
    canVerifyPermission: false, // §6-3-c: 권한 거부 여부를 앱에 알리지 않는다
    maxHistory: Duration(days: 36500), // §6-3-d: 권한만 있으면 과거 전체를 읽는다
    hrvMetric: HrvMetric.sdnn,
  );

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<bool> requestAuthorization() async {
    await _ensureConfigured();
    return _health.requestAuthorization([
      ..._iosAsleepTypes,
      hk.HealthDataType.HEART_RATE_VARIABILITY_SDNN,
      hk.HealthDataType.RESTING_HEART_RATE,
    ]);
  }

  @override
  Future<List<HealthSleepSession>> sleepSessions(DateRange range) async {
    await _ensureConfigured();
    final points = await _health.getHealthDataFromTypes(
      types: _iosAsleepTypes,
      startTime: range.start,
      endTime: range.end,
    );
    if (points.isEmpty) return const [];

    final intervals = points.map((p) => (p.dateFrom, p.dateTo)).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));

    // 세션 스티칭: 간격이 _sessionStitchGap 이하면 같은 수면으로 이어붙인다(§6-3-a).
    final sessions = <HealthSleepSession>[];
    var start = intervals.first.$1;
    var end = intervals.first.$2;
    for (final interval in intervals.skip(1)) {
      final (segStart, segEnd) = interval;
      if (segStart.difference(end) <= _sessionStitchGap) {
        if (segEnd.isAfter(end)) end = segEnd;
      } else {
        sessions.add(HealthSleepSession(start, end));
        start = segStart;
        end = segEnd;
      }
    }
    sessions.add(HealthSleepSession(start, end));
    return sessions;
  }

  @override
  Future<DaylightSeries?> daylight(DateRange range) async {
    try {
      final raw = await _daylightChannel.invokeMethod<List<Object?>>(
        'timeInDaylight',
        {
          'startMillis': range.start.millisecondsSinceEpoch,
          'endMillis': range.end.millisecondsSinceEpoch,
        },
      );
      if (raw == null || raw.isEmpty) return null;
      final points = raw.map((entry) {
        final map = Map<Object?, Object?>.from(entry as Map);
        final t = DateTime.fromMillisecondsSinceEpoch(
          (map['t'] as num).toInt(),
        );
        final v = (map['v'] as num).toDouble();
        return (t, v);
      }).toList();
      return DaylightSeries(points);
    } on PlatformException {
      // §6-3-c와 같은 이유로 권한 거부와 데이터 없음을 구분하지 않는다.
      return null;
    }
  }

  @override
  Future<HrvSeries?> hrvNormalized(DateRange range) async {
    await _ensureConfigured();
    final raw = await _fetchNumericSeries(
      _health,
      hk.HealthDataType.HEART_RATE_VARIABILITY_SDNN,
      range,
    );
    if (raw.isEmpty) return null;
    return HrvSeries(_personalZScore(raw));
  }

  @override
  Future<HeartRateSeries?> restingHeartRate(DateRange range) async {
    await _ensureConfigured();
    final series = await _fetchNumericSeries(
      _health,
      hk.HealthDataType.RESTING_HEART_RATE,
      range,
    );
    if (series.isEmpty) return null;
    return HeartRateSeries(series);
  }
}

// Health Connect에서 수면의 중심 레코드(§6-3-a). iOS와 달리 세션 스티칭이
// 필요 없고, 대신 삼성헬스·핏빗·가민 등 여러 출처가 같은 밤을 중복 기록할 수
// 있어 dedup이 필요하다(§6-3-b).
const _androidSleepType = hk.HealthDataType.SLEEP_SESSION;

/// Health Connect 실기기 어댑터. `TimeInDaylight`에 대응하는 타입 자체가
/// Health Connect에 없어(§6-3) [daylight]는 항상 null이다 — 네이티브 채널이
/// 필요 없다.
class AndroidHealthSource implements HealthSignalSource {
  AndroidHealthSource({hk.Health? health}) : _health = health ?? hk.Health();

  final hk.Health _health;
  bool _configured = false;

  @override
  HealthCapabilities get capabilities => const HealthCapabilities(
    hasDaylight: false,
    canVerifyPermission: true, // Health Connect는 부여된 권한을 조회할 수 있다(§6-3-c)
    maxHistory: Duration(days: 30), // §6-3-d: 기본 30일, 그 이상은 별도 이력 권한 필요
    hrvMetric: HrvMetric.rmssd,
  );

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<bool> requestAuthorization() async {
    await _ensureConfigured();
    return _health.requestAuthorization([
      _androidSleepType,
      hk.HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
      hk.HealthDataType.RESTING_HEART_RATE,
    ]);
  }

  @override
  Future<List<HealthSleepSession>> sleepSessions(DateRange range) async {
    await _ensureConfigured();
    final points = await _health.getHealthDataFromTypes(
      types: [_androidSleepType],
      startTime: range.start,
      endTime: range.end,
    );
    if (points.isEmpty) return const [];

    final intervals = points.map((p) => (p.dateFrom, p.dateTo)).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));

    // dedup: 겹치는 구간만 하나로 합친다. iOS의 간격 기반 스티칭과 달리
    // 여기선 SleepSessionRecord가 이미 온전한 세션이라 실제 겹침만 병합한다.
    final sessions = <HealthSleepSession>[];
    var start = intervals.first.$1;
    var end = intervals.first.$2;
    for (final interval in intervals.skip(1)) {
      final (segStart, segEnd) = interval;
      if (!segStart.isAfter(end)) {
        if (segEnd.isAfter(end)) end = segEnd;
      } else {
        sessions.add(HealthSleepSession(start, end));
        start = segStart;
        end = segEnd;
      }
    }
    sessions.add(HealthSleepSession(start, end));
    return sessions;
  }

  @override
  Future<DaylightSeries?> daylight(DateRange range) async => null;

  @override
  Future<HrvSeries?> hrvNormalized(DateRange range) async {
    await _ensureConfigured();
    final raw = await _fetchNumericSeries(
      _health,
      hk.HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
      range,
    );
    if (raw.isEmpty) return null;
    return HrvSeries(_personalZScore(raw));
  }

  @override
  Future<HeartRateSeries?> restingHeartRate(DateRange range) async {
    await _ensureConfigured();
    final series = await _fetchNumericSeries(
      _health,
      hk.HealthDataType.RESTING_HEART_RATE,
      range,
    );
    if (series.isEmpty) return null;
    return HeartRateSeries(series);
  }
}
