# SHIFT 서캐디언 엔진 — Dart 포팅

Arcascope `circadian` v1.0.3(Python, MIT)의 4개 위상 모델(Forger99·Hannay19·
Hannay19TP·Jewett99)을 클라이언트(Flutter)에서 계산하기 위해 옮긴 것이다.
`SHIFT_개발기획서.md` §3-3이 원래 "서버 계산"을 확정 사항으로 명시했던 걸
뒤집은 결정이라, **재현성 검증을 실행 테스트로 직접 확인**하는 걸 최우선으로
삼았다.

## 검증 상태

`dart test`로 골든 벡터 17개 **전부 통과** (2026-08-17, `dart-sdk` 3.13.0).

골든 벡터(`test/golden_vectors.json`)는 Python 원본 패키지를 실제로 설치해서
72시간·dt=0.1h·16L/8D 반복 조도 스케줄로 직접 뽑은 값이다. 이 값과 Dart 포팅
결과를 상태값(1e-3 허용오차)·DLMO 시각(0.1h 허용오차)·`equilibrate()` 수렴
결과까지 대조한다.

**검증 범위의 한계**: 지금 골든 벡터는 규칙적인 16L/8D 스케줄 1가지뿐이다.
실제 로스터 기반 lux(t)는 근무·통근·수면 구간이 뒤섞인 불규칙한 입력이므로,
프로덕션에 붙이기 전에 **실제 로스터 샘플로 골든 벡터를 추가 생성**해서
한 번 더 검증하는 걸 권한다 (`scripts/gen_golden.py` 참고 — Python 쪽
`logic/light.py`의 `build_light_fn()` 출력을 그대로 넣으면 된다).

## 포팅 중 실제로 잡은 버그

시간축을 `h += 0.1`로 720번 누적해서 만들었더니 부동소수점 오차가 쌓여
골든 테스트가 전부 실패했다. numpy의 `arange`는 `start + i*step`(인덱스
곱셈) 방식이라 이 누적이 없다. **이 엔진의 `integrate()`/`equilibrate()`에
넘기는 모든 `time` 배열은 반드시 인덱스 곱셈으로 만들 것** — 실수하면
숫자는 그럴듯하게 나오는데 미세하게 틀려서 테스트 없이는 못 잡는다.

## 포팅되지 않은 것 (Python 원본에 있지만 여기 없음)

- `PRCFinder`, `LightSchedule.ShiftWork()`/`SlamShift()` 등 — 원본 개발기획서
  부록이 이미 "쓰지 않는다" 또는 "버그 있음, 우회 필요"로 명시한 것들이라
  포팅 대상에서 제외
- `Hilaire07`, `Breslow13`, `Skeldon23` 모델 — SHIFT는 4모델(Forger99·
  Hannay19·Hannay19TP·Jewett99)만 쓰므로 제외
- `scale_steps_to_activity()`(걸음 수 기반 활동량 근사) — Process C 엔진과
  무관, 필요 시 별도 포팅

## 구조

```
lib/
  circadian_model.dart   — 공통 베이스: RK4 적분기, equilibrate, findPeaks
  models/
    forger99.dart
    hannay19.dart         — SHIFT 기본(primary) 모델
    hannay19_tp.dart
    jewett99.dart
test/
  golden_vectors.json     — Python 원본에서 뽑은 참조값
  golden_vectors_test.dart
```

Flutter 의존성이 전혀 없는 순수 Dart 패키지다. 실제 앱에서는 이 `lib/`
디렉터리를 그대로 `lib/engine/`(또는 원하는 위치) 아래로 옮기면 된다.

## 실행

```bash
dart pub get
dart test
```

## 로스터 → lux(t) 포팅 (`lib/roster/`) — 완료, 검증됨

`logic/light.py`(`plan_sleep`, `build_light_fn`, `light_series`,
`intervention_windows`, `sun_times`)를 `lib/roster/light_schedule.dart`로
포팅했다. 골든 벡터 4종(`test/light_golden.json`) 전부 통과
(2026-08-18) — `sunTimes`의 NOAA 근사식, `planSleep`의 수면창, 720개
lux 샘플, 개입창(`intervention_windows`)까지 Python 원본과 대조 확인.
ODE 엔진 포팅 때와 달리 첫 시도에 전부 통과했다(시간축을 처음부터
`i * dt`로 만들었기 때문 — 이전 버그를 알고 있었던 덕).

`lib/roster/constants.dart`에 `ShiftType`/`ShiftTiming`/`UserProfile`도
같이 옮겼다. `logic/constants.py`와 동일 네이밍 규칙(값은 그대로, 필드명만
camelCase)을 유지했다.

## 다음 단계 (아직 안 된 것)

1. **실측 데이터 3계층 fallback** — `SHIFT_실측데이터_통합_기획서.md`의
   원칙(실측 > 온보딩 선언 > 기본 상수)을 `light_schedule.dart`의
   `planSleep()`/`buildLightFn()`에 반영. 지금은 계획된 수면창만 쓴다
   (§원칙 3 "데이터 0에서도 동작"은 이미 만족).
2. **넛지 하이브리드 계산** — "할당 사항" 문서의 고정 오프셋 넛지
   (`caffeineCutoff = 목표취침 - 528분` 등)와, Python `logic/nudge.py`의
   반사실 시뮬레이션(개입 전후 DLMO 이동량 비교)을 함께 쓰기로 확정됨.
   후자는 이 엔진의 `integrate()`를 개입 전/후 두 번 돌려서 DLMO 차이를
   비교하면 되므로 추가 포팅 없이 바로 구현 가능하다.
3. **Drift 스키마 병합** — "할당 사항" 문서의 7개 테이블에 `daily_plan`이
   이미 있으니, 여기에 `dlmoClock`/`modelSpreadHours`(4모델 분산) 컬럼을
   추가하는 정도로 충분해 보인다.
4. **로스터 입력 — 엑셀 1차 우선순위 확정.** "할당 사항" 문서의 "달력 +
   반복 패턴"은 2차 폴백으로 유지하고, 엑셀 파싱은 클라이언트에 없던
   기능이라 신규 구현 필요 (`logic/pipeline.py`의 파싱 규칙 참고 — 단,
   기존 개발기획서는 파싱을 서버에서 한다고 했으므로, 계산은 클라이언트로
   옮기더라도 **엑셀 파싱만은 서버에 남기는 하이브리드**가 합리적일 수
   있다 — `.xls`(BIFF) 지원 라이브러리가 Dart 생태계에 마땅치 않기
   때문. 이 부분은 별도 확인 필요).
