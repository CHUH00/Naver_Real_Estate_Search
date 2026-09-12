#!/usr/bin/env python3
"""
네이버 부동산 매물 정보를 스크래핑해서 Excel 파일에 누적 저장하는 도구.

사용법:
    python3 naver_land_scraper.py <네이버_부동산_URL>

예시:
    python3 naver_land_scraper.py "https://new.land.naver.com/complexes/338?articleNo=2632668008"

옵션:
    --output, -o    저장할 Excel 파일 경로 (기본값: 스크립트와 같은 폴더)
    --debug         API 응답 원문 출력
    --browser       직접 API 호출 대신 브라우저 방식 강제 사용
"""

import sys
import re
import time
import json
import argparse
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse, parse_qs

import requests
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

EXCEL_FILE = Path(__file__).parent / "네이버_부동산_매물.xlsx"

HEADERS_MAP = [
    ("수집일시",                "collected_at"),
    ("매물번호",                "article_no"),
    ("단지명",                  "complex_name"),
    ("주소",                    "address"),
    ("거래유형",                "trade_type"),
    ("매매가 (만원)",           "price_main"),
    ("기보증금",                 "rent_price"),
    ("입주가능일",              "move_in_date"),
    ("공급면적 (평)",           "area_supply"),
    ("전용면적 (평)",           "area_exclusive"),
    ("방향",                    "direction"),
    ("단지세대수/동세대수",      "household_by_type"),
    ("총주차대수 (대)",         "parking_count"),
    ("방수/화장실수 (개)",      "rooms_baths"),
    ("해당층/총층",             "floor"),
    ("현관구조",                "entrance_type"),
    ("난방 (방식/연료)",        "heating"),
    ("관리비 (만원)",           "maintenance"),
    ("건축물 용도",             "building_use"),
    ("매물특징",                "feature"),
    ("중개사",                  "dealer_name"),
    ("URL",                     "url"),
]


# ─── URL 파싱 ──────────────────────────────────────────────────────────────────

def parse_url(url: str) -> tuple[str, str]:
    """URL에서 articleNo와 complexNo 추출."""
    parsed = urlparse(url)
    qs = parse_qs(parsed.query)

    article_no = re.sub(r"\D+$", "", qs.get("articleNo", [""])[0])  # 숫자 이외 trailing 문자 제거
    complex_no = ""

    m = re.search(r"/complexes/(\d+)", parsed.path)
    if m:
        complex_no = m.group(1)

    m = re.search(r"/articles/(\d+)", parsed.path)
    if m and not article_no:
        article_no = m.group(1)

    if not article_no:
        raise ValueError(f"URL에서 매물번호(articleNo)를 찾을 수 없습니다:\n{url}")

    return article_no, complex_no


# ─── API 호출 (직접) ───────────────────────────────────────────────────────────

def fetch_via_api(article_no: str, complex_no: str, retries: int = 3, log=print) -> dict:
    """네이버 부동산 REST API 직접 호출."""
    session = requests.Session()
    session.headers.update({
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/126.0.0.0 Safari/537.36"
        ),
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "ko-KR,ko;q=0.9,en-US;q=0.8",
        "Referer": f"https://new.land.naver.com/complexes/{complex_no}",
        "Sec-Fetch-Dest": "empty",
        "Sec-Fetch-Mode": "cors",
        "Sec-Fetch-Site": "same-origin",
    })

    api_url = f"https://new.land.naver.com/api/articles/{article_no}"
    params = {"complexNo": complex_no} if complex_no else {}

    for attempt in range(retries):
        try:
            r = session.get(api_url, params=params, timeout=15)
            if r.status_code == 200:
                return r.json()
            elif r.status_code == 429:
                wait = 5 * (attempt + 1)
                log(f"  서버 요청 제한 — {wait}초 후 재시도 ({attempt + 1}/{retries})")
                time.sleep(wait)
            elif r.status_code in (401, 403):
                raise RuntimeError("인증 오류 (401/403). 브라우저 방식으로 재시도합니다.")
            else:
                raise RuntimeError(f"API 오류 {r.status_code}: {r.text[:200]}")
        except requests.RequestException as e:
            if attempt == retries - 1:
                raise RuntimeError(f"네트워크 오류: {e}")
            time.sleep(3)

    raise RuntimeError("direct_api_failed")


# ─── API 호출 (브라우저 경유) ──────────────────────────────────────────────────

