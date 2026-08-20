// 온보딩 → 로스터 입력 → 홈으로 이어지는 세션 상태.
//
// InheritedWidget/provider 패키지 대신 평범한 싱글턴 ChangeNotifier로 뒀다
// — 위젯 트리 어디서든 `AppState.instance`로 접근 가능해서, 화면을
// 단독으로 pump하는 기존 위젯 테스트들(`_wrap(const HomeScreen())` 등)이
// 앱 루트 Provider 없이도 그대로 동작한다. 상태가 바뀔 때마다
// SharedPreferences에 JSON 한 덩어리로 저장하고 앱 시작 시 [load]로
// 복원한다 — 재시작해도 온보딩을 다시 하지 않는다
// (docs/SHIFT_프론트엔드_구현체크리스트.md §7 참고). 헬스 세션처럼 양이
// 많은 시계열이 생기면 그때 Drift로 옮긴다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_circadian_engine/roster/constants.dart';

/// `bedtime_intent` 테이블 초안(id, user_id, at, note)의 로컬 메모리
/// 버전 — 서버 스키마가 확정되면 그대로 옮겨 담을 수 있게 컬럼명을
/// 맞춰뒀다(docs/SHIFT_프론트엔드_구현체크리스트.md §5).
class BedtimeIntent {
  const BedtimeIntent(this.at, {this.note});
  final DateTime at;
  final String? note;
}

