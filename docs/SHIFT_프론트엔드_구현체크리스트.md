# SHIFT 프론트엔드 구현 체크리스트

> 작성: 코드 실사 기반
> 근거: `SHIFT_개발기획서.md` §6~7, `SHIFT_프론트엔드_기획서.md` §4~5·§7, `flutter_engine`/`shift_app` 코드
> v1 · 2026-08-18

## 0. 이 문서의 성격

에픽 순서(데이터 수집 → 계산 → 화면 → 알림)는 원안 그대로 두었다. 각 항목에 지금 코드베이스에 **이미 있는 것 / 없는 것 / 기존 기획서와 어긋나는 것**을 표시했다. 우선순위 재조정은 하지 않았으니, 순서를 바꾸고 싶으면 별도로 정하면 된다.

---

## 1. 데이터 수집 (헬스 데이터)

| # | 항목 | 상태 | 비고 |
|---|---|---|---|
| 1 | HealthKit 연동 세팅 (Info.plist, Xcode Capability, 실기기 빌드) | 미착수 | 개발기획서 §7-1에 이미 "필수·1~2일" 항목으로 있음 — `HKQuantityTypeIdentifierTimeInDaylight`는 Flutter `health` 패키지(v13.3.2)에 없어서 Swift MethodChannel 직접 구현 필요. §7-1: "즉시 스파이크로 검증할 것. 이게 막히면 광 신호 검증 스토리가 통째로 빠진다." |
| 2 | 수면 세션 읽기(`SleepAnalysis`) | 미착수 | §6-3(c): **iOS는 권한 거부 여부를 앱에 알려주지 않는다** — "권한 미부여"와 "기록 없음"을 구분 불가. 안내 문구는 두 원인을 다 커버해야 함(§6-3 인용문). |
| 3 | 세션 병합(30분 간격으로 하나로 묶기) | 미착수 | §6-3(a)에서 "세션 스티칭"이라는 이름으로 이미 요구됨(HealthKit은 카테고리 샘플이 흩어져 있어 "이게 한 번의 수면인가"를 앱이 직접 판정). **30분 임계값은 이번에 처음 나온 구체값 — 문헌 근거 없음, `ASSUMPTION` 태그 권장.** |
| 4 | 출처 필터링(Apple Watch만, 아이폰·타사앱 제외) | 미착수 | §6-3(b): iOS는 사실상 단일 출처라 상대적으로 덜 급함. **Android(Health Connect) 쪽 dedup+출처 필터가 이 목록에 빠져 있는데, §6-2 플랫폼 전략상 안드로이드는 선택이 아니라 필수 분기다.** 안드로이드도 타깃이면 이 항목 옆에 나란히 추가할 것. |
| 5 | Drift 스키마 7개 테이블 구현 | **설계만 필요, 코드 0** | 프론트엔드 기획서 §7: "'할당 사항' 문서의 7개 테이블 설계는 있으나 실제 코드 없음"이라고만 되어 있고, 그 "할당 사항" 문서 자체가 이 레포엔 없음. §5에서 7테이블 초안을 새로 제안했다. |
| 6 | DB 저장 + 중복 방지(`startAt` 유니크) | 미착수 | 5번에 종속. |
| 7 | 앱 실행 시 동기화(마지막 동기화 이후만) | 미착수 | §6-3(e): 갤럭시워치는 기상 후 폰과 페어링돼야 동기화되므로 "아침에 앱 열자마자 어젯밤 데이터 있다고 가정 금지". |

**어댑터 인터페이스는 이미 설계돼 있다** — 개발기획서 §6-4. 위 1~4·7은 이 인터페이스 뒤로 들어가면 된다.

```dart
abstract class HealthSignalSource {
  HealthCapabilities get capabilities;

  /// iOS: 세션 스티칭 후 반환 / Android: SleepSessionRecord 정규화 + dedup
  Future<List<SleepSession>> sleepSessions(DateRange range);

  /// null = 이 기기가 제공하지 않음 (Android는 항상 null)
  Future<DaylightSeries?> daylight(DateRange range);

  /// 원시값이 아닌 개인 내 z-score. 플랫폼별 정규화는 구현체 책임
  Future<HrvSeries?> hrvNormalized(DateRange range);

  Future<HeartRateSeries?> restingHeartRate(DateRange range);
}
```

구현체는 `IosHealthSource` / `AndroidHealthSource` 두 개(§6-4). **원시값을 인터페이스 밖으로 내보내지 말 것** — SDNN(iOS)과 RMSSD(Android)는 상호 변환 공식이 없어서 같은 필드로 새면 상위 로직이 조용히 오염된다(§6-3-f).

---

## 2. 계산 (룰 엔진)