def fetch_via_browser(article_no: str, complex_no: str, original_url: str, log=print) -> dict:
    """Playwright로 실제 브라우저를 열어 API 응답 가로채기.
    같은 세션에서 기보증금 전세 실거래가도 함께 조회해 _fetched_rent_price 키로 반환."""
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        raise RuntimeError(
            "playwright가 설치되지 않았습니다.\n"
            "  pip3 install playwright\n"
            "  python3 -m playwright install chromium"
        )

    captured = {}
    jwt_token = [None]

    def on_response(response):
        if (
            "data" not in captured          # 첫 번째 성공 응답만 저장, 이후 덮어쓰기 방지
            and f"api/articles/{article_no}" in response.url
            and response.status == 200
        ):
            try:
                captured["data"] = response.json()
            except Exception:
                pass

    def on_request(request):
        if jwt_token[0] is None:
            auth = request.headers.get("authorization", "")
            if auth.startswith("Bearer "):
                jwt_token[0] = auth[7:]

    navigate_url = (
        original_url
        if "articleNo=" in original_url
        else f"https://new.land.naver.com/complexes/{complex_no}?articleNo={article_no}"
    )

    log("  브라우저로 페이지 로딩 중...")
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        ctx = browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/126.0.0.0 Safari/537.36"
            ),
            locale="ko-KR",
        )
        page = ctx.new_page()
        page.on("request", on_request)
        page.on("response", on_response)
        page.goto(navigate_url, wait_until="domcontentloaded", timeout=30000)
        page.wait_for_timeout(4000)

        # 기보증금 없으면 전세 실거래가 인라인 조회 (세션 유지 중에)
        if "data" in captured and jwt_token[0] and complex_no:
            data = captured["data"]
            price_info = data.get("articlePrice", {})
            all_warrant = price_info.get("allWarrantPrice", 0) or 0
            if not all_warrant:
                try:
                    ea = float(
                        data.get("articleSpace", {}).get("exclusiveSpace")
                        or data.get("articleAddition", {}).get("area2")
                        or 0
                    )
                except (TypeError, ValueError):
                    ea = 0.0

                py_list = page.evaluate(
                    """async ([cno, jwt]) => {
                        const r = await fetch(
                            `https://new.land.naver.com/api/complexes/${cno}?sameAddressGroup=false`,
                            {headers: {'Authorization': 'Bearer ' + jwt,
                                       'Accept': 'application/json',
                                       'Referer': 'https://new.land.naver.com/'}}
                        );
                        if (!r.ok) return [];
                        const d = await r.json();
                        return (d.complexPyeongDetailList || []).map(p => ({
                            pyeongNo: String(p.pyeongNo),
                            exclusiveArea: parseFloat(p.exclusiveArea) || 0
                        }));
                    }""",
                    [complex_no, jwt_token[0]],
                ) or []

                if py_list:
                    best = (min(py_list, key=lambda p: abs(p["exclusiveArea"] - ea))
                            if ea else py_list[0])
                    rp = page.evaluate(
                        """async ([cno, pno, jwt]) => {
                            const r = await fetch(
                                `https://new.land.naver.com/api/complexes/${cno}/prices/real?tradeType=B1&areaNo=${pno}&type=table`,
                                {headers: {'Authorization': 'Bearer ' + jwt,
                                           'Accept': 'application/json',
                                           'Referer': `https://new.land.naver.com/complexes/${cno}`}}
                            );
                            if (!r.ok) return null;
                            const d = await r.json();
                            const months = d.realPriceOnMonthList || [];
                            if (!months.length) return null;
                            const latest = [...(months[0].realPriceList || [])];
                            if (!latest.length) return null;
                            latest.sort((a, b) => Number(b.tradeDate) - Number(a.tradeDate));
                            return latest[0];
                        }""",
                        [complex_no, best["pyeongNo"], jwt_token[0]],
                    )
                    if rp:
                        ps = (rp.get("formattedPrice") or "").strip()
                        dt = (rp.get("formattedTradeYearMonth") or "")[:7]
                        if ps:
                            dt = dt or datetime.now().strftime("%Y.%m")
                            captured["data"]["_fetched_rent_price"] = f"{ps} ({dt}. 거래내역)"


        browser.close()

    if "data" not in captured:
        raise RuntimeError("브라우저 방식으로도 API 응답을 가로채지 못했습니다.")

    return captured["data"]


def fetch_article(
    article_no: str,
    complex_no: str,
    original_url: str,
    force_browser: bool = False,
    log=print,
) -> dict:
    """API 호출 - 직접 시도 후 실패하면 브라우저 폴백."""
    return fetch_via_browser(article_no, complex_no, original_url, log=log)




# ─── 필드 추출 ─────────────────────────────────────────────────────────────────

def _fmt_price(amount_manwon) -> str:
    """만원 단위 숫자를 한국어 형식으로. 예: 39700 → '3억9,700'"""
    try:
        amount = int(amount_manwon)
    except (TypeError, ValueError):
        return ""
    if amount == 0:
        return ""
    if amount >= 10000:
        eok = amount // 10000
        rem = amount % 10000
        return f"{eok}억{rem:,}" if rem else f"{eok}억"
    return f"{amount:,}"


def _get(d: dict, *keys, default=""):
    for k in keys:
        if isinstance(d, dict):
            d = d.get(k, None)
            if d is None:
                return default
        else:
            return default
    return d if d is not None else default