class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  // 계정(Drift user_profile 테이블의 name/email/password_hash에 대응 —
  // docs/SHIFT_프론트엔드_구현체크리스트.md §5 참고). ⚠️ 진짜 인증이
  // 아니다 — 백엔드 계정 시스템이 없어서 평문을 메모리에 들고 데모용으로
  // 비교만 한다. 실제 인증 서버가 붙으면 이 필드들과 signUp/tryLogin은
  // 반드시 해싱 + 서버 검증으로 교체해야 한다.
  //
  // ⚠️ [_userPassword]는 절대 디스크에 쓰지 않는다 — 평문 비밀번호를
  // 저장소에 남기면 안 된다. 대신 이름/이메일만 저장해서 재시작 시
  // 로그인된 상태로 복원하고, 비밀번호는 같은 세션 안에서만 비교한다.
  String? userName;
  String? userEmail;
  String? _userPassword;

  bool get isSignedIn => userName != null;

  void signUp({required String name, required String email, required String password}) {
    userName = name;
    userEmail = email;
    _userPassword = password;
    _persist();
    notifyListeners();
  }

  /// 데모 로그인: 같은 세션에서 가입한 계정과 이메일·비밀번호가 일치하는지만
  /// 본다(§ 클래스 docstring 참고 — 서버 검증 없음).
  bool tryLogin({required String email, required String password}) {
    if (userEmail == email && _userPassword == password) {
      notifyListeners();
      return true;
    }
    return false;
  }

  void signOut() {
    userName = null;
    userEmail = null;
    _userPassword = null;
    shiftTimings = null;
    roster = null;
    rosterStartDate = null;
    chronotype = 'neutral';
    caffeineCutoff = const TimeOfDay(hour: 14, minute: 0);
    workplaceLighting = 'normal';
    bedroomLighting = 'curtain';
    privacyConsent = false;
    aiConsent = false;
    consentAt = null;
    bedtimeIntents.clear();
    _clearPersisted();
    notifyListeners();
  }

  Map<ShiftType, (TimeOfDay, TimeOfDay)>? shiftTimings;
  String workplaceLighting = 'normal'; // bright | normal | dim
  String bedroomLighting = 'curtain'; // blackout | curtain | none
  String chronotype = 'neutral'; // morning | neutral | evening
  TimeOfDay caffeineCutoff = const TimeOfDay(hour: 14, minute: 0);

  /// 개인정보 수집·이용 동의(필수). 가입 시 받는다.
  bool privacyConsent = false;

  /// AI 리포트용 국외 이전 동의(선택) — 이 값이 false면 리포트 화면이
  /// 외부 호출을 하지 않는다. 필수 동의와 분리해야 하는 이유는
  /// [PrivacyPolicyScreen] §5 참고: 거부해도 계산·넛지는 쓸 수 있어야 한다.
  bool aiConsent = false;

  /// 동의한 시각 — 동의 이력은 증빙이 필요해서 언제 받았는지까지 남긴다.
  DateTime? consentAt;

  void saveConsent({required bool privacy, required bool ai}) {
    privacyConsent = privacy;
    aiConsent = ai;
    consentAt = privacy ? DateTime.now() : null;
    _persist();
    notifyListeners();
  }

  List<ShiftType>? roster;
  // roster[0]이 어느 날짜인지 — 이게 없으면 "오늘이 로스터의 몇 번째
  // 인덱스인지" 계산할 수가 없다(nudge_service.dart가 실제로 이 값으로
  // todayIndex를 구한다). 이전엔 이 앵커가 없어서 항상 roster[0](=로스터
  // 시작일)을 "오늘"로 취급하는 버그가 있었다.
  DateTime? rosterStartDate;

  bool get hasProfile => shiftTimings != null;

  // "지금 누웠어요" 로그. Drift/서버 스키마 붙기 전까지는 메모리에만 쌓인다
  // — 여러 번 눌러도(false start 등) 전부 기록하고, 최신순으로 앞에 둔다.
  final List<BedtimeIntent> bedtimeIntents = [];

  void logBedtimeIntent({String? note}) {
    bedtimeIntents.insert(0, BedtimeIntent(DateTime.now(), note: note));
    _persist();
    notifyListeners();
  }

  void saveOnboarding({
    required Map<ShiftType, (TimeOfDay, TimeOfDay)> shiftTimings,
    required String workplaceLighting,
    required String bedroomLighting,
    required String chronotype,
    required TimeOfDay caffeineCutoff,
  }) {
    this.shiftTimings = Map.of(shiftTimings);
    this.workplaceLighting = workplaceLighting;
    this.bedroomLighting = bedroomLighting;
    this.chronotype = chronotype;
    this.caffeineCutoff = caffeineCutoff;
    _persist();
    notifyListeners();
  }

  /// [startDate]는 `roster[0]`이 해당하는 실제 날짜(자정 기준) — 보통
  /// 로스터를 확인한 달의 1일. 이게 있어야 "오늘"이 배열의 몇 번째
  /// 인덱스인지 계산할 수 있다.
  void saveRoster(List<ShiftType> roster, {required DateTime startDate}) {
    this.roster = List.of(roster);
    rosterStartDate = DateTime(startDate.year, startDate.month, startDate.day);
    _persist();
    notifyListeners();
  }

  /// `shift_circadian_engine`의 `buildNudgePlan(profile: ...)`에 그대로 넘길 수 있는 형태.
  /// [hasProfile]이 false일 때는 호출하지 말 것(온보딩 값이 없으면 의미 없음).
  UserProfile toUserProfile() {
    final t = shiftTimings!;
    return UserProfile(
      shiftTimings: {
        for (final s in [ShiftType.day, ShiftType.evening, ShiftType.night])
          s: ShiftTiming(_toHours(t[s]!.$1), _toHours(t[s]!.$2)),
      },
      workplaceLighting: workplaceLighting,
      bedroomLighting: bedroomLighting,
    );
  }

  static double _toHours(TimeOfDay t) => t.hour + t.minute / 60.0;

  // ─── 영구저장 ────────────────────────────────────────────────────────
  //
  // 값 하나당 키 하나로 흩어놓으면 "로스터는 저장됐는데 시작일은 안 된"
  // 반쪽 상태가 나올 수 있어서, JSON 한 덩어리를 단일 키에 쓴다.
  // 스키마가 바뀌면 키 뒤 버전을 올리고 이전 키는 무시하면 된다.
  static const _prefsKey = 'shift_app_state_v1';

  /// 저장된 세션을 복원한다. `runApp` 전에 한 번 호출 —
  /// 저장된 게 없으면 아무것도 하지 않는다(최초 실행).
  ///
  /// 저장 데이터가 깨졌거나 옛 스키마여도 앱이 못 켜지면 안 되므로,
  /// 복원에 실패하면 조용히 지우고 최초 실행처럼 시작한다.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      _applyJson(jsonDecode(raw) as Map<String, dynamic>);
      notifyListeners();
    } catch (_) {
      await _clearPersisted();
    }
  }

  /// 저장은 부수효과라서, 실패해도 화면 동작을 막지 않는다(플러그인이 없는
  /// 위젯 테스트 환경 포함). 대신 메모리 상태는 이미 갱신된 뒤다.
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_toJson()));
    } catch (_) {
      // 무시 — 다음 저장 시점에 다시 시도된다.
    }
  }

  Future<void> _clearPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {
      // 무시.
    }
  }

  Map<String, dynamic> _toJson() => {
        'userName': userName,
        'userEmail': userEmail,
        if (shiftTimings != null)
          'shiftTimings': {
            for (final e in shiftTimings!.entries)
              e.key.name: [_toMinutes(e.value.$1), _toMinutes(e.value.$2)],
          },
        'workplaceLighting': workplaceLighting,
        'bedroomLighting': bedroomLighting,
        'chronotype': chronotype,
        'caffeineCutoffMin': _toMinutes(caffeineCutoff),
        'privacyConsent': privacyConsent,
        'aiConsent': aiConsent,
        if (consentAt != null) 'consentAt': consentAt!.toIso8601String(),
        if (roster != null) 'roster': [for (final s in roster!) s.name],
        if (rosterStartDate != null)
          'rosterStartDate': rosterStartDate!.toIso8601String(),
        // 무한정 쌓이면 안 되니 최근 것만 — 홈은 가장 최근 1건만 쓴다.
        'bedtimeIntents': [
          for (final i in bedtimeIntents.take(60))
            {'at': i.at.toIso8601String(), 'note': i.note},
        ],
      };

  void _applyJson(Map<String, dynamic> json) {
    userName = json['userName'] as String?;
    userEmail = json['userEmail'] as String?;

    final timings = json['shiftTimings'] as Map<String, dynamic>?;
    shiftTimings = timings == null
        ? null
        : {
            for (final e in timings.entries)
              ShiftType.values.byName(e.key): (
                _fromMinutes((e.value as List)[0] as int),
                _fromMinutes((e.value as List)[1] as int),
              ),
          };

    workplaceLighting = json['workplaceLighting'] as String? ?? 'normal';
    bedroomLighting = json['bedroomLighting'] as String? ?? 'curtain';
    chronotype = json['chronotype'] as String? ?? 'neutral';
    caffeineCutoff = _fromMinutes(json['caffeineCutoffMin'] as int? ?? 14 * 60);
    privacyConsent = json['privacyConsent'] as bool? ?? false;
    aiConsent = json['aiConsent'] as bool? ?? false;
    final consent = json['consentAt'] as String?;
    consentAt = consent == null ? null : DateTime.parse(consent);

    final savedRoster = json['roster'] as List?;
    roster = savedRoster == null
        ? null
        : [for (final s in savedRoster) ShiftType.values.byName(s as String)];

    final start = json['rosterStartDate'] as String?;
    rosterStartDate = start == null ? null : DateTime.parse(start);

    bedtimeIntents
      ..clear()
      ..addAll([
        for (final i in (json['bedtimeIntents'] as List? ?? []))
          BedtimeIntent(
            DateTime.parse((i as Map)['at'] as String),
            note: i['note'] as String?,
          ),
      ]);
  }

  static int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  static TimeOfDay _fromMinutes(int m) =>
      TimeOfDay(hour: m ~/ 60, minute: m % 60);
}