| # | 항목 | 상태 |
|---|---|---|
| 1 | `buildPlan()` 순수함수 + 유닛 테스트 | **이미 있음, 이름만 다름.** `flutter_engine/lib/nudge/nudge_engine.dart`의 `buildNudgePlan()`. 순수함수, `test/nudge_engine_test.dart`·`test/nudge_messages_test.dart`로 37개 테스트 통과 중. |
| 2 | 취침/낮잠 타입 분기 | **완료.** `룰엔진_규칙_v2.md` §3 그대로, `PlanType.bedtime` / `PlanType.nap`. |
| 3 | 엣지케이스 4종 반환(`noData`/`insufficientData`/`noShift`/`ok`) | **기존 설계와 충돌.** 지금 구현(`idealSleepTimes`/`currentPhase`)은 최근 수면 기록이 없으면 4종 중 하나를 반환하는 게 아니라 `ArgumentError`를 던진다 — "콜드스타트 처리는 호출부 책임"이라는 설계였다(`logic/nudge.py`의 `evaluate_effects=False` 콜드스타트 분기와 같은 맥락). 4종 sentinel로 바꾸려면 기존 동작을 바꿔야 한다 — §6 "결정 필요" 참고. |
| 4 | 파생변수 계산 → `daily_metric` 저장(순환 평균·순환 표준편차 주의) | 미착수. **순환평균은 이미 구현됨**(`flutter_engine/lib/nudge/circular_time.dart`의 `circularMeanHours`) — 재사용 가능. **순환표준편차는 아직 없음**, 새로 필요. |

---

## 3. 화면

| # | 항목 | 상태 |
|---|---|---|
| 1 | 온보딩 — 권한 요청 직후 7일치 조회 → 비면 안내 화면 분기 | **지금 있는 온보딩과 다른 화면을 가리킴.** 현재 `shift_app/lib/screens/onboarding_flow.dart`는 근무 시각(방금 시간선택기로 구현하기로 함)·조명 환경·크로노타입·카페인 습관 4단계이고 HealthKit 권한/데이터 조회가 없다. 이 항목은 §7-2(권한 온보딩) 또는 신규 "헬스 연동" 단계로 봐야 함 — 온보딩 플로우 안에 통합할지 별도 화면으로 둘지 결정 필요. |
| 2 | 근무표 입력 — 달력 + 반복 패턴 | **부분 완료.** 달력 UI는 `roster_confirm_screen.dart`에 있음(더미 데이터). "반복 패턴" 입력은 없음. 진짜 엑셀 업로드 경로는 `POST /roster/parse`로 이미 계약이 확정돼 있다(프론트엔드 기획서 §4-2-1) — 파일 업로드가 1차, 캘린더 직접 편집은 2차 폴백(개발기획서 §5-2). |
| 3 | 홈 — 목표 시각 카드 + 오늘의 행동 2~3개 + 회복 상태 | **목표 시각·오늘의 행동은 완료**(`nudge_service.dart` + `home_screen.dart`, 지난 대화에서 계산 엔진 연결함). 단 지금은 데모 고정 로스터를 쓰고 있어 실제 사용자 로스터·프로필과는 아직 안 이어짐(§6). **회복 상태(수면시간/HRV/심박)는 여전히 mock** — §1 `HealthSignalSource` 구현이 선행돼야 함. |
| 4 | "지금 누웠어요" 버튼 → `bedtime_intent` 저장 | 미착수. |
| 5 | 홈 하단 그래프 — 2주 격차 추이(`fl_chart`) | 미착수. **주의**: 개발기획서 §5-3은 액토그램에 한해 "`fl_chart`로는 구현 불가, `CustomPainter` 확정"이라고 못박았다 — 이건 다른 차트(2주 격차 추이, 단순 라인)라 `fl_chart`로 가능할 가능성이 높지만, 액토그램과 헷갈리지 않게 문서에 명시해두는 게 좋겠다. |
| 6 | 수동 수면 입력(`source = manual`) | 미착수. |
| 7 | 첫날 / 데이터 없음 상태 화면 | 미착수. §2-3(엣지케이스 4종)과 직접 연결됨 — 엔진이 `noData`/`insufficientData`를 반환해야 이 화면이 뭘 보여줄지 분기할 수 있다. |

---

## 4. 알림

| # | 항목 | 상태 |
|---|---|---|
| 1 | 로컬 알림 예약(`flutter_local_notifications`) + 알림 권한 | 미착수. 개발기획서 §7-2에 플랫폼별 제약이 이미 정리돼 있음: **iOS는 pending 알림 64개 제한**(하루 3개 기준 약 3주치 — 앱 실행 시 재예약 로직 필수), **Android 12+는 `SCHEDULE_EXACT_ALARM` + 사용자 수동 허용 UI** 필요, **삼성 절전 정책** 대응 위해 온보딩에 배터리 최적화 예외 요청 화면 포함, **타임존**(`timezone` 패키지 초기화, 자정 넘는 나이트 근무 검증). |
| 2 | 알림 탭 → 앱 실행 → 동기화 트리거 | 미착수. |
| 3 | 알림 반응 → `nudge_log` 저장 | 미착수. §5의 `nudge_log` 테이블과 직결. |