def extract_fields(data: dict, article_no: str, url: str) -> dict:
    """API 응답에서 필요한 필드 추출."""
    detail   = data.get("articleDetail", {})
    addition = data.get("articleAddition", {})
    facility = data.get("articleFacility", {})
    space    = data.get("articleSpace", {})
    floor_d  = data.get("articleFloor", {})
    price    = data.get("articlePrice", {})
    realtor  = data.get("articleRealtor", {})
    admin    = data.get("administrationCostInfo", {})

    # 단지명
    complex_name = (
        _get(detail, "aptName")
        or _get(addition, "articleName")
        or _get(detail, "articleName")
    )
    building = _get(detail, "buildingName") or _get(addition, "buildingName")
    if building and building not in complex_name:
        complex_name = f"{complex_name} {building}"

    # 주소
    address = _get(detail, "exposureAddress") or _get(detail, "address")

    # 거래유형
    trade_type = _get(addition, "tradeTypeName") or _get(detail, "tradeTypeName")

    # 면적 (㎡ → 평 변환, 소수점 1자리)
    def _to_pyeong(val):
        try: return round(float(val) * 0.3025, 1)
        except (TypeError, ValueError): return ""

    area_supply    = _get(space, "supplySpace")    or _get(addition, "area1")
    area_exclusive = _get(space, "exclusiveSpace") or _get(addition, "area2")

    # 층: "해당층/총층"
    floor = _get(addition, "floorInfo") or (
        f"{_get(floor_d, 'correspondingFloorCount')}/{_get(floor_d, 'buildingHighestFloor')}"
        if _get(floor_d, "correspondingFloorCount") else ""
    )

    # 가격
    price_main = _get(addition, "dealOrWarrantPrc")

    # 기보증금/월세
    today_ym   = datetime.now().strftime("%Y.%m")
    rent_prc   = _get(addition, "rentPrc")
    all_warrant  = price.get("allWarrantPrice", 0)
    monthly_rent = price.get("rentPrice", 0)
    if rent_prc:
        rent_price = rent_prc                                              # 월세: API 문자열 그대로
    elif monthly_rent and monthly_rent > 0:
        rent_price = f"{_fmt_price(all_warrant)}/{_fmt_price(monthly_rent)}"
    elif all_warrant and all_warrant > 0:
        rent_price = f"{_fmt_price(all_warrant)} ({today_ym}. 실보증금)"   # 기보증금 있음
    elif data.get("_fetched_rent_price"):
        rent_price = data["_fetched_rent_price"]                           # 브라우저 세션에서 미리 조회
    else:
        rent_price = ""                                                    # 없음 → 후처리에서 채움

    # 관리비 (원 단위 → 만원)
    admin_amount = _get(admin, "etcFeeDetails", "etcFeeAmount")
    if admin_amount:
        maintenance = f"{int(admin_amount) // 10000}만원"
    else:
        avg = _get(detail, "maintenanceCost", "averageTotalPrice")
        maintenance = f"평균 {int(avg) // 10000}만원" if avg else ""

    # 입주가능일
    move_in = (
        _get(detail, "moveInTypeName")
        or _get(addition, "moveInDiscussionPossibleYN", "")
    )

    # 방향 (남향, 동향 등)
    direction = (
        _get(detail, "aptDirectionTypeName")
        or _get(detail, "directionTypeName")
        or _get(addition, "directionTypeName")
        or _get(addition, "aptDirectionTypeName")
        or _get(facility, "directionTypeName")
        or _get(space, "directionTypeName")
    )
    if not direction:
        # 디버그: 어떤 키에 방향 관련 데이터가 있는지 확인
        for _sec_nm, _sec in [("detail", detail), ("addition", addition),
                               ("facility", facility), ("space", space)]:
            _dir_keys = [k for k in (_sec or {}) if "dir" in k.lower() or "향" in str(_sec.get(k, ""))]
            if _dir_keys:
                import sys
                print(f"[방향 디버그] {_sec_nm}: {_dir_keys} → {[_sec[k] for k in _dir_keys]}", file=sys.stderr)

    # 단지세대수 / 동세대수
    household_total   = _get(detail, "aptHouseholdCount")
    household_by_type = _get(detail, "householdCountByPtp")

    # 총주차대수
    parking_count = _get(detail, "aptParkingCount") or _get(detail, "parkingCount")
    parking_ratio = _get(detail, "aptParkingCountPerHousehold") or _get(detail, "parkingPerHouseholdCount")

    # 방수/화장실수
    rooms   = _get(detail, "roomCount")
    baths   = _get(detail, "bathroomCount")
    rooms_baths = f"{rooms}/{baths}" if (rooms or baths) else ""

    # 현관구조 (계단식/복도식)
    entrance_type = _get(facility, "entranceTypeName")

    # 난방 (방식/연료)
    heat_method = _get(detail, "aptHeatMethodTypeName")
    heat_fuel   = _get(detail, "aptHeatFuelTypeName")
    if heat_method and heat_fuel:
        heating = f"{heat_method}/{heat_fuel}"
    else:
        heating = heat_method or heat_fuel

    # 건축물 용도
    building_use = _get(detail, "principalUse")

    # 매물특징
    feature = (
        _get(detail, "articleFeatureDescription")
        or _get(addition, "articleFeatureDesc")
    )

    # move_in이 "즉시입주"인데 feature에 날짜가 적혀 있으면 그걸로 대체
    if move_in and "즉시입주" in move_in and feature:
        # 패턴 예: "2025년 3월", "25년 3월", "25.03", "2025.03", "3월 입주", "3월말 입주가능" 등
        _date_pat = re.search(
            r"(\d{2,4}[년.]\s*\d{1,2}월?\w*|\d{1,2}월\w*)",
            feature,
        )
        if _date_pat:
            move_in = _date_pat.group(0).strip()

    # 중개사 (사무소명 + 주소 + 전화 + 휴대폰)
    r_name    = _get(realtor, "realtorName") or _get(addition, "realtorName") or _get(detail, "dealerName")
    r_address = _get(realtor, "address")
    r_tel     = _get(realtor, "representativeTelNo")
    r_cell    = _get(realtor, "cellPhoneNo")
    parts = [p for p in [r_name, r_address, r_tel, r_cell] if p]
    dealer_name = "\n".join(parts)

    # 평형번호 (전세 시세 API 요청에 사용)
    ptp_no = str(
        _get(detail, "ptpNo")
        or _get(addition, "ptpNo")
        or _get(space, "ptpNo")
        or ""
    )

    return {
        "collected_at":      datetime.now().strftime("%Y-%m-%d %H:%M"),
        "article_no":        article_no,
        "complex_name":      complex_name,
        "address":           address,
        "trade_type":        trade_type,
        "price_main":        price_main,
        "rent_price":        rent_price,
        "move_in_date":      move_in,
        "area_supply":       f"{_to_pyeong(area_supply)}평" if area_supply else "",
        "area_exclusive":    f"{_to_pyeong(area_exclusive)}평" if area_exclusive else "",
        "direction":         direction,
        "household_by_type": (f"{household_total}세대/{household_by_type}세대"
                              if household_total and household_by_type
                              else f"{household_total or household_by_type}세대"
                              if (household_total or household_by_type) else ""),
        "parking_count":     (f"{parking_count}대(세대당 {parking_ratio}대)" if parking_ratio
                              else f"{parking_count}대") if parking_count else "",
        "rooms_baths":       rooms_baths,
        "floor":             floor,
        "entrance_type":     entrance_type,
        "heating":           heating,
        "maintenance":       maintenance,
        "building_use":      building_use,
        "feature":           feature,
        "dealer_name":       dealer_name,
        "url":               url,
        "_complex_no":       str(_get(detail, "hscpNo") or ""),  # 내부용, Excel 저장 제외
    }


