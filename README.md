# 슬립레디 (SleepReady)

교대근무자의 근무표와 생활 패턴을 바탕으로 필요한 수면량, 권장 취침 시각,
회복 행동과 피부 루틴을 제안하는 개인화 웰니스 앱입니다.

해커톤 운영 환경에서는 **Supabase 계정 없이 게스트 모드만으로 전체 핵심
화면을 시연할 수 있습니다.** 수면·HRV·안정시 심박과 Apple Watch 연동은
현실적인 데모 데이터를 사용합니다.

## 주요 기능

- 엑셀 근무표 업로드 또는 근무 패턴 직접 입력
- 교대 근무별 필요 수면량과 수면 부족 추정
- 권장 취침·기상·카페인·빛 노출 넛지
- 최근 수면 리듬과 근무 루틴별 AI 인사이트
- 날짜별 상태·고민 기록과 반복 패턴 기반 개인화
- 수면을 우선으로 한 피부 행동 및 AAC 데모 제품 추천
- Apple Health 연결·동기화 시연 화면
- 선택적 Supabase 이메일 회원가입·로그인

## 저장소 구조

```text
shift_app/       Flutter iOS/Android 앱
flutter_engine/  순수 Dart 서캐디언 계산 엔진
logic/           엑셀 근무표 파싱 FastAPI 백엔드
docs/            기획·구현 문서
```

## 운영 측 빠른 실행: iOS 시뮬레이터 + 게스트 모드

### 1. 준비물

- macOS
- Xcode와 iOS Simulator
- Flutter SDK
- CocoaPods
- 인터넷 연결

Flutter가 정상 설치됐는지 확인합니다.

```bash
flutter doctor
```

`shift_app/pubspec.yaml`의 Dart SDK 조건을 충족하는 Flutter 버전을 사용해야
합니다. `flutter doctor`에서 Xcode 또는 CocoaPods 오류가 나오면 해당 항목을
먼저 해결합니다.

### 2. 의존성 설치

저장소 루트에서 실행합니다.

```bash
cd shift_app
flutter pub get
cd ios
pod install
cd ..
```

### 3. iOS Simulator 실행

```bash
open -a Simulator
flutter devices
```

목록에 표시된 iPhone 시뮬레이터 ID로 앱을 실행합니다.

```bash
flutter run -d <SIMULATOR_ID>
```

기기가 하나만 연결돼 있다면 `flutter run`만 사용해도 됩니다.

### 4. 앱 진입

1. 첫 화면에서 `게스트로 계속하기`를 선택합니다.
2. 근무 시각, 조명, 생활 습관, 피부 상태 온보딩을 진행합니다.
3. Apple Health 단계에서는 데모 수면 데이터를 확인합니다.
4. 근무표 등록에서 `패턴 선택 + 캘린더 편집`을 선택하면 파일 없이 진행할 수 있습니다.
5. 근무표 확인 후 홈으로 이동합니다.

게스트 모드는 Supabase publishable key가 없어도 동작합니다.

## 권장 시연 순서

1. 홈에서 오늘 권장 취침과 행동 넛지를 확인합니다.
2. `최근 2주 권장 수면량` 그래프에서 필요 수면 대비 부족분을 확인합니다.
3. `AI 오늘의 한 줄`에서 수면 우선 개인화 조언을 확인합니다.
4. `상태·고민 전달`에서 상태 태그와 고민을 입력합니다.
5. AI 결과 화면에서 원인, 개인 데이터 근거, 해결 행동과 AAC 데모 제품을 확인합니다.
6. `리듬 자세히 보기`에서 주간·월간·근무루틴별 변화를 전환합니다.
7. 설정의 `웨어러블 연동`에서 Apple Health 사전 동의와 동기화 화면을 확인합니다.
8. 홈 하단 피부 루틴과 `DEMO` 제품 5종을 확인합니다.

## 목업 데이터 안내

시뮬레이터와 디버그 시연에서는 다음 데이터를 목업으로 제공합니다.

- 최근 수면 시작·종료와 수면 시간
- HRV 개인 기준값
- 안정시 심박수
- Apple Watch 연결 및 최근 동기화 상태
- 필요 수면량과 수면 부족 그래프
- AAC 클렌저·미스트·세럼·크림·선케어 제품

Apple Watch는 앱에 직접 연결하는 것이 아니라
`Apple Watch → iPhone 건강 앱 → HealthKit → 슬립레디` 경로로 연동됩니다.
현재 해커톤 시연은 동일한 데이터 형식의 목업값을 사용합니다.

## 엑셀 근무표 업로드

`.xlsx` 또는 `.xls` 파일을 지원합니다. 파일 업로드는 Railway의 로스터 파싱
API를 호출하므로 인터넷 연결이 필요합니다.

