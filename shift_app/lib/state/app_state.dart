// 온보딩 → 로스터 입력 → 홈으로 이어지는 세션 상태.
//
// InheritedWidget/provider 패키지 대신 평범한 싱글턴 ChangeNotifier로 뒀다
// — 위젯 트리 어디서든 `AppState.instance`로 접근 가능해서, 화면을
// 단독으로 pump하는 기존 위젯 테스트들(`_wrap(const HomeScreen())` 등)이
// 앱 루트 Provider 없이도 그대로 동작한다. Drift로 영구저장하기 전까지는
// 메모리에만 있어서 앱을 재시작하면 초기화된다
// (docs/SHIFT_프론트엔드_구현체크리스트.md §7 참고).
import 'package:flutter/material.dart';
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
  String? userName;
  String? userEmail;
  String? _userPassword;

  bool get isSignedIn => userName != null;

  void signUp({required String name, required String email, required String password}) {
    userName = name;
    userEmail = email;
    _userPassword = password;
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
    bedtimeIntents.clear();
    notifyListeners();
  }

  Map<ShiftType, (TimeOfDay, TimeOfDay)>? shiftTimings;
  String workplaceLighting = 'normal'; // bright | normal | dim
  String bedroomLighting = 'curtain'; // blackout | curtain | none
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
    notifyListeners();
  }

  void saveOnboarding({
    required Map<ShiftType, (TimeOfDay, TimeOfDay)> shiftTimings,
    required String workplaceLighting,
    required String bedroomLighting,
  }) {
    this.shiftTimings = Map.of(shiftTimings);
    this.workplaceLighting = workplaceLighting;
    this.bedroomLighting = bedroomLighting;
    notifyListeners();
  }

  /// [startDate]는 `roster[0]`이 해당하는 실제 날짜(자정 기준) — 보통
  /// 로스터를 확인한 달의 1일. 이게 있어야 "오늘"이 배열의 몇 번째
  /// 인덱스인지 계산할 수 있다.
  void saveRoster(List<ShiftType> roster, {required DateTime startDate}) {
    this.roster = List.of(roster);
    rosterStartDate = DateTime(startDate.year, startDate.month, startDate.day);
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
}