# ─── Excel ────────────────────────────────────────────────────────────────────

# 열별 최소/최대 너비 힌트 (글자 단위, 한글 1자 ≈ 2)
_COL_MIN = {
    "collected_at": 16, "article_no": 13, "complex_name": 14, "address": 22,
    "trade_type": 6, "price_main": 14, "rent_price": 13, "move_in_date": 16,
    "area_supply": 10, "area_exclusive": 10,
    "direction": 8, "household_by_type": 14, "parking_count": 10, "rooms_baths": 10,
    "floor": 10, "entrance_type": 8, "heating": 14, "maintenance": 10,
    "building_use": 10, "feature": 30, "dealer_name": 28, "url": 50,
}


def _header_width(header: str) -> float:
    """헤더 문자열 길이 기반 열 너비 (한글 2, 영문/숫자/기호 1 기준)."""
    w = sum(2 if ord(c) > 0x7F else 1 for c in header)
    return w + 2   # 여백


def setup_sheet(ws) -> None:
    """헤더 행 스타일 초기 설정."""
    header_fill  = PatternFill("solid", fgColor="1F4E79")
    header_font  = Font(name="맑은 고딕", bold=True, color="FFFFFF", size=10)
    header_align = Alignment(horizontal="center", vertical="center", wrap_text=False)
    thin = Side(style="thin", color="CCCCCC")
    bdr  = Border(left=thin, right=thin, top=thin, bottom=thin)

    for col_idx, (header, key) in enumerate(HEADERS_MAP, start=1):
        cell = ws.cell(row=1, column=col_idx, value=header)
        cell.font      = header_font
        cell.fill      = header_fill
        cell.alignment = header_align
        cell.border    = bdr
        width = max(_header_width(header), _COL_MIN.get(key, 10))
        ws.column_dimensions[get_column_letter(col_idx)].width = width

    ws.row_dimensions[1].height = 20
    ws.freeze_panes = "A2"


def _cell_width(value: str) -> float:
    """셀 값 기준 필요 너비 (한글 2, 그 외 1)."""
    longest = max(value.split("\n"), key=len) if "\n" in value else value
    return sum(2 if ord(c) > 0x7F else 1 for c in longest) + 2


def append_row(ws, fields: dict, row_idx: int) -> None:
    thin = Side(style="thin", color="CCCCCC")
    bdr  = Border(left=thin, right=thin, top=thin, bottom=thin)
    fill = (
        PatternFill("solid", fgColor="EBF3FB")
        if row_idx % 2 == 0
        else PatternFill("solid", fgColor="FFFFFF")
    )
    for col_idx, (_, key) in enumerate(HEADERS_MAP, start=1):
        value = fields.get(key, "")
        text  = str(value) if value else ""
        cell  = ws.cell(row=row_idx, column=col_idx, value=text)
        cell.border = bdr
        cell.fill   = fill
        if key in ("feature", "url", "dealer_name"):
            cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        else:
            cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=False)

        # 데이터가 헤더보다 넓으면 열 너비 확장 (URL·매물특징·중개사 제외)
        if text and key not in ("url", "feature", "dealer_name"):
            col_letter = get_column_letter(col_idx)
            needed = _cell_width(text)
            current = ws.column_dimensions[col_letter].width or 0
            if needed > current:
                ws.column_dimensions[col_letter].width = min(needed, 40)

    # 행 높이: 중개사 줄 수 기준으로 자동 계산 (줄당 약 16pt)
    dealer_text = str(fields.get("dealer_name", ""))
    line_count = dealer_text.count("\n") + 1 if dealer_text else 1
    ws.row_dimensions[row_idx].height = max(18, line_count * 16 + 4)