```text
POST https://shift-roster-api-production.up.railway.app/roster/parse
```

시뮬레이터에서 파일 선택이 어려우면 `패턴 선택 + 캘린더 편집`으로 진행하는
것이 가장 안정적입니다.

## AI 인사이트

AI 인사이트는 Supabase Edge Function을 통해 Gemini 응답을 생성합니다.

```text
POST https://fthdvkrufjolrfuopvma.supabase.co/functions/v1/report
```

(2026-08-20: 원래 프로젝트 오너 초대가 막혀 새 프로젝트로 옮김. 함수
소스는 `shift_app/supabase/functions/report/index.ts`. 지금은
`gapMinutes`/`sleepDebtMin`/`shiftPattern` 3개만 프롬프트에 반영되고,
클라이언트가 같이 보내는 피부 프로필·상태 메모는 아직 안 실린다.)

회원가입 또는 설정에서 AI 인사이트 사용에 동의해야 외부 AI 요청을
보냅니다. 네트워크 요청에 실패하면 앱 내부의 개인화 폴백 문구를 사용합니다.

AI에는 근무 유형, 나이트 횟수, 수면 부족, 권장 취침, 직접 제출한 상태·고민,
최근 14일 반복 횟수와 피부 프로필의 요약만 전달됩니다.

## Supabase 회원가입·로그인 설정: 선택

게스트 시연에는 필요하지 않습니다. 실제 이메일 회원가입과 사용자별 데이터
저장을 사용할 때만 설정합니다.

### 1. Publishable key

새 프로젝트(`aza2o-shift-report`)의 publishable key:

```text
sb_publishable_NHSYLKAag3fpz0noLFlbQg_KZacuPe2
```

`service_role`/secret key는 모바일 앱에 절대 넣지 않습니다.

```bash
flutter run \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_NHSYLKAag3fpz0noLFlbQg_KZacuPe2
```

### 2. DB 마이그레이션

`shift_app/supabase/migrations/`의 두 파일은 새 프로젝트에 이미
적용돼 있습니다(2026-08-20). 다시 적용해야 하면 Dashboard SQL Editor에서
파일명 순서(생성일 접두사)대로 실행하면 됩니다 — 첫 번째가 사용자
프로필+RLS, 두 번째가 피부 프로필+날짜별 상태·고민 기록.

### 3. 이메일 인증

Supabase Dashboard의 `Authentication → Sign In / Providers → Email`에서
설정합니다. `Confirm email`이 켜져 있으면 가입 후 인증 메일의 링크를 눌러야
로그인할 수 있습니다. 심사 시 빠른 시연이 필요하면 관리자가 이 옵션을 끌 수
있습니다.

## VS Code에서 실행

1. VS Code에서 `shift_app` 폴더를 엽니다.
2. Flutter와 Dart 확장을 설치합니다.
3. `open -a Simulator`로 시뮬레이터를 실행합니다.
4. VS Code 하단에서 iPhone Simulator를 선택합니다.
5. `lib/main.dart`를 열고 `F5`를 실행합니다.

기기 목록이 보이지 않으면 다음 명령을 실행한 뒤 VS Code를 다시 불러옵니다.

```bash
flutter devices
flutter doctor
```

## 문제 해결

### CocoaPods 오류

```bash
cd shift_app/ios
pod repo update
pod install
cd ..
```

### 의존성 또는 캐시 오류

```bash
cd shift_app
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter run
```

### 시뮬레이터에서 Apple Health 권한창이 나오지 않음

정상입니다. 시뮬레이터는 실제 Apple Watch 건강 데이터를 제공하지 않으므로
앱 내부 사전 동의와 목업 동기화 화면을 사용합니다.

### AI 답변이 나오지 않음

- 설정에서 `AI 인사이트 사용`이 켜져 있는지 확인합니다.
- 인터넷 연결을 확인합니다.
- Edge Function 장애 시 새로고침 후 앱 내부 폴백 답변을 확인합니다.

### 엑셀 파일을 선택할 수 없음

- 파일 확장자가 `.xlsx` 또는 `.xls`인지 확인합니다.
- iOS Files 앱의 `다운로드` 또는 `나의 iPhone` 위치를 확인합니다.
- 운영 시연에서는 파일 없이 `패턴 선택 + 캘린더 편집`을 권장합니다.

## 백엔드 로컬 실행: 선택

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn logic.main:app --reload --port 8001
```

## 참고

- 계산 엔진은 `flutter_engine/`의 순수 Dart 코드입니다.
- 서캐디언 모델 검증 내용은 `flutter_engine/README.md`에 있습니다.
- 세부 기획과 구현 상태는 `docs/` 문서를 참고합니다.
