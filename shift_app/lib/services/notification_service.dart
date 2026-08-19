// 로컬 알림 예약 — `SHIFT_개발기획서.md` §7-2("알림 스케줄링 · 제품의 심장").
// 서버 푸시가 아니라 로컬 알림인 이유: 오프라인에서도 동작해야 하고,
// 넛지는 "퇴근 20분 전 차광"처럼 타이밍이 곧 효과라 발화 시각이 정확해야
// 한다(서버 왕복 지연을 피한다).
//
// 권한 요청·예약 둘 다 내부에서 타임아웃을 걸어 항상 짧은 시간 안에
// 끝난다 — 이 기능은 선택 사항이라 실패해도(권한 거부, 플랫폼 채널 지연
// 등) 온보딩·로스터 확인 플로우를 막으면 안 된다.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../engine/nudge_service.dart' show ScheduledNudge;

const _callTimeout = Duration(seconds: 5);

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
    _initialized = true;
  }

  /// 알림 권한(+ Android 정확 알람 권한) 요청. 거부돼도 예외 없이 false만
  /// 반환한다 — 선택 권한이라 앱을 막지 않는다.
  Future<bool> requestPermission() async {
    try {
      return await _requestPermission().timeout(_callTimeout);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _requestPermission() async {
    await _ensureInitialized();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? false;
      // 정확 알람 — 넛지는 타이밍이 곧 효과라 §7-2에서 필수로 다룬다.
      await android?.requestExactAlarmsPermission();
      return granted;
    }
    return false;
  }

  /// 기존 예약을 전부 지우고 [nudges]로 새로 건다 — 앱 실행·로스터 변경
  /// 시점마다 재예약해야 한다(§7-2, iOS 대기 알림 64개 제한 때문에 너무
  /// 먼 미래까지 걸어두면 안 됨 — 호출부가 며칠치를 넘길지 결정한다).
  Future<void> rescheduleAll(List<ScheduledNudge> nudges) async {
    try {
      await _rescheduleAll(nudges).timeout(_callTimeout);
    } catch (_) {
      // 권한 거부·플랫폼 채널 지연 등 — 다음 재예약 시점에 다시 시도된다.
    }
  }

  Future<void> _rescheduleAll(List<ScheduledNudge> nudges) async {
    await _ensureInitialized();
    await _plugin.cancelAll();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'shift_nudge',
        'SHIFT 넛지',
        channelDescription: '근무 리듬에 맞춘 행동 알림',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    final now = DateTime.now();
    for (var i = 0; i < nudges.length; i++) {
      final n = nudges[i];
      if (n.at.isBefore(now)) continue; // 이미 지난 시각은 예약하지 않는다
      await _plugin.zonedSchedule(
        i,
        n.title,
        n.body,
        tz.TZDateTime.from(n.at.toUtc(), tz.UTC),
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }
}
