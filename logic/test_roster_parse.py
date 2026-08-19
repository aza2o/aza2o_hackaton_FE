"""`roster_parse.py` 단위 테스트. 실제 openpyxl 워크북을 메모리에서
만들어 `parse_roster_excel`에 그대로 먹인다 — §4-2-1 응답 스키마의
네 가지 status(ok/needs_row_selection/error) 전부 커버."""

from __future__ import annotations

import io

import openpyxl
import pytest

from .roster_parse import parse_roster_excel

AUG_2026_DAYS = 31  # calendar.monthrange(2026, 8)[1]


def _make_xlsx(rows: list[list[object]]) -> bytes:
    wb = openpyxl.Workbook()
    ws = wb.active
    for row in rows:
        ws.append(row)
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def _header_row() -> list[object]:
    return ["이름", *range(1, AUG_2026_DAYS + 1)]


def test_기본_피벗_구조를_성공적으로_파싱한다():
    codes = (["D", "D", "E", "E", "N", "N", "O"] * 5)[:AUG_2026_DAYS]
    xlsx = _make_xlsx([
        ["○○병동 8월 근무표"],
        _header_row(),
        ["이수정", *codes],
    ])

    result = parse_roster_excel(
        file_bytes=xlsx, filename="roster.xlsx", user_name="이수정",
        year=2026, month=8, known_code_mappings={},
    )

    assert result["status"] == "ok"
    assert result["year"] == 2026 and result["month"] == 8
    assert result["shifts"]["1"] == "D"
    assert result["shifts"]["5"] == "N"
    assert len(result["shifts"]) == AUG_2026_DAYS
    assert result["unmapped_codes"] == []


def test_모르는_코드는_O로_폴백하고_unmapped_codes에_담긴다():
    codes = ["연차"] + ["D"] * (AUG_2026_DAYS - 1)
    xlsx = _make_xlsx([_header_row(), ["이수정", *codes]])

    result = parse_roster_excel(
        file_bytes=xlsx, filename="roster.xlsx", user_name="이수정",
        year=2026, month=8, known_code_mappings={},
    )

    assert result["status"] == "ok"
    assert result["shifts"]["1"] == "O"  # 안전 폴백
    assert result["unmapped_codes"] == ["연차"]


def test_known_code_mappings으로_학습된_코드는_unmapped에_안_들어간다():
    codes = ["연차"] + ["D"] * (AUG_2026_DAYS - 1)
    xlsx = _make_xlsx([_header_row(), ["이수정", *codes]])

    result = parse_roster_excel(
        file_bytes=xlsx, filename="roster.xlsx", user_name="이수정",
        year=2026, month=8, known_code_mappings={"연차": "N"},
    )

    assert result["shifts"]["1"] == "N"
    assert result["unmapped_codes"] == []


def test_이름이_여러_행에_있으면_needs_row_selection():
    codes = ["D"] * AUG_2026_DAYS
    xlsx = _make_xlsx([
        _header_row(),
        ["이수정", *codes],
        ["이수정", *codes],
    ])

    result = parse_roster_excel(
        file_bytes=xlsx, filename="roster.xlsx", user_name="이수정",
        year=2026, month=8, known_code_mappings={},
    )

    assert result["status"] == "needs_row_selection"
    assert len(result["candidates"]) == 2


def test_row_index를_주면_모호함_없이_그_행을_바로_쓴다():
    xlsx = _make_xlsx([
        _header_row(),
        ["이수정", *(["D"] * AUG_2026_DAYS)],
        ["이수정", *(["N"] * AUG_2026_DAYS)],
    ])

    result = parse_roster_excel(
        file_bytes=xlsx, filename="roster.xlsx", user_name="이수정",
        year=2026, month=8, known_code_mappings={}, row_index=2,
    )

    assert result["status"] == "ok"
    assert result["shifts"]["1"] == "N"


def test_이름을_못_찾으면_error():
    xlsx = _make_xlsx([_header_row(), ["다른사람", *(["D"] * AUG_2026_DAYS)]])

    result = parse_roster_excel(
        file_bytes=xlsx, filename="roster.xlsx", user_name="이수정",
        year=2026, month=8, known_code_mappings={},
    )

    assert result["status"] == "error"


def test_날짜_헤더를_못_찾으면_error():
    xlsx = _make_xlsx([["아무", "의미", "없는", "표"], ["이수정", 1, 2, 3]])

    result = parse_roster_excel(
        file_bytes=xlsx, filename="roster.xlsx", user_name="이수정",
        year=2026, month=8, known_code_mappings={},
    )

    assert result["status"] == "error"


def test_지원하지_않는_확장자는_error():
    result = parse_roster_excel(
        file_bytes=b"not really a spreadsheet", filename="roster.csv",
        user_name="이수정", year=2026, month=8, known_code_mappings={},
    )

    assert result["status"] == "error"
