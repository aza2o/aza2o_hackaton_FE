# logic — SHIFT 백엔드

계산 로직은 전부 클라이언트(`flutter_engine`)로 이관됐다(2026-08-18
아키텍처 확정, `main.py` 상단 docstring 참고). 이 서버가 지금 실제로
맡는 건 **엑셀 근무표 파싱 하나뿐**이다:

```
POST /roster/parse
GET  /health
```

계약 상세는 `../docs/SHIFT_프론트엔드_기획서.md` §4-2-1.

## 실행

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn logic.main:app --reload --port 8001
```

`logic.main:app` 형태로 실행해야 한다(패키지 상대 임포트 사용 — 저장소
루트에서 실행할 것, `logic/` 안에서 `uvicorn main:app`으로 실행하면 깨짐).

## 테스트

```bash
pytest
```

## 배포

Railway에 배포돼 있다(`https://shift-roster-api-production.up.railway.app`).
저장소 루트의 `Procfile`/`requirements.txt`/`.python-version`이 배포 설정이다
— `logic/requirements.txt`가 원본이고, 루트 `requirements.txt`는 그걸
`-r`로 참조만 한다.

## 개인정보 처리 원칙 (협상 불가)

업로드된 엑셀에서 **본인 행만 추출**하고, 원본 파일은 응답 직후 즉시
폐기한다. 타인 행은 어떤 형태로도 저장·로그하지 않는다
(`roster_parse.py` 모듈 docstring 참고).