---

## 5. Drift 스키마 초안 (7테이블 — 신규 제안, 리뷰 필요)

기존 문서에 실제 스키마가 없어서 지금까지 나온 요구사항(§1~4, `SHIFT_프론트엔드_기획서.md` §5 데이터 계층)을 근거로 새로 짰다. **확정 아님 — 컬럼명·타입은 리뷰 대상.**

| 테이블 | 핵심 컬럼 | 근거 |
|---|---|---|
| `user_profile` | `id`, `name`, `email`, `password_hash`, `shift_timings(json)`, `workplace_lighting`, `bedroom_lighting`, `commute_minutes`, `latitude`, `longitude` | `flutter_engine`의 `UserProfile`과 1:1 + 계정 식별자 3개(2026-08-18 로그인/회원가입 화면 추가하며 편입). **`chronotype`/`caffeine_cutoff`(온보딩에서 수집 중)는 엔진 `UserProfile`에 대응 필드가 없음 — §6 "결정 필요" 참고. `password_hash`는 이름 그대로 해시 저장을 전제한 컬럼명이지만, 지금 앱엔 실제 백엔드 인증이 없어 `AppState`가 데모용으로 평문을 들고 있다 — 진짜 인증 서버 붙을 때 반드시 해싱 경로로 교체할 것.** |
| `roster` | `id`, `user_id`, `year`, `month`, `day`, `shift_code`, `source`(excel/manual/ocr) | 프론트엔드 기획서 §5 "Roster (로컬 저장, 월 단위)" |
| `code_mapping` | `id`, `user_id`, `raw_code`, `mapped_code` | 개발기획서 §5-2-3 "근무 코드 매핑 테이블", 사용자 단위 재사용 |
| `health_session` | `id`, `user_id`, `start_at`, `end_at`, `source`, `kind`(main/nap), unique(`user_id`,`start_at`) | §1-2·6, `nudge_engine.dart`의 `SleepSession`과 호환되게 |
| `daily_metric` | `id`, `user_id`, `date`, `dlmo_clock`, `sleep_debt_min`, `circular_mean_bedtime`, `circular_std_bedtime`, `source` | §2-4 |
| `bedtime_intent` | `id`, `user_id`, `at`, `note` | §3-4 |
| `nudge_log` | `id`, `user_id`, `nudge_kind`, `scheduled_at`, `reacted_at`, `action`(tapped/dismissed/completed) | §4-3 |

---

## 6. 결정 필요한 것

이번에 코드 읽으면서 걸린 것들 — 구현 전에 답이 있어야 방향이 갈리는 것만 추림.

1. **엣지케이스 4종 vs 예외.** 지금 `nudge_engine.dart`는 데이터 없으면 던진다. `noData`/`insufficientData`/`noShift`/`ok` 4종을 원하면 반환 타입을 바꿔야 하고, 이미 있는 테스트(§2-1)도 같이 고쳐야 함.
2. **온보딩 `chronotype`/`caffeine_cutoff` 필드의 용도.** 지금 UI엔 있지만 엔진 어디에도 안 씀. 나중에 (a) `needSleepMin` 개인화, (b) `caffeineCutoffBeforeMin`(528분 고정값) 개인 오버라이드, (c) 그냥 삭제 중 뭘로 갈지.
3. **Android Health Connect 어댑터가 §1 목록에 없음.** iOS만 타깃인지, 안드로이드도 §6-2 원안대로 필수 분기인지.
4. **1번(온보딩→HealthKit 7일 조회)과 현재 온보딩 플로우의 관계.** 지금 4단계 온보딩에 통합할지, 별도 "헬스 연동" 단계로 뺄지.

---

## 7. 지금 당장 할 일 (제안)

이 체크리스트 순서(데이터 수집이 1번)를 그대로 따르면 HealthKit 스파이크부터 시작해야 하는데, 그건 실기기·Xcode 세팅이 걸려 있어 지금 이 세션에서 바로 이어가긴 어렵다. 대신 **§3-1(온보딩)의 일부 — 근무 시각/조명 값을 실제 `UserProfile` 상태로 만드는 것**부터 하는 걸 제안한다:

1. `onboarding_flow.dart` Step1에 시간선택기 구현 (합의됨)
2. Drift에 `user_profile` 테이블만 우선 추가 (§5의 7개 중 1개, 나머지는 뒤 에픽에서)
3. 온보딩 완료 시 저장 → `nudge_service.dart`가 데모 상수 대신 이 값을 읽도록 연결

§6-2/§6-4(chronotype·caffeine_cutoff 용도)는 위 3단계와 무관하게 진행 가능하므로 나중에 따로 답해도 막히지 않는다.
