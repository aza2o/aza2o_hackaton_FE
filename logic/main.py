"""
SHIFT 백엔드 API.

⚠️ 2026-08-18 아키텍처 확정(`SHIFT_프론트엔드_기획서.md` 상단): 계산은
전부 `flutter_engine`(Dart, 클라이언트)으로 이관됐다. 아래 "연산이
백엔드에 있는 이유"는 그 이전 설계 근거이고, `/plan`·`/render/{kind}`는
이 새 아키텍처 기준으로는 더 이상 쓰지 않는 경로다(폐기하진 않았음 —
아직 이걸 참조하는 데모/코드가 있을 수 있어 지우지 않고 남겨둠). 지금
서버에 실제로 필요한 건 `/roster/parse` 하나뿐이다.

연산이 백엔드에 있는 이유(구 설계):
  1) Arcascope/circadian은 논문 저자(Walch·Hannay) 직접 개발이라 재현성
     논쟁이 없다. Dart로 포팅하면 이 논거가 소멸한다.
  2) 재계산은 하루 1~3회(온보딩, 근무표 변경, 헬스 동기화)뿐이다.
     인터랙티브 연산이 아니므로 클라이언트에서 돌릴 이유가 없다.

알림은 서버 푸시가 아니라 로컬 알림으로 쏜다:
  백엔드가 향후 N일치 넛지 스케줄을 반환 → Flutter가 전부 로컬 예약.
  오프라인 동작, FCM/APNs 불필요, 무엇보다 발화 시각이 정확하다.
  넛지는 "퇴근 20분 전 차광"처럼 타이밍이 곧 효과다.

실행: uvicorn logic.main:app --reload
"""

from __future__ import annotations

import json
from datetime import date

from fastapi import FastAPI, File, Form, HTTPException, Response, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from .constants import DEFAULT_SHIFT_TIMINGS, ShiftTiming, ShiftType, UserProfile
from .pipeline import parse_roster, run
from .roster_parse import parse_roster_excel

app = FastAPI(title="SHIFT Engine", version="0.1.0")

# 개발 중 Flutter web(localhost:다른 포트)에서 바로 호출할 수 있도록 허용.
# 배포 전에는 실제 앱 오리진으로 좁혀야 한다.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class ProfileIn(BaseModel):
    workplace_lighting: str = Field("normal", pattern="^(bright|normal|dim)$")
    bedroom_lighting: str = Field("curtain", pattern="^(blackout|curtain|none)$")
    commute_minutes: float = 20.0
    latitude: float = 35.87
    longitude: float = 128.60
    # 하드코딩 금지 — 병원마다 근무 시각이 다르다
    shift_hours: dict[str, tuple[float, float]] | None = None

    def to_profile(self) -> UserProfile:
        timings = dict(DEFAULT_SHIFT_TIMINGS)
        for k, (s, e) in (self.shift_hours or {}).items():
            timings[ShiftType(k)] = ShiftTiming(s, e)
        return UserProfile(
            shift_timings=timings,
            workplace_lighting=self.workplace_lighting,
            bedroom_lighting=self.bedroom_lighting,
            commute_minutes=self.commute_minutes,
            latitude=self.latitude,
            longitude=self.longitude,
        )


class PlanRequest(BaseModel):
    roster: str = Field(..., description="예: 'DDEENNOO'", min_length=1)
    start_date: date
    profile: ProfileIn = ProfileIn()
    sleep_efficiency: dict[int, float] | None = None
    # 콜드스타트 첫 주에는 False — 문헌 상수 기반 발화만
    evaluate_effects: bool = True


@app.post("/plan")
def create_plan(req: PlanRequest):
    roster = parse_roster(req.roster)
    if not roster:
        raise HTTPException(400, "roster에 D/E/N/O 문자가 없습니다")
    if len(roster) > 42:
        raise HTTPException(400, "roster는 최대 42일까지 지원합니다")

    plan, _ = run(roster, req.profile.to_profile(), req.start_date,
                  sleep_efficiency=req.sleep_efficiency,
                  evaluate_effects=req.evaluate_effects,
                  render=False)
    return plan.to_dict()


@app.post("/render/{kind}")
def render(kind: str, req: PlanRequest):
    """kind: actogram | alertness | spread"""
    if kind not in {"actogram", "alertness", "spread"}:
        raise HTTPException(404, "unknown chart")
    roster = parse_roster(req.roster)
    _, images = run(roster, req.profile.to_profile(), req.start_date,
                    sleep_efficiency=req.sleep_efficiency,
                    evaluate_effects=req.evaluate_effects, render=True)
    return Response(content=images[kind], media_type="image/png")


@app.post("/roster/parse")
async def roster_parse(
    file: UploadFile = File(...),
    user_name: str = Form(...),
    # 하드코딩 금지 원칙과 별개로, 연도/월은 항상 클라이언트가 "지금 보고
    # 있는 월"을 함께 보내기로 했다(프론트엔드 기획서 §4-2-1) — 그러면
    # "연도 누락" 분기(needs_year)가 애초에 생기지 않는다.
    year_hint: int = Form(...),
    month_hint: int = Form(...),
    # multipart form 필드는 전부 문자열이라 JSON으로 인코딩해 보낸다.
    known_code_mappings: str = Form("{}"),
    # needs_row_selection 이후 재요청 시에만 채워짐.
    row_index: int | None = Form(None),
):
    """§4-2-1 계약. 본인 행만 메모리에서 읽고 원본은 저장하지 않는다
    (`roster_parse.py` 모듈 docstring 참고)."""
    content = await file.read()
    try:
        mappings = json.loads(known_code_mappings) if known_code_mappings else {}
    except json.JSONDecodeError:
        mappings = {}

    return parse_roster_excel(
        file_bytes=content,
        filename=file.filename or "",
        user_name=user_name,
        year=year_hint,
        month=month_hint,
        known_code_mappings=mappings,
        row_index=row_index,
    )


@app.get("/health")
def health():
    return {"ok": True}