def is_duplicate(ws, article_no: str, complex_name: str = "", floor: str = "") -> bool:
    """중복 확인.

    1차: 매물번호 동일 → 확실한 중복
    2차: 단지명 + 층 동일 → 재등록 의심 (층이 같은 동일 단지는 드물기 때문)
    """
    col = {k: i for i, (_, k) in enumerate(HEADERS_MAP)}
    a_col = col.get("article_no", -1)
    c_col = col.get("complex_name", -1)
    f_col = col.get("floor", -1)

    check_cf = bool(complex_name and floor and c_col >= 0 and f_col >= 0)

    for row in ws.iter_rows(min_row=2, max_row=ws.max_row):
        vals = [c.value or "" for c in row]
        if a_col >= 0 and vals[a_col] == article_no:
            return True
        if check_cf and vals[c_col] == complex_name and vals[f_col] == floor:
            return True
    return False


def load_or_create_workbook(path: Path):
    if path.exists():
        wb = openpyxl.load_workbook(path)
        ws = wb.active
    else:
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.title = "매물목록"
        setup_sheet(ws)
    return wb, ws


# ─── 지역 전세안고 검색 ────────────────────────────────────────────────────────

_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)


def _geocode(region_name: str) -> tuple[float, float]:
    """Nominatim으로 지역명 → (lat, lon) 변환 (API 키 불필요)."""
    import urllib.request, urllib.parse
    encoded = urllib.parse.quote(region_name)
    url = (
        f"https://nominatim.openstreetmap.org/search"
        f"?q={encoded}&format=json&limit=3&accept-language=ko&countrycodes=kr"
    )
    req = urllib.request.Request(url, headers={"User-Agent": "NaverLandScraper/1.0"})
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.loads(r.read())
    if not data:
        raise RuntimeError(f"'{region_name}' 지역 좌표를 찾을 수 없습니다.")
    return float(data[0]["lat"]), float(data[0]["lon"])


