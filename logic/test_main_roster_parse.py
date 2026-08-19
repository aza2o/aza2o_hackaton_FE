"""`/roster/parse` 엔드포인트 통합 테스트 — 실제 HTTP 레이어(폼 파싱,
JSON 인코딩)까지 거쳐서 `roster_parse.py`가 맞물리는지 확인한다."""

from __future__ import annotations

import io

import openpyxl
from fastapi.testclient import TestClient

from .main import app

client = TestClient(app)


def _make_xlsx(rows: list[list[object]]) -> bytes:
    wb = openpyxl.Workbook()
    ws = wb.active
    for row in rows:
        ws.append(row)
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def test_엔드포인트가_정상_파일을_ok로_응답한다():
    codes = (["D", "D", "E", "E", "N", "N", "O"] * 5)[:31]
    xlsx = _make_xlsx([["이름", *range(1, 32)], ["이수정", *codes]])

    resp = client.post(
        "/roster/parse",
        files={"file": ("roster.xlsx", xlsx,
                         "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")},
        data={"user_name": "이수정", "year_hint": "2026", "month_hint": "8"},
    )

    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["shifts"]["1"] == "D"
    assert body["unmapped_codes"] == []


def test_known_code_mappings_json_문자열이_반영된다():
    xlsx = _make_xlsx([["이름", *range(1, 32)], ["이수정", "연차", *(["D"] * 30)]])

    resp = client.post(
        "/roster/parse",
        files={"file": ("roster.xlsx", xlsx,
                         "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")},
        data={
            "user_name": "이수정", "year_hint": "2026", "month_hint": "8",
            "known_code_mappings": '{"연차":"N"}',
        },
    )

    body = resp.json()
    assert body["shifts"]["1"] == "N"
    assert body["unmapped_codes"] == []


def test_row_index로_재요청하면_그_행을_바로_쓴다():
    xlsx = _make_xlsx([
        ["이름", *range(1, 32)],
        ["이수정", *(["D"] * 31)],
        ["이수정", *(["N"] * 31)],
    ])

    ambiguous = client.post(
        "/roster/parse",
        files={"file": ("roster.xlsx", xlsx,
                         "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")},
        data={"user_name": "이수정", "year_hint": "2026", "month_hint": "8"},
    )
    assert ambiguous.json()["status"] == "needs_row_selection"
    row = ambiguous.json()["candidates"][1]["row"]

    resolved = client.post(
        "/roster/parse",
        files={"file": ("roster.xlsx", xlsx,
                         "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")},
        data={
            "user_name": "이수정", "year_hint": "2026", "month_hint": "8",
            "row_index": str(row),
        },
    )
    assert resolved.json()["status"] == "ok"
    assert resolved.json()["shifts"]["1"] == "N"
