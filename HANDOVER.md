# SHIFT 프론트엔드 — 핸드오버

**작성 2026-08-20** · 브랜치 `feat/persistence-nav-consent` · [PR #1](https://github.com/aza2o/aza2o_hackaton_FE/pull/1) (OPEN)

새 세션에 붙여넣을 프롬프트는 맨 아래 [§8](#8-새-세션에-붙여넣을-프롬프트)에 있다.

---

## 1. 이 프로젝트가 뭔가

교대근무자(간호사)용 수면·일주기 리듬 관리 앱. 근무표를 넣으면 Process C(DLMO, 일주기 위상)와 Process S(수면압력)로 개인화된 취침 타이밍을 계산하고, **넛지**(정해진 시각의 행동 알림)와 AI 리포트로 알려준다.

**넛지**는 행동경제학 용어(Thaler & Sunstein, 2008)로 "강제하지 않고 행동을 유도하는 선택 설계"다. 이 앱은 7종을 목표 취침시각 기준으로 역산해 건다 — `caffeineCutoff`(취침 8.8h 전), `lightBlock`(2h 전), `windDown`(1h 전), `lightExposure`(기상 30m 후), `napStart`, `sunglassesCommute`, `brightLightAtWork`. 상수는 [`flutter_engine/lib/nudge/nudge_constants.dart`](flutter_engine/lib/nudge/nudge_constants.dart).

```
shift_app/       Flutter 클라이언트
flutter_engine/  순수 Dart 서캐디언 엔진 (Flutter 의존성 없음, 골든벡터 검증됨)
logic/           FastAPI — POST /roster/parse (엑셀 파싱) 하나만 실사용
supabase/        DB 마이그레이션 초안 (미적용)
docs/            기획서·구현체크리스트·룰엔진 스펙
```

계산은 전부 클라이언트에서 돈다. 서버는 엑셀 파싱과 AI 문구 생성만 한다.

---

## 2. 환경 — 여기서 제일 많이 막힌다

**Flutter 3.47(Dart 3.13) 이상이 필요하다.** `pubspec.yaml`의 `sdk: ^3.13.0` 때문에 그 아래로는 `pub get`부터 실패한다.

```bash
cd shift_app
flutter clean && rm -rf .dart_tool && flutter pub get
flutter test
```

**함정 3가지 (이번 세션에서 전부 밟았다):**

1. **`flutter clean`을 꼭 해라.** Flutter를 업그레이드한 뒤 구버전 캐시가 남아 있으면 `dart:ui`가 해석되지 않아 **Flutter SDK 자체 파일에서** 에러 5만 개가 쏟아진다. 패키지 문제로 보이지만 아니다.
2. **`shift_app/`에서는 절대 `dart` 명령을 쓰지 마라.** `dart run lib/main.dart` 같은 걸 돌리면 `dart:ui`가 없어 똑같이 에러가 폭발한다. 항상 `flutter`를 쓴다. 순수 `dart`는 `flutter_engine/`에서만.
3. **VSCode는 `aza2o_hackaton_FE`를 열어라** (그 상위 폴더 말고). 모노레포라 루트에 `pubspec.yaml`이 없어서, 상위를 열면 Run 버튼이 Flutter가 아니라 `dart`로 실행해버린다. [`.vscode/launch.json`](.vscode/launch.json)이 이걸 해결한다.

에러가 길면 **앞부분**을 봐라. 꼬리만 보면 진짜 원인(`Dart library 'dart:ui' is not available`)이 안 보인다.

```bash
flutter run -d chrome 2>&1 | head -30
```

---

## 3. 이번 세션에서 한 일 (커밋 4개)

| 커밋 | 내용 |
|---|---|
| `fb41403` | VSCode 실행 설정 |
| `523084c` | 온보딩·로스터 영속화 |
| `942efbd` | 내비 개편 · 개인정보 동의 · 월 이동 · AI 상태 입력 |
| `56985fb` | AI 답변 홈 노출 · 피부 루틴 계산화 · 로그인 여백 |

**영속화** — `AppState`에 `load()`/`_persist()`. SharedPreferences에 JSON 한 덩어리를 단일 키(`shift_app_state_v1`)로 저장한다. 값별로 키를 쪼개면 "로스터는 저장됐는데 시작일은 안 된" 반쪽 상태가 생긴다. 비밀번호는 저장하지 않는다. 깨진 데이터는 지우고 최초 실행처럼 시작한다. Drift는 안 썼다 — 스키마 초안의 7테이블은 현재 데이터량에 과하고, 헬스 시계열이 들어올 때 옮기는 게 맞다.

**내비게이션** — 하단 탭 = 홈 + 근무 달력. 설정은 홈 우측 상단 아이콘. AI 리포트·피부 루틴은 홈 하단 섹션에 인라인.

**근무 달력** (신규) — 월 이동, 오늘 표시, 셀 탭 편집. 근무표 없는 달은 오프로 채우지 않고 빈 상태로 둔다(없는 근무를 O로 그리면 "오프로 등록됐다"고 오해하고 그 값으로 넛지까지 계산된다).

**개인정보 동의** — 가입 시 필수 동의 게이트, AI 국외 이전은 별도 선택 동의. 미동의 시 Gemini 호출 자체를 안 한다. 설정에서 철회 가능.

**AI 인사이트 홈 노출** — 코멘트를 홈에 바로 띄우고 **하루 1회만 호출**한다(`AppState.hasFreshAiComment`). 홈은 자주 여는 화면이라 캐시 없이는 비용이 여는 횟수만큼 늘어난다.

### 고친 버그
- 온보딩 3단계(크로노타입·카페인)가 `saveOnboarding`에 전달되지 않아 사용자 답이 버려지고 있었다.
- 피부 루틴 화면의 시각이 전부 하드코딩(`14:30`, `07:00`, `자외선지수 4`)이라 근무표와 무관했고, 그래서 `14:30`에 `AM`이 붙어 있었다. 이제 수면 창에서 계산한다([`skin_routine_service.dart`](shift_app/lib/engine/skin_routine_service.dart)).
- 권한 화면 "나중에 하기"가 근무표 입력을 건너뛰어 로스터가 빈 채로 앱이 시작됐다.

---

## 4. 지켜야 할 원칙 (임의로 바꾸지 말 것)

- **점수·게이지·진단성 문구 금지.** 피부 트랙 근거 문서 §2·§5가 명시적으로 금지. 테스트가 지키고 있다.
- **넛지 문구는 명령조로 바꾸지 않는다.** 근무를 자기가 정할 수 없는 사용자에게 명령조는 죄책감만 남는다. 게다가 회복 지표(수면·HRV·심박)가 아직 데모값이라 그 위에 단정적 표현을 얹을 수 없다. 강하게 쓸 곳은 **권한 요청**이지 넛지 본문이 아니다.
- **동의 없이 외부 호출 금지.** 화면을 열었다는 이유만으로 데이터가 국외로 나가면 안 된다.
- **계산 못 하면 안 보여준다.** 추측한 시각·근무를 채워 넣지 않는다.
- **엔진(`flutter_engine/`)은 골든벡터로 Python 원본과 대조 검증돼 있다.** 시그니처를 바꾸면 반드시 `dart test`로 44개를 다시 확인한다.

---

## 5. 지금 상태 — 진짜와 가짜

| 항목 | 상태 |
|---|---|
| 목표 취침 시각 / 오늘의 행동 | **진짜** — 엔진 계산 |
| 근무 달력 | **진짜** — 저장된 로스터 |
| 피부 루틴 시각 | **진짜** — 수면 창에서 계산 (이번에 수정) |
| 회복 상태(수면·HRV·심박) | **가짜** — HealthKit 미연동, 데모 세션 |
| AI 리포트 문구 | **진짜** (Gemini 호출) — 단, 상태 입력은 미반영 (§6) |
| 로그인·비밀번호 | **가짜** — 인증 서버 없음, 메모리 대조뿐 |

---

## 6. 다음 작업 (우선순위)

1. **Supabase Edge Function 소스 확보** — 최우선 블로커. `supabase/`에 `functions/`가 없어서 배포된 `report` 함수가 버전관리 밖에 있다. 클라이언트는 `stateNote`(사용자가 입력한 현재 컨디션)를 보내지만, 함수가 프롬프트에 넣도록 고쳐지기 전까지 답변에 반영되지 않는다. 원개발자에게 요청할 것.
2. **report 엔드포인트 rate limit / 인증** — 지금 anon 공개다. 호출당 Gemini 비용이 나가므로 공개 전 필수.
3. **크로노타입·카페인을 엔진에 연결** — 값은 저장되지만 `UserProfile`에 필드가 없어 계산에 안 쓰인다(카페인은 고정 상수 `528분`). 엔진 시그니처 변경 → 골든벡터 재확인 필요.
4. **HealthKit / Health Connect 실측 연동** — 실기기 + Xcode 설정 필요. 리스크가 커서 뒤로 미뤘다.
5. **홈 첫 진입 코치마크** — 별도 튜토리얼 화면은 만들지 않기로 했다(가입→온보딩 4단계→권한→근무표로 이미 7화면이라 이탈이 는다).
6. **개인정보 처리방침 법무 검토** — 현재 문구는 코드가 실제로 하는 동작을 사실대로 적은 초안이다.
7. **Supabase DB 스키마 적용** — `0001_shift_schema.sql` 미적용, 팀 리뷰 대기.

---

## 7. 테스트 / 검증

```bash
cd shift_app     && flutter test    # 30개
cd flutter_engine && dart test      # 44개 (골든벡터)
cd shift_app     && flutter analyze
```

근무표 파싱을 실물로 확인하려면 `SHIFT_데모_근무표_2026-08.xlsx`(원개발자 제공)를 쓴다. 시트 5개에 엣지케이스 포함. **가입한 이름이 파일 안 이름과 같아야** 파싱된다 — 파일에 `게스트`가 들어있어서 게스트 로그인으로 바로 테스트된다.

---

## 8. 새 세션에 붙여넣을 프롬프트

```
/Users/yun/Coding/aza2o/aza2o_hackaton_FE 에서 SHIFT 앱 작업을 이어서 한다.
먼저 저장소 루트의 HANDOVER.md를 읽어라. 프로젝트 배경, 환경 함정,
지금까지 한 작업, 지켜야 할 원칙, 다음 작업 우선순위가 전부 거기 있다.

현재 브랜치는 feat/persistence-nav-consent 이고 PR #1이 열려 있다.
main에 머지되기 전이다.

작업 시작 전에 반드시 확인할 것:
- shift_app/ 안에서는 `dart`가 아니라 `flutter` 명령을 쓴다
- Flutter 3.47(Dart 3.13) 이상이어야 한다
- 변경 후 `flutter test`(30개)와 `dart test`(엔진 44개)가 통과해야 한다

무엇부터 할지는 HANDOVER.md §6 우선순위를 따르되, 시작 전에 나에게
무엇을 할 건지 한 줄로 확인받아라.
```