def search_region_articles(
    region_name: str,
    log=print,
    max_count: int = 500,
    proxy: dict | None = None,
) -> list[dict]:
    """지역명으로 전세안고 매매 매물 목록 수집 후 상세 필드까지 반환.

    Returns:
        extract_fields() 형식의 dict 리스트 (append_row()에 바로 사용 가능)
    """
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        raise RuntimeError("playwright 패키지가 필요합니다.")

    log(f"'{region_name}' 지역 전세안고 매매 매물 검색 중...")

    # ── 1. 지역 좌표 조회 (Nominatim) ───────────────────────────────────────
    try:
        lat, lon = _geocode(region_name)
        log(f"  좌표: {lat:.4f}, {lon:.4f}")
    except Exception as e:
        raise RuntimeError(f"지역 좌표 조회 실패: {e}")

    jwt_token: list[str | None] = [None]

    def _on_request(req):
        if "land.naver.com/api/articles" in req.url:
            auth = req.headers.get("authorization", "")
            if auth.startswith("Bearer "):
                jwt_token[0] = auth[7:]

    all_fields: list[dict] = []

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, proxy=proxy)
        ctx = browser.new_context(user_agent=_UA, locale="ko-KR")
        page = ctx.new_page()
        page.on("request", _on_request)

        # ── 2. 브라우저 세션 초기화 & JWT 획득 ─────────────────────────────
        log("  브라우저 인증 중...")
        page.goto(
            "https://new.land.naver.com/complexes/338?ms=37.5762,127.0348,15&a=APT&b=A1&e=RETAIL",
            wait_until="domcontentloaded", timeout=30000,
        )
        page.wait_for_timeout(4000)

        if not jwt_token[0]:
            browser.close()
            raise RuntimeError("JWT 토큰 획득 실패 — 네이버 부동산 접속이 불가합니다.")

        log("  인증 완료")

        # ── 3. cortarNo 조회 ────────────────────────────────────────────────
        cortar_data = None
        for zoom in [15, 14]:
            cortar_data = page.evaluate(
                """async ([lat, lon, zoom, jwt]) => {
                    const r = await fetch(
                        `https://new.land.naver.com/api/cortars?zoom=${zoom}&centerLat=${lat}&centerLon=${lon}`,
                        {headers: {'Authorization': 'Bearer ' + jwt,
                                   'Accept': 'application/json',
                                   'Referer': 'https://new.land.naver.com/'}}
                    );
                    return r.ok ? await r.json() : null;
                }""",
                [lat, lon, zoom, jwt_token[0]],
            )
            if cortar_data:
                break

        if not cortar_data:
            browser.close()
            raise RuntimeError(f"'{region_name}' 지역 코드 조회 실패")

        # 지역명 끝 글자로 수준 자동 판단
        #   동/읍/면/리 로 끝나면 → 동(sector) 수준 코드
        #   구/시/군/도  로 끝나면 → 구(division) 수준 코드 (전체 구 검색)
        import re as _re
        if _re.search(r"[동읍면리]$", region_name.strip()):
            cortar_no = cortar_data.get("sectorNo") or cortar_data.get("cortarNo")
            cortar_nm = cortar_data.get("sectorName") or cortar_data.get("cortarName", region_name)
        else:
            cortar_no = cortar_data.get("divisionNo") or cortar_data.get("cortarNo")
            cortar_nm = cortar_data.get("divisionName") or cortar_data.get("cortarName", region_name)
        log(f"  지역 코드: {cortar_nm} ({cortar_no})")

        # ── 4. 전세안고 매물 목록 (페이지네이션) ───────────────────────────
        BASE_PARAMS = (
            f"cortarNo={cortar_no}"
            "&realEstateType=APT%3AABYH%3AMLS"
            "&tradeType=A1"
            "&tag=RENTHUG%3A%3A%3A%3A%3A%3A%3A%3A"
            "&rentPriceMin=0&rentPriceMax=900000000"
            "&priceMin=0&priceMax=900000000"
            "&areaMin=0&areaMax=900000000"
            "&oldBuildYears&recentlyBuildYears"
            "&minHouseHoldCount&maxHouseHoldCount"
            "&showArticle=false&sameAddressGroup=false"
            "&minMaintenanceCost&maxMaintenanceCost"
            "&perPage=20"
        )

        page_num = 1
        article_list: list[dict] = []

        while len(article_list) < max_count:
            result = page.evaluate(
                """async ([params, pageNum, jwt]) => {
                    const url = `https://new.land.naver.com/api/articles?${params}&page=${pageNum}`;
                    const r = await fetch(url, {
                        headers: {'Authorization': 'Bearer ' + jwt,
                                  'Accept': 'application/json',
                                  'Referer': 'https://new.land.naver.com/'}
                    });
                    return r.ok ? await r.json() : {error: r.status};
                }""",
                [BASE_PARAMS, page_num, jwt_token[0]],
            )

            if not result or "error" in result:
                log(f"  페이지 {page_num} 오류: {result}")
                break

            arts = result.get("articleList", [])
            is_more = result.get("isMoreData", False)

            if not arts:
                break

            article_list.extend(arts)
            log(f"  목록 {len(article_list)}개 수집 (더 있음: {is_more})")

            if not is_more or len(article_list) >= max_count:
                break

            page_num += 1
            page.wait_for_timeout(200)

        log(f"  상세 조회 시작: {min(len(article_list), max_count)}개")

        # 기보증금 실거래가 캐시 (complexNo별 1회 조회)
        _pyeong_cache: dict[str, list] = {}   # cno → [{pyeongNo, exclusiveArea}]
        _rp_cache: dict[tuple, dict]  = {}   # (cno, pyeongNo) → realPrice dict

        # ── 5. 각 매물 상세 조회 ────────────────────────────────────────────
        for i, art in enumerate(article_list[:max_count]):
            article_no = str(art.get("articleNo", ""))
            if not article_no:
                continue

            article_url = f"https://new.land.naver.com/articles/{article_no}"
            try:
                detail = page.evaluate(
                    """async ([articleNo, jwt]) => {
                        const r = await fetch(
                            `https://new.land.naver.com/api/articles/${articleNo}`,
                            {headers: {'Authorization': 'Bearer ' + jwt,
                                       'Accept': 'application/json',
                                       'Referer': 'https://new.land.naver.com/'}}
                        );
                        return r.ok ? await r.json() : null;
                    }""",
                    [article_no, jwt_token[0]],
                )

                if detail and detail.get("articleDetail"):
                    # 올바른 URL: complexes/{hscpNo}?articleNo=...
                    complex_no = str(
                        detail.get("articleDetail", {}).get("hscpNo", "") or ""
                    )
                    if complex_no:
                        article_url = (
                            f"https://new.land.naver.com/complexes/{complex_no}"
                            f"?articleNo={article_no}"
                        )
                    fields = extract_fields(detail, article_no, article_url)
                    cname = fields.get("complex_name", "")
                    # 주상복합·도시형·생활주택 제외
                    if any(kw in cname for kw in ("주상복합", "도시형", "생활주택")):
                        log(f"  ({i+1}/{len(article_list)}) 제외: {cname}")
                        continue
                    # 기보증금 없으면 전세 실거래가로 채우기 (인라인)
                    if not fields.get("rent_price") and complex_no:
                        try:
                            _ea = float(fields.get("area_exclusive", "").replace("평", "").strip() or "0") / 0.3025
                        except:
                            _ea = 0.0

                        if complex_no not in _pyeong_cache:
                            _pyeong_cache[complex_no] = page.evaluate(
                                """async ([cno, jwt]) => {
                                    const r = await fetch(
                                        `https://new.land.naver.com/api/complexes/${cno}?sameAddressGroup=false`,
                                        {headers: {'Authorization': 'Bearer ' + jwt,
                                                   'Accept': 'application/json',
                                                   'Referer': 'https://new.land.naver.com/'}}
                                    );
                                    if (!r.ok) return [];
                                    const d = await r.json();
                                    return (d.complexPyeongDetailList || []).map(p => ({
                                        pyeongNo: String(p.pyeongNo),
                                        exclusiveArea: parseFloat(p.exclusiveArea) || 0
                                    }));
                                }""",
                                [complex_no, jwt_token[0]],
                            ) or []

                        _py_list = _pyeong_cache.get(complex_no, [])
                        if _py_list:
                            _best = (min(_py_list, key=lambda p: abs(p["exclusiveArea"] - _ea))
                                     if _ea else _py_list[0])
                            _pno = _best["pyeongNo"]
                            _rk  = (complex_no, _pno)
                            if _rk not in _rp_cache:
                                _rp_cache[_rk] = page.evaluate(
                                    """async ([cno, pno, jwt]) => {
                                        const r = await fetch(
                                            `https://new.land.naver.com/api/complexes/${cno}/prices/real?tradeType=B1&areaNo=${pno}&type=table`,
                                            {headers: {'Authorization': 'Bearer ' + jwt,
                                                       'Accept': 'application/json',
                                                       'Referer': `https://new.land.naver.com/complexes/${cno}`}}
                                        );
                                        if (!r.ok) return null;
                                        const d = await r.json();
                                        const months = d.realPriceOnMonthList || [];
                                        if (!months.length) return null;
                                        const latest = [...(months[0].realPriceList || [])];
                                        if (!latest.length) return null;
                                        latest.sort((a, b) => Number(b.tradeDate) - Number(a.tradeDate));
                                        return latest[0];
                                    }""",
                                    [complex_no, _pno, jwt_token[0]],
                                )
                            _rp = _rp_cache.get(_rk)
                            if _rp:
                                _ps  = (_rp.get("formattedPrice") or "").strip()
                                _dt  = (_rp.get("formattedTradeYearMonth") or "")[:7]
                                if _ps:
                                    _dt  = _dt or datetime.now().strftime("%Y.%m")
                                    fields["rent_price"] = f"{_ps} ({_dt}. 거래내역)"


                    all_fields.append(fields)
                    log(
                        f"  ({i+1}/{len(article_list)}) "
                        f"{cname} — {fields.get('price_main', '')}"
                    )
                else:
                    log(f"  ({i+1}/{len(article_list)}) 매물 {article_no} 응답 없음")

            except Exception as e:
                log(f"  ({i+1}/{len(article_list)}) 매물 {article_no} 오류: {e}")

            if (i + 1) % 10 == 0:
                page.wait_for_timeout(300)


        browser.close()

    log(f"  완료: {len(all_fields)}개 수집")
    return all_fields


