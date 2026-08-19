# SHIFT

교대근무자(간호사 등)를 위한 수면·일주기 리듬 관리 앱. 근무표를 넣으면
Process C(DLMO, 일주기 위상)와 Process S(수면압력) 모델로 개인화된 취침
타이밍을 계산하고, 넛지(알림)와 AI 리포트로 알려준다.

## 구조 (모노레포)

```
shift_app/       Flutter 클라이언트 (iOS/Android)
flutter_engine/  순수 Dart 서캐디언 계산 엔진 — Flutter 의존성 없음, 골든
                  벡터로 Python 원본(Arcascope circadian) 대비 검증됨
logic/           FastAPI 백엔드 — 지금 실제로 필요한 엔드포인트는
                  POST /roster/parse(엑셀 근무표 파싱) 하나뿐
supabase/        DB 마이그레이션 초안(SQL) — 아직 미적용, 리뷰 대기
docs/            기획서·구현 체크리스트·룰엔진 스펙 문서
```

계산(서캐디언 모델, 넛지 룰엔진)은 전부 클라이언트(`flutter_engine`)에서
돈다 — 서버는 "엑셀 파싱"과 "AI 리포트 문구 생성"만 담당한다. 자세한 배경은
`docs/SHIFT_프론트엔드_기획서.md` 참고.

## 배포 상태

| 구성요소 | 위치 | 용도 |
|---|---|---|
| 로스터 엑셀 파싱 (`logic/`) | Railway — `https://shift-roster-api-production.up.railway.app` | `POST /roster/parse` |
| AI 리포트 코멘트 생성 | Supabase Edge Function — `https://zfwmwplxezqtxxbgmieb.supabase.co/functions/v1/report` | Gemini 기반, `POST` (gapMinutes/sleepDebtMin/shiftPattern → comment) |
| DB 스키마 | `supabase/migrations/0001_shift_schema.sql` | **아직 미적용.** 로컬 전용(Drift) 대신 Supabase Postgres로 가기로 함 — 적용 전 팀 리뷰 필요 |

`logic/`을 다시 배포하려면 저장소 루트에 있는 `Procfile`/`requirements.txt`/
`.python-version`이 Railway(Railpack)가 그대로 인식하는 배포 설정이다.

> ⚠️ 위 두 엔드포인트 모두 **인증 없이(anon) 호출 가능**하다 — 클라이언트
> 앱에 어차피 URL이 그대로 박히므로 README에 적어도 새로운 노출은 아니지만,
> `report`는 호출마다 Gemini API 비용이 나가므로 rate limit/인증을 붙이는
> 걸 공개 전에 고려할 것.

## 로컬 개발

### Flutter 앱 (`shift_app/`)

```bash
cd shift_app
flutter pub get
flutter test
flutter run            # 시뮬레이터/실기기
```

### 서캐디언 엔진 (`flutter_engine/`)

```bash
cd flutter_engine
dart pub get
dart test               # 골든 벡터 검증 포함
```

`shift_app`은 이 패키지를 `path:` 의존성(`../flutter_engine`)으로 물고
있어서 별도 배포 없이 로컬 소스가 바로 반영된다.

### 백엔드 (`logic/`)

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn logic.main:app --reload --port 8001
```

## 알려진 미완성 항목

`docs/SHIFT_프론트엔드_구현체크리스트.md`가 최신 상태를 추적한다. 요약:

- **HealthKit/Health Connect 실측 연동** — 미착수. 지금은 전부 데모 수면
  세션으로 근사한다(로그인 → 온보딩 → 로스터 확인 흐름 자체는 완료돼
  있음).
- **서버 DB 스키마** — `supabase/migrations/0001_shift_schema.sql`에
  초안 있음, 적용 전 리뷰 대기.
- **로컬 알림 예약(`flutter_local_notifications`)** — iOS pending 알림
  64개 제한, Android 12+ 정확한 알람 권한 등 플랫폼별 제약이
  `docs/SHIFT_프론트엔드_기획서.md` §7-2에 정리돼 있음.

## 라이선스 / 데이터 출처

일주기 리듬 계산은 Arcascope `circadian`(Python, MIT)의 4개 위상 모델을
Dart로 포팅한 것이다 — 자세한 검증 내역은 `flutter_engine/README.md` 참고.
