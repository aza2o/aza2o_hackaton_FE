# shift_app

SHIFT의 Flutter 클라이언트. 저장소 전체 구조/배경은 루트 `README.md` 참고.

## 실행

```bash
flutter pub get
flutter run
```

`../flutter_engine`를 `path:` 의존성으로 물고 있어서(`pubspec.yaml`),
서캐디언 계산 로직을 고치면 `flutter pub get` 없이도 바로 반영된다.

## 테스트

```bash
flutter test
```

## 이 앱이 의존하는 외부 서버

- `lib/services/roster_api.dart` — 로스터 엑셀 업로드 파싱(`logic/` FastAPI,
  Railway 배포). 로컬 서버로 돌리려면 `_baseUrl`을 맥 LAN IP로 바꿀 것
  (`ipconfig getifaddr en0`) — 실기기는 `127.0.0.1`을 폰 자신으로 인식한다.
- `lib/services/report_api.dart` — AI 리포트 코멘트(Supabase Edge
  Function, Gemini).

## 알림/실기기 관련 참고

- iOS 실기기 빌드는 Xcode 서명(development team)이 필요하다
  (`ios/Runner.xcodeproj`).
- 무선 디버깅(`flutter run -d <wireless-device-id>`)은 Dart VM Service
  연결이 자주 타임아웃난다 — 안 되면 USB로 연결해서 재시도할 것. 앱
  설치·실행 자체는 VM 연결 실패와 무관하게 보통 성공한다(hot reload만
  못 씀).

## 알려진 미완성 항목

루트 `README.md`의 "알려진 미완성 항목" 및
`../docs/SHIFT_프론트엔드_구현체크리스트.md` 참고.