# ─── URL 목록 수집 (search_region_articles와 동일한 방식) ────────────────────

def collect_articles_by_url_list(url_list: list[str], log=print, proxy: dict | None = None) -> list[dict]:
    """URL 목록으로 매물 상세 수집.  search_region_articles와 동일한 브라우저/JWT 방식 사용."""
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        raise RuntimeError("playwright 패키지가 필요합니다.")

    # URL → (article_no, complex_no_from_url) 파싱
    parsed: list[tuple[str, str, str]] = []   # (article_no, complex_no_hint, original_url)
    for url in url_list:
        try:
            ano, cno = parse_url(url)
            parsed.append((ano, cno, url))
        except ValueError as e:
            log(f"  URL 오류 — 건너뜀: {e}")

    if not parsed:
        return []

    jwt_token: list[str | None] = [None]

    def _on_request(req):
        if "land.naver.com/api/articles" in req.url:
            auth = req.headers.get("authorization", "")
            if auth.startswith("Bearer "):
                jwt_token[0] = auth[7:]

    all_fields: list[dict] = []
    _pyeong_cache: dict[str, list] = {}
    _rp_cache: dict[tuple, dict]  = {}

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, proxy=proxy)
        ctx = browser.new_context(user_agent=_UA, locale="ko-KR")
        page = ctx.new_page()
        page.on("request", _on_request)

        # JWT 획득: search_region_articles와 동일한 페이지로 이동 (세션/쿠키 동일하게 확보)
        log("  브라우저 인증 중...")
        page.goto(
            "https://new.land.naver.com/complexes/338?ms=37.5762,127.0348,15&a=APT&b=A1&e=RETAIL",
            wait_until="domcontentloaded", timeout=30000,
        )
        page.wait_for_timeout(4000)

        if not jwt_token[0]:
            browser.close()
            raise RuntimeError("JWT 토큰 획득 실패 — 네이버 부동산 접속이 불가합니다.")

        log("  인증 완료")

        for i, (article_no, complex_no_hint, original_url) in enumerate(parsed):
            try:
                nav_url = (
                    f"https://new.land.naver.com/complexes/{complex_no_hint}?articleNo={article_no}"
                    if complex_no_hint
                    else f"https://new.land.naver.com/articles/{article_no}"
                )

                try:
                    with page.expect_response(
                        lambda r, _a=article_no: f"/api/articles/{_a}" in r.url and r.status == 200,
                        timeout=20000,
                    ) as resp_info:
                        page.goto(nav_url, wait_until="domcontentloaded", timeout=20000)
                    detail = resp_info.value.json()
                except Exception:
                    detail = None

                if not detail or not detail.get("articleDetail"):
                    log(f"  ({i+1}/{len(parsed)}) 매물 {article_no} 유효 데이터 없음 — 만료/비공개 매물")
                    continue

                complex_no = str(detail.get("articleDetail", {}).get("hscpNo", "") or "")
                article_url = (
                    f"https://new.land.naver.com/complexes/{complex_no}?articleNo={article_no}"
                    if complex_no else original_url
                )

                fields = extract_fields(detail, article_no, article_url)
                cname  = fields.get("complex_name", "")

                # 기보증금 없으면 전세 실거래가로 채우기 (search_region_articles와 동일)
                if not fields.get("rent_price") and complex_no:
                    try:
                        _ea = float(fields.get("area_exclusive", "").replace("평", "").strip() or "0") / 0.3025
                    except Exception:
                        _ea = 0.0

                    if complex_no not in _pyeong_cache:
                        _pyeong_cache[complex_no] = page.evaluate(
                            """async ([cno, jwt]) => {
                                const r = await fetch(
                                    `https://new.land.naver.com/api/complexes/${cno}?sameAddressGroup=false`,
                                    {headers: {'Authorization': 'Bearer ' + jwt,
                                               'Accept': 'application/json',
                                               'Referer': 'https://new.land.naver.com/'}}
                                );
                                if (!r.ok) return [];
                                const d = await r.json();
                                return (d.complexPyeongDetailList || []).map(p => ({
                                    pyeongNo: String(p.pyeongNo),
                                    exclusiveArea: parseFloat(p.exclusiveArea) || 0
                                }));
                            }""",
                            [complex_no, jwt_token[0]],
                        ) or []

                    _py_list = _pyeong_cache.get(complex_no, [])
                    if _py_list:
                        _best = (min(_py_list, key=lambda p: abs(p["exclusiveArea"] - _ea))
                                 if _ea else _py_list[0])
                        _pno = _best["pyeongNo"]
                        _rk  = (complex_no, _pno)
                        if _rk not in _rp_cache:
                            _rp_cache[_rk] = page.evaluate(
                                """async ([cno, pno, jwt]) => {
                                    const r = await fetch(
                                        `https://new.land.naver.com/api/complexes/${cno}/prices/real?tradeType=B1&areaNo=${pno}&type=table`,
                                        {headers: {'Authorization': 'Bearer ' + jwt,
                                                   'Accept': 'application/json',
                                                   'Referer': `https://new.land.naver.com/complexes/${cno}`}}
                                    );
                                    if (!r.ok) return null;
                                    const d = await r.json();
                                    const months = d.realPriceOnMonthList || [];
                                    if (!months.length) return null;
                                    const latest = [...(months[0].realPriceList || [])];
                                    if (!latest.length) return null;
                                    latest.sort((a, b) => Number(b.tradeDate) - Number(a.tradeDate));
                                    return latest[0];
                                }""",
                                [complex_no, _pno, jwt_token[0]],
                            )
                        _rp = _rp_cache.get(_rk)
                        if _rp:
                            _ps = (_rp.get("formattedPrice") or "").strip()
                            _dt = (_rp.get("formattedTradeYearMonth") or "")[:7]
                            if _ps:
                                _dt = _dt or datetime.now().strftime("%Y.%m")
                                fields["rent_price"] = f"{_ps} ({_dt}. 거래내역)"


                all_fields.append(fields)
                log(f"  ({i+1}/{len(parsed)}) {cname} — {fields.get('price_main', '')}")

            except Exception as e:
                log(f"  ({i+1}/{len(parsed)}) 매물 {article_no} 오류: {e}")

        browser.close()

    log(f"  완료: {len(all_fields)}개 수집")
    return all_fields


