"""
로스터 엑셀 파싱. `SHIFT_프론트엔드_기획서.md` §4-2-1 계약 구현.

MVP 범위 결정(2026-08-18, 사용자 협의): 병합 셀·다중 헤더 같은 양식
파편화 대응은 하지 않는다. 파싱 결과는 항상 `RosterConfirmScreen`의 셀 탭
편집(D→E→N→O 순환)으로 사용자가 고칠 수 있으므로, 파서가 완벽하지 않아도
제품이 깨지지 않는다 — "반드시 사용자 확인·수정 화면을 거친다"는 원칙
(`SHIFT_개발기획서.md` §5-2)이 파서의 약점을 흡수하는 구조다.

지원: 행=사람, 열=1~N일인 피벗 구조에서 날짜 헤더 행과 본인 행을 찾아
교차 지점을 읽는다.
미지원: 병합 셀, 다중 헤더 행, 세로형(사람=열) 양식 — 헤더/본인 행을
못 찾으면 status="error"로 떨어지고, 클라이언트는 이미 있는 "2차: 패턴
선택 + 캘린더 편집" 경로로 폴백한다.

개인정보 처리: 파일 바이트는 이 모듈 안에서만 메모리로 다루고 디스크에
쓰지 않는다 — 함수가 끝나면(응답을 반환하면) 원본은 자동으로 사라진다.
"본인 행만 추출한 뒤 원본 파일을 즉시 폐기"(§5-2-4) 요구사항을 "애초에
저장하지 않음"으로 만족시킨다.
"""

from __future__ import annotations

import calendar
import io

_KNOWN_CODES: dict[str, str] = {
    "D": "D", "DAY": "D", "데이": "D", "주": "D", "주간": "D",
    "E": "E", "EVE": "E", "EVENING": "E", "이브": "E", "이브닝": "E", "저": "E", "저녁": "E",
    "N": "N", "NIGHT": "N", "나이트": "N", "야": "N", "야간": "N",
    "O": "O", "OFF": "O", "오프": "O", "휴": "O", "휴무": "O",
}


def _cell_str(v: object) -> str:
    if v is None:
        return ""
    return str(v).strip()


def _load_grid(file_bytes: bytes, filename: str) -> list[list[object]]:
    lower = filename.lower()
    if lower.endswith(".xlsx"):
        import openpyxl

        wb = openpyxl.load_workbook(io.BytesIO(file_bytes), data_only=True)
        ws = wb.worksheets[0]
        return [list(row) for row in ws.iter_rows(values_only=True)]
    if lower.endswith(".xls"):
        import xlrd

        wb = xlrd.open_workbook(file_contents=file_bytes)
        ws = wb.sheet_by_index(0)
        return [[ws.cell_value(r, c) for c in range(ws.ncols)] for r in range(ws.nrows)]
    raise ValueError(f"지원하지 않는 파일 형식: {filename}")


def _find_header_row(grid: list[list[object]], month_days: int) -> tuple[int, dict[int, int]] | None:
    """day(1..month_days) -> 열 인덱스 매핑을 담은 헤더 행을 찾는다.

    날짜 숫자가 가장 많이 발견되는 행을 헤더로 채택한다. 절반 미만이면
    "헤더가 아니다"로 보고 포기한다(병합 셀·비정형 양식 조기 감지).
    """
    best: tuple[int, dict[int, int]] | None = None
    for r, row in enumerate(grid):
        day_cols: dict[int, int] = {}
        for c, v in enumerate(row):
            try:
                n = int(v)  # type: ignore[arg-type]
            except (TypeError, ValueError):
                continue
            if 1 <= n <= month_days and n not in day_cols:
                day_cols[n] = c
        if best is None or len(day_cols) > len(best[1]):
            best = (r, day_cols)
    if best is None or len(best[1]) < month_days // 2:
        return None
    return best


def _find_name_rows(grid: list[list[object]], user_name: str) -> list[int]:
    target = user_name.strip()
    rows = []
    for r, row in enumerate(grid):
        if any(_cell_str(v) == target for v in row):
            rows.append(r)
    return rows


def _map_code(raw: str, known_code_mappings: dict[str, str]) -> str | None:
    if raw in known_code_mappings:
        return known_code_mappings[raw]
    return _KNOWN_CODES.get(raw.upper())


def parse_roster_excel(
    *,
    file_bytes: bytes,
    filename: str,
    user_name: str,
    year: int,
    month: int,
    known_code_mappings: dict[str, str],
    row_index: int | None = None,
) -> dict:
    """§4-2-1 응답 스키마 그대로 반환: status가 ok/needs_row_selection/error."""
    try:
        grid = _load_grid(file_bytes, filename)
    except Exception as e:  # noqa: BLE001 — 파일 파싱 실패는 전부 사용자에게 error로 보고
        return {"status": "error", "message": f"파일을 읽을 수 없어요: {e}"}

    month_days = calendar.monthrange(year, month)[1]
    header = _find_header_row(grid, month_days)
    if header is None:
        return {"status": "error", "message": f"날짜 헤더(1~{month_days}일)를 찾지 못했어요"}
    header_row_idx, day_cols = header

    if row_index is not None:
        name_row = row_index
    else:
        name_rows = [r for r in _find_name_rows(grid, user_name) if r != header_row_idx]
        if not name_rows:
            return {"status": "error", "message": f"'{user_name}' 행을 찾지 못했어요"}
        if len(name_rows) > 1:
            candidates = []
            for r in name_rows:
                name_cell = next((_cell_str(v) for v in grid[r] if _cell_str(v)), "")
                candidates.append({"row": r, "name": name_cell})
            return {"status": "needs_row_selection", "candidates": candidates}
        name_row = name_rows[0]

    if not (0 <= name_row < len(grid)):
        return {"status": "error", "message": "선택한 행이 시트 범위를 벗어났어요"}

    row = grid[name_row]
    shifts: dict[str, str] = {}
    unmapped: set[str] = set()
    for day, col in sorted(day_cols.items()):
        raw = _cell_str(row[col]) if col < len(row) else ""
        if not raw:
            continue
        mapped = _map_code(raw, known_code_mappings)
        if mapped is None:
            unmapped.add(raw)
            mapped = "O"  # 안전 폴백 — 확인 화면에서 탭으로 고침(모듈 docstring 참고)
        shifts[str(day)] = mapped

    return {
        "status": "ok",
        "year": year,
        "month": month,
        "shifts": shifts,
        "unmapped_codes": sorted(unmapped),
    }