# ─── 메인 ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="네이버 부동산 매물 정보를 Excel에 누적 저장합니다.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("url", help="네이버 부동산 매물 URL")
    parser.add_argument(
        "--output", "-o",
        default=str(EXCEL_FILE),
        metavar="PATH",
        help=f"저장할 Excel 파일 경로 (기본값: {EXCEL_FILE.name})",
    )
    parser.add_argument("--debug",   action="store_true", help="API 응답 원문 출력")
    parser.add_argument("--browser", action="store_true", help="브라우저 방식 강제 사용")
    args = parser.parse_args()

    output_path = Path(args.output)

    print(f"URL: {args.url}")

    # 1. URL 파싱
    try:
        article_no, complex_no = parse_url(args.url)
    except ValueError as e:
        print(f"\n오류: {e}")
        sys.exit(1)
    print(f"매물번호: {article_no}  단지번호: {complex_no or '(없음)'}")

    # 2. 중복 확인
    wb, ws = load_or_create_workbook(output_path)
    if is_duplicate(ws, article_no):
        print(f"\n이미 등록된 매물입니다 (매물번호: {article_no}). 건너뜁니다.")
        return

    # 3. 데이터 수집
    print("데이터 수집 중...")
    try:
        data = fetch_article(article_no, complex_no, args.url, force_browser=args.browser)
    except RuntimeError as e:
        print(f"\n오류: {e}")
        sys.exit(1)

    if args.debug:
        print("\n── API 응답 ──────────────────────────────────────")
        print(json.dumps(data, ensure_ascii=False, indent=2))
        print("──────────────────────────────────────────────────\n")

    # 4. 필드 추출
    fields = extract_fields(data, article_no, args.url)

    # 내부 전용 키 제거 후 저장
    fields.pop("_complex_no", None)
    next_row = ws.max_row + 1
    append_row(ws, fields, next_row)
    wb.save(output_path)

    # 5. 결과 요약
    trade  = fields["trade_type"] or ""
    price  = fields["price_main"] or ""
    rent   = fields["rent_price"] or ""
    price_str = f"{price}만원" + (f" / 월 {rent}만원" if rent else "")

    print(f"\n✓ 저장 완료  →  {output_path}  (행 {next_row})")
    print(f"  단지명  : {fields['complex_name'] or '(없음)'}")
    print(f"  주소    : {fields['address'] or '(없음)'}")
    print(f"  거래    : {trade}  {price_str}")
    print(f"  면적    : 공급 {fields['area_supply']} / 전용 {fields['area_exclusive']}  {fields['floor']}층")
    if fields["move_in_date"]:
        print(f"  입주    : {fields['move_in_date']}")


if __name__ == "__main__":
    main()
