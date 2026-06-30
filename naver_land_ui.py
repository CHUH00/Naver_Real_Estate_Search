#!/usr/bin/env python3
"""
네이버 부동산 매물 수집기 — GUI
"""

import tkinter as tk
from tkinter import filedialog, messagebox
import threading
import queue
import subprocess
import sys
import os
import re
from pathlib import Path

try:
    import xlwings as xw
    _HAS_XLWINGS = True
except ImportError:
    _HAS_XLWINGS = False

sys.path.insert(0, str(Path(__file__).parent))
from naver_land_scraper import (
    parse_url, extract_fields,
    load_or_create_workbook, append_row, is_duplicate,
    search_region_articles, collect_articles_by_url_list,
)

# ── Palette ────────────────────────────────────────────────────────────────────
BG        = "#0E1218"   # 배경
SURFACE   = "#161D28"   # 카드/패널
INPUT_BG  = "#090C12"   # 입력창
BORDER    = "#1F2A3A"   # 구분선
TEXT      = "#E2EAF5"   # 본문
TEXT_DIM  = "#4A5870"   # 보조
ACCENT    = "#F0A500"   # 강조 (골드)
SUCCESS   = "#34D079"   # 성공
ERROR     = "#F06060"   # 오류
INFO      = "#5A9ED4"   # 정보
# ──────────────────────────────────────────────────────────────────────────────

FONT_UI   = ("맑은 고딕", 10)
FONT_MONO = ("Menlo", 10)
FONT_HEAD = ("맑은 고딕", 14, "bold")
FONT_LABEL= ("맑은 고딕", 9)


class _Btn:
    """Label+Frame 기반 버튼 — macOS에서 bg/fg 색상이 완전히 적용됨."""

    def __init__(self, parent, text, command, primary=False, **kw):
        self._command = command
        self._enabled = True
        self._primary = primary
        self._bg  = ACCENT if primary else SURFACE
        self._fg  = "#0E1218" if primary else TEXT
        self._hov = "#C87E00" if primary else BORDER
        self._font = ("맑은 고딕", 10, "bold") if primary else FONT_LABEL

        self._frame = tk.Frame(parent, bg=self._bg, cursor="hand2", **kw)
        self._lbl = tk.Label(
            self._frame, text=text,
            bg=self._bg, fg=self._fg, font=self._font,
            cursor="hand2", padx=14, pady=6,
        )
        self._lbl.pack()
        self._bind()

    def _bind(self):
        for w in (self._frame, self._lbl):
            w.bind("<Button-1>", self._click)
            w.bind("<Enter>",    self._enter)
            w.bind("<Leave>",    self._leave)

    def _unbind(self):
        for w in (self._frame, self._lbl):
            w.unbind("<Button-1>")
            w.unbind("<Enter>")
            w.unbind("<Leave>")

    def _click(self, _=None):
        if self._enabled:
            self._command()

    def _enter(self, _=None):
        if self._enabled:
            self._frame.config(bg=self._hov)
            self._lbl.config(bg=self._hov)

    def _leave(self, _=None):
        self._frame.config(bg=self._bg)
        self._lbl.config(bg=self._bg)

    # ── 외부 인터페이스 ─────────────────────────────────────────────────────
    def config(self, text=None, state=None, bg=None, fg=None, **_):
        if text  is not None: self._lbl.config(text=text)
        if fg    is not None: self._lbl.config(fg=fg)
        if bg    is not None:
            self._bg = bg
            self._frame.config(bg=bg)
            self._lbl.config(bg=bg)
        if state == "disabled":
            self._enabled = False
            self._unbind()
        elif state == "normal":
            self._enabled = True
            self._bind()

    def bind(self, seq, func, add=None):
        # 외부에서 hover 재등록할 때 내부 이벤트와 충돌 방지
        if seq in ("<Enter>", "<Leave>"):
            return
        for w in (self._frame, self._lbl):
            w.bind(seq, func, add)

    def pack(self, **kw):  self._frame.pack(**kw)
    def grid(self, **kw):  self._frame.grid(**kw)
    def place(self, **kw): self._frame.place(**kw)


def _btn(parent, text, command, primary=False, **kw):
    return _Btn(parent, text, command, primary=primary, **kw)


# ── 수도권 지역 목록 ───────────────────────────────────────────────────────────
SEOUL_REGIONS = [
    "강남구", "강동구", "강북구", "강서구", "관악구", "광진구", "구로구",
    "금천구", "노원구", "도봉구", "동대문구", "동작구", "마포구", "서대문구",
    "서초구", "성동구", "성북구", "송파구", "양천구", "영등포구", "용산구",
    "은평구", "종로구", "중구", "중랑구",
]

SEOUL_DONG = {
    "강남구": ["개포동","논현동","대치동","도곡동","삼성동","세곡동","수서동","신사동","압구정동","역삼동","일원동","자곡동","청담동"],
    "강동구": ["강일동","고덕동","길동","둔촌동","명일동","상일동","성내동","암사동","천호동"],
    "강북구": ["번동","미아동","수유동","우이동"],
    "강서구": ["가양동","개화동","공항동","내발산동","등촌동","마곡동","방화동","외발산동","화곡동"],
    "관악구": ["남현동","봉천동","신림동"],
    "광진구": ["광장동","구의동","군자동","능동","자양동","중곡동","화양동"],
    "구로구": ["가리봉동","개봉동","고척동","구로동","궁동","오류동","온수동","천왕동","항동"],
    "금천구": ["가산동","독산동","시흥동"],
    "노원구": ["공릉동","상계동","월계동","중계동","하계동"],
    "도봉구": ["도봉동","방학동","쌍문동","창동"],
    "동대문구": ["답십리동","용두동","이문동","장안동","전농동","청량리동","회기동","휘경동"],
    "동작구": ["노량진동","대방동","동작동","본동","사당동","상도동","신대방동"],
    "마포구": ["공덕동","도화동","동교동","마포동","망원동","상수동","서교동","성산동","신수동","아현동","연남동","염리동","용강동","합정동"],
    "서대문구": ["남가좌동","냉천동","대신동","대현동","북가좌동","신촌동","연희동","천연동","홍은동","홍제동"],
    "서초구": ["내곡동","반포동","방배동","서초동","신원동","양재동","염곡동","우면동","원지동","잠원동"],
    "성동구": ["금호동","마장동","사근동","성수동","송정동","옥수동","용답동","왕십리동","행당동"],
    "성북구": ["길음동","돈암동","동선동","보문동","삼선동","석관동","성북동","안암동","월곡동","장위동","정릉동","종암동"],
    "송파구": ["가락동","거여동","문정동","방이동","삼전동","석촌동","송파동","신천동","오금동","잠실동","장지동","풍납동"],
    "양천구": ["목동","신월동","신정동"],
    "영등포구": ["당산동","대림동","도림동","문래동","신길동","양평동","여의도동","영등포동"],
    "용산구": ["갈월동","남영동","동빙고동","문배동","보광동","서빙고동","용문동","이촌동","이태원동","청파동","한강로동","한남동"],
    "은평구": ["갈현동","구산동","녹번동","대조동","불광동","수색동","신사동","역촌동","응암동","증산동","진관동"],
    "종로구": ["가회동","계동","교남동","돈의동","동숭동","명륜동","무악동","부암동","사직동","삼청동","숭인동","신교동","안국동","연건동","옥인동","와룡동","원서동","이화동","인사동","창성동","청운동","체부동","통의동","통인동","팔판동","평동","필운동","행촌동","혜화동","홍지동","효자동"],
    "중구": ["광희동","남산동","다산동","만리동","묵정동","방산동","봉래동","소공동","신당동","을지로동","입정동","장충동","정동","충무로동","태평로","필동","황학동","회현동"],
    "중랑구": ["면목동","망우동","묵동","상봉동","신내동","중화동"],
}


class App:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("네이버 부동산 매물 수집기")
        self.root.geometry("860x940")
        self.root.minsize(660, 740)
        self.root.configure(bg=BG)
        self._selected_regions: set[str] = set()
        self._chip_btns: dict[str, _Btn] = {}
        self._selected_dong: set[str] = set()
        self._dong_chip_btns: dict[str, _Btn] = {}
        self._dong_panel_gu: str = ""

        # 필터 입력 변수
        self._f_price_min  = tk.StringVar()
        self._f_price_max  = tk.StringVar()
        self._f_area_min   = tk.StringVar()
        self._f_area_max   = tk.StringVar()
        self._f_movein_yr  = tk.StringVar()
        self._f_movein_mo  = tk.StringVar()
        self._f_directions: set[str] = set()
        self._f_dir_btns: dict[str, _Btn] = {}
        self._f_rent_ratio = tk.IntVar(value=0)   # 기보증금/매매가 최소 비율 (%)
        self._f_floors: set[str] = set()           # 저/중/고
        self._f_floor_btns: dict[str, _Btn] = {}
        self._f_household_min = tk.StringVar()     # 단지 전체 세대수 최소값
        self._filter_open  = False

        # macOS 기본 메뉴바 숨기기 방지 (제목 표시줄 유지)
        try:
            self.root.tk.call("::tk::unsupported::MacWindowStyle", "style", self.root._w, "document", "closeBox collapseBox resizeBox")
        except Exception:
            pass

        self.excel_path = tk.StringVar(
            value=str(Path(__file__).parent / "네이버_부동산_매물.xlsx")
        )
        self._pdf_path = tk.StringVar()
        self._update_pdf_path()
        self.excel_path.trace_add("write", lambda *_: self._update_pdf_path())
        self.q = queue.Queue()
        self.running = False

        self._build()
        self._poll()

    # ── UI 구성 ────────────────────────────────────────────────────────────────

    def _build(self):
        # ── 전체 페이지 스크롤 컨테이너 ─────────────────────────────────────────
        self._main_canvas = tk.Canvas(self.root, bg=BG, highlightthickness=0)
        self._main_canvas.pack(fill="both", expand=True)

        root = tk.Frame(self._main_canvas, bg=BG)
        _win_id = self._main_canvas.create_window((0, 0), window=root, anchor="nw")

        def _on_inner_configure(*_):
            self._main_canvas.configure(scrollregion=self._main_canvas.bbox("all"))
        def _on_canvas_resize(e):
            self._main_canvas.itemconfig(_win_id, width=e.width)
        root.bind("<Configure>", _on_inner_configure)
        self._main_canvas.bind("<Configure>", _on_canvas_resize)
        self.root.unbind_all("<MouseWheel>")

        # ── 헤더 ──────────────────────────────────────────────────────────────
        hdr = tk.Frame(root, bg=BG)
        hdr.pack(fill="x", padx=28, pady=(24, 0))

        hdr_left = tk.Frame(hdr, bg=BG)
        hdr_left.pack(side="left")
        tk.Label(hdr_left, text="NAVER LAND", bg=BG, fg=TEXT_DIM,
                 font=("맑은 고딕", 8, "bold")).pack(anchor="w")
        title_row = tk.Frame(hdr_left, bg=BG)
        title_row.pack(anchor="w")
        tk.Label(title_row, text="매물 수집기", bg=BG, fg=TEXT,
                 font=("맑은 고딕", 17, "bold")).pack(side="left")
        tk.Label(title_row, text="  전세안고 매매", bg=BG, fg=ACCENT,
                 font=("맑은 고딕", 10)).pack(side="left", pady=(5, 0))

        tk.Frame(root, bg=BORDER, height=1).pack(fill="x", padx=28, pady=(14, 16))

        # ── 지역 일괄 검색 섹션 ───────────────────────────────────────────────
        region_sec = tk.Frame(root, bg=SURFACE)
        region_sec.pack(fill="x", padx=28, pady=(0, 6))

        # 섹션 헤더 (강조 바 + 제목)
        _rhdr_row = tk.Frame(region_sec, bg=SURFACE)
        _rhdr_row.pack(fill="x")
        tk.Frame(_rhdr_row, bg=ACCENT, width=3).pack(side="left", fill="y")
        _rhdr_inner = tk.Frame(_rhdr_row, bg=SURFACE)
        _rhdr_inner.pack(side="left", fill="x", expand=True, padx=(12, 12), pady=(10, 8))
        _rhdr_lrow = tk.Frame(_rhdr_inner, bg=SURFACE)
        _rhdr_lrow.pack(fill="x")
        tk.Label(_rhdr_lrow, text="지역 일괄 검색", bg=SURFACE, fg=TEXT,
                 font=("맑은 고딕", 10, "bold")).pack(side="left")
        tk.Label(_rhdr_lrow, text="  해당 지역 전세안고 매매 매물 전부 저장",
                 bg=SURFACE, fg=TEXT_DIM, font=FONT_LABEL).pack(side="left")
        _btn(_rhdr_lrow, "전체 해제", self._deselect_all).pack(side="right")
        _btn(_rhdr_lrow, "서울 전체", self._select_all_seoul).pack(side="right", padx=(0, 6))

        # 구 칩 버튼
        chips_inner = tk.Frame(region_sec, bg=SURFACE)
        chips_inner.pack(fill="x", padx=15, pady=(0, 4))

        def _add_chip_section(parent, title, regions):
            hrow = tk.Frame(parent, bg=SURFACE)
            hrow.pack(fill="x", pady=(4, 2))
            tk.Label(hrow, text=title, bg=SURFACE, fg=TEXT_DIM,
                     font=("맑은 고딕", 8, "bold")).pack(side="left")
            COLS = 8
            for r_start in range(0, len(regions), COLS):
                row_f = tk.Frame(parent, bg=SURFACE)
                row_f.pack(fill="x", pady=1)
                for name in regions[r_start:r_start + COLS]:
                    self._add_chip(row_f, name)

        _add_chip_section(chips_inner, "서울", SEOUL_REGIONS)

        # 동 선택 패널 (구 클릭 시 동적으로 채워짐)
        self._dong_section = tk.Frame(region_sec, bg=SURFACE)
        self._dong_chips_open = True

        dong_hdr = tk.Frame(self._dong_section, bg=SURFACE)
        dong_hdr.pack(fill="x", padx=15, pady=(6, 2))
        self._dong_title_lbl = tk.Label(
            dong_hdr, text="", bg=SURFACE, fg=TEXT_DIM,
            font=("맑은 고딕", 8, "bold"),
        )
        self._dong_title_lbl.pack(side="left")
        _btn(dong_hdr, "전체 해제", self._deselect_all_dong).pack(side="right")
        _btn(dong_hdr, "전체 선택", self._select_all_dong).pack(side="right", padx=(0, 6))
        self._dong_toggle_btn = _btn(dong_hdr, "▲ 접기", self._toggle_dong)
        self._dong_toggle_btn.pack(side="right", padx=(0, 6))

        self._dong_inner_sep = tk.Frame(self._dong_section, bg=BORDER, height=1)
        self._dong_inner_sep.pack(fill="x", padx=15)

        self._dong_chips_frame = tk.Frame(self._dong_section, bg=SURFACE)
        self._dong_chips_frame.pack(fill="x", padx=15, pady=(4, 6))

        # 동 패널이 나타날 때 filter_sec 앞에 삽입되는 구분선
        self._dong_sep = tk.Frame(region_sec, bg=BORDER, height=1)

        # ── 필터 설정 ─────────────────────────────────────────────────────────
        tk.Frame(region_sec, bg=BORDER, height=1).pack(fill="x", padx=15, pady=(2, 0))

        self._filter_sec = tk.Frame(region_sec, bg=SURFACE)
        self._filter_sec.pack(fill="x")

        flt_hdr = tk.Frame(self._filter_sec, bg=SURFACE)
        flt_hdr.pack(fill="x", padx=15, pady=(8, 4))
        tk.Label(flt_hdr, text="필터", bg=SURFACE, fg=TEXT,
                 font=("맑은 고딕", 10, "bold")).pack(side="left")
        tk.Label(flt_hdr, text="  비워두면 제한 없음", bg=SURFACE, fg=TEXT_DIM,
                 font=FONT_LABEL).pack(side="left")
        _btn(flt_hdr, "초기화", self._clear_filters).pack(side="right")
        self._filter_toggle_btn = _btn(flt_hdr, "▲ 접기", self._toggle_filter)
        self._filter_toggle_btn.pack(side="right", padx=(0, 6))

        # 필터 본문 — 기본 열림
        self._filter_body = tk.Frame(self._filter_sec, bg=SURFACE)
        self._filter_body.pack(fill="x")
        self._filter_open = True

        def _fe(parent, var, w=7):
            wrap = tk.Frame(parent, bg=BORDER, bd=1)
            wrap.pack(side="left")
            e = tk.Entry(wrap, textvariable=var, width=w,
                         bg=INPUT_BG, fg=TEXT, insertbackground=ACCENT,
                         font=FONT_MONO, bd=0, relief="flat")
            e.pack(padx=6, pady=4)
            return e

        def _lbl(parent, text):
            tk.Label(parent, text=text, bg=SURFACE, fg=TEXT_DIM,
                     font=FONT_LABEL).pack(side="left", padx=(4, 0))

        r1 = tk.Frame(self._filter_body, bg=SURFACE)
        r1.pack(fill="x", padx=15, pady=(2, 2))
        tk.Label(r1, text="매매가", bg=SURFACE, fg=TEXT,
                 font=FONT_LABEL, width=8, anchor="w").pack(side="left")
        _fe(r1, self._f_price_min)
        _lbl(r1, "억 이상  ~")
        _fe(r1, self._f_price_max)
        _lbl(r1, "억 이하")

        r2 = tk.Frame(self._filter_body, bg=SURFACE)
        r2.pack(fill="x", padx=15, pady=2)
        tk.Label(r2, text="전용면적", bg=SURFACE, fg=TEXT,
                 font=FONT_LABEL, width=8, anchor="w").pack(side="left")
        _fe(r2, self._f_area_min)
        _lbl(r2, "평 이상  ~")
        _fe(r2, self._f_area_max)
        _lbl(r2, "평 이하")

        r3 = tk.Frame(self._filter_body, bg=SURFACE)
        r3.pack(fill="x", padx=15, pady=2)
        tk.Label(r3, text="입주가능일", bg=SURFACE, fg=TEXT,
                 font=FONT_LABEL, width=8, anchor="w").pack(side="left")
        _fe(r3, self._f_movein_yr, w=6)
        _lbl(r3, "년")
        _fe(r3, self._f_movein_mo, w=4)
        _lbl(r3, "월 이후")

        r4 = tk.Frame(self._filter_body, bg=SURFACE)
        r4.pack(fill="x", padx=15, pady=2)
        tk.Label(r4, text="방향", bg=SURFACE, fg=TEXT,
                 font=FONT_LABEL, width=8, anchor="w").pack(side="left")
        for d in ("남향", "남동향", "남서향", "동향", "서향", "북향", "북동향", "북서향"):
            self._f_dir_btns[d] = self._make_dir_chip(r4, d)

        r5 = tk.Frame(self._filter_body, bg=SURFACE)
        r5.pack(fill="x", padx=15, pady=2)
        tk.Label(r5, text="기보증금 비율", bg=SURFACE, fg=TEXT,
                 font=FONT_LABEL, width=8, anchor="w").pack(side="left")
        self._f_ratio_lbl = tk.Label(r5, text="제한 없음", bg=SURFACE, fg=ACCENT,
                                     font=("맑은 고딕", 9, "bold"), width=9, anchor="w")
        self._f_ratio_lbl.pack(side="left", padx=(6, 0))
        slider_frame = tk.Frame(r5, bg=SURFACE)
        slider_frame.pack(side="left", fill="x", expand=True, padx=(4, 0))
        self._f_ratio_slider = tk.Scale(
            slider_frame,
            variable=self._f_rent_ratio,
            from_=0, to=100, orient="horizontal",
            bg=SURFACE, fg=TEXT, troughcolor=INPUT_BG,
            highlightthickness=0, bd=0,
            activebackground=ACCENT, sliderrelief="flat",
            font=FONT_LABEL, showvalue=False,
            command=self._on_ratio_change,
        )
        self._f_ratio_slider.pack(fill="x", expand=True)
        _lbl(r5, "% 이상")

        r6 = tk.Frame(self._filter_body, bg=SURFACE)
        r6.pack(fill="x", padx=15, pady=2)
        tk.Label(r6, text="해당층", bg=SURFACE, fg=TEXT,
                 font=FONT_LABEL, width=8, anchor="w").pack(side="left")
        for fl in ("저층", "중층", "고층"):
            self._f_floor_btns[fl] = self._make_floor_chip(r6, fl)

        r7 = tk.Frame(self._filter_body, bg=SURFACE)
        r7.pack(fill="x", padx=15, pady=(2, 10))
        tk.Label(r7, text="단지 세대수", bg=SURFACE, fg=TEXT,
                 font=FONT_LABEL, width=8, anchor="w").pack(side="left")
        _fe(r7, self._f_household_min)
        _lbl(r7, "세대 이상")

        # 지역 직접 입력 + 검색 버튼
        self._region_row = tk.Frame(region_sec, bg=SURFACE)
        region_row = self._region_row
        region_row.pack(fill="x", padx=15, pady=(2, 12))

        region_entry_wrap = tk.Frame(region_row, bg=BORDER, bd=1)
        region_entry_wrap.pack(side="left", fill="x", expand=True, padx=(0, 8))
        self.region_entry = tk.Entry(
            region_entry_wrap,
            bg=INPUT_BG, fg=TEXT,
            insertbackground=ACCENT,
            font=FONT_MONO,
            bd=0, relief="flat",
        )
        self.region_entry.pack(fill="x", padx=8, pady=6)
        self.region_entry.insert(0, "예: 용두동, 강남구, 마포구")
        self.region_entry.config(fg=TEXT_DIM)
        self.region_entry.bind("<FocusIn>",  self._region_focus_in)
        self.region_entry.bind("<FocusOut>", self._region_focus_out)
        self.region_entry.bind("<Return>",   lambda e: self._start_region())
        self.region_entry.bind("<Meta-v>",   self._region_paste)
        self.region_entry.bind("<Control-v>", self._region_paste)

        self.region_btn = _btn(region_row, "검색 시작", self._start_region, primary=True)
        self.region_btn.pack(side="left")

        # ── "또는" 구분선 ─────────────────────────────────────────────────────
        or_frame = tk.Frame(root, bg=BG)
        or_frame.pack(fill="x", padx=28, pady=(8, 8))
        tk.Frame(or_frame, bg=BORDER, height=1).pack(side="left", fill="x", expand=True)
        tk.Label(or_frame, text="  또는  ", bg=BG, fg=TEXT_DIM, font=FONT_LABEL).pack(side="left")
        tk.Frame(or_frame, bg=BORDER, height=1).pack(side="left", fill="x", expand=True)

        # ── URL 직접 입력 섹션 ────────────────────────────────────────────────
        url_sec = tk.Frame(root, bg=SURFACE)
        url_sec.pack(fill="x", padx=28)

        _uhdr_row = tk.Frame(url_sec, bg=SURFACE)
        _uhdr_row.pack(fill="x")
        tk.Frame(_uhdr_row, bg=INFO, width=3).pack(side="left", fill="y")
        _uhdr_inner = tk.Frame(_uhdr_row, bg=SURFACE)
        _uhdr_inner.pack(side="left", fill="x", expand=True, padx=(12, 12), pady=(10, 8))
        _uhdr_lrow = tk.Frame(_uhdr_inner, bg=SURFACE)
        _uhdr_lrow.pack(fill="x")
        tk.Label(_uhdr_lrow, text="매물 URL 직접 입력", bg=SURFACE, fg=TEXT,
                 font=("맑은 고딕", 10, "bold")).pack(side="left")
        tk.Label(_uhdr_lrow, text="  여러 개는 줄바꿈으로 구분", bg=SURFACE,
                 fg=TEXT_DIM, font=FONT_LABEL).pack(side="left")
        _btn(_uhdr_lrow, "붙여넣기", self._paste).pack(side="right")
        _btn(_uhdr_lrow, "지우기", self._clear_input).pack(side="right", padx=(0, 6))

        url_entry_outer = tk.Frame(url_sec, bg=SURFACE)
        url_entry_outer.pack(fill="x", padx=15, pady=(0, 12))
        url_wrap = tk.Frame(url_entry_outer, bg=BORDER, bd=1)
        url_wrap.pack(fill="x")

        self.url_text = tk.Text(
            url_wrap, height=5,
            bg=INPUT_BG, fg=TEXT,
            insertbackground=ACCENT,
            font=FONT_MONO,
            bd=0, padx=10, pady=8,
            wrap="none", relief="flat",
            selectbackground=ACCENT, selectforeground="#0E1218",
        )
        url_sb = tk.Scrollbar(url_wrap, orient="vertical",
                              command=self.url_text.yview, bg=SURFACE)
        self.url_text.configure(yscrollcommand=url_sb.set)
        self.url_text.pack(side="left", fill="both", expand=True)
        url_sb.pack(side="right", fill="y")

        for key, fn in [("v", self._paste), ("c", self._copy),
                        ("a", self._select_all), ("x", self._cut)]:
            self.url_text.bind(f"<Control-{key}>", fn)
            self.url_text.bind(f"<Meta-{key}>", fn)

        self._ctx_menu = tk.Menu(self.root, tearoff=0, bg=SURFACE, fg=TEXT,
                                  activebackground=ACCENT, activeforeground="#0E1218")
        self._ctx_menu.add_command(label="붙여넣기  Ctrl+V", command=self._paste)
        self._ctx_menu.add_command(label="복사      Ctrl+C", command=self._copy)
        self._ctx_menu.add_command(label="잘라내기  Ctrl+X", command=self._cut)
        self._ctx_menu.add_separator()
        self._ctx_menu.add_command(label="전체 선택  Ctrl+A", command=self._select_all)
        self._ctx_menu.add_command(label="전체 지우기", command=self._clear_input)
        self.url_text.bind("<Button-2>", self._show_ctx)
        self.url_text.bind("<Button-3>", self._show_ctx)
        self.url_text.bind("<Control-Button-1>", self._show_ctx)

        # ── 저장 위치 + 액션 버튼 행 ──────────────────────────────────────────
        ctrl = tk.Frame(root, bg=BG)
        ctrl.pack(fill="x", padx=28, pady=(12, 10))

        # 저장 위치 (왼쪽) — 한 줄: [레이블] [경로] [변경] [새파일]
        path_frame = tk.Frame(ctrl, bg=BG)
        path_frame.pack(side="left", fill="x", expand=True)
        tk.Label(path_frame, text="저장 위치", bg=BG, fg=TEXT,
                 font=("맑은 고딕", 10, "bold")).pack(side="left", padx=(0, 8))
        self.path_lbl = tk.Label(
            path_frame, textvariable=self.excel_path,
            bg=BG, fg=TEXT_DIM, font=FONT_LABEL,
            cursor="hand2", anchor="w",
        )
        self.path_lbl.pack(side="left")
        self.path_lbl.bind("<Button-1>", lambda _: self._choose_path())
        _btn(path_frame, "변경", self._choose_path).pack(side="left", padx=(8, 0))
        _btn(path_frame, "새파일", self._new_file).pack(side="left", padx=(4, 0))

        # 액션 버튼 (오른쪽)
        action_frame = tk.Frame(ctrl, bg=BG)
        action_frame.pack(side="right", anchor="s")
        _btn(action_frame, "Excel 열기", self._open_excel).pack(side="left", padx=(0, 8))
        self.save_btn = _btn(action_frame, "저장하기", self._start, primary=True)
        self.save_btn.pack(side="left")

        # ── PDF 내보내기 섹션 ─────────────────────────────────────────────
        pdf_outer = tk.Frame(root, bg=BG)
        pdf_outer.pack(fill="x", padx=28, pady=(4, 8))

        pdf_hdr = tk.Frame(pdf_outer, bg=BG)
        pdf_hdr.pack(fill="x", pady=(0, 4))
        tk.Label(pdf_hdr, text="PDF 내보내기", bg=BG, fg=TEXT,
                 font=("맑은 고딕", 10, "bold")).pack(side="left")
        tk.Label(pdf_hdr, text="  A4 가로 · 좁은 여백 · 너비 맞춤",
                 bg=BG, fg=TEXT_DIM, font=FONT_LABEL).pack(side="left")

        pdf_ctrl = tk.Frame(pdf_outer, bg=BG)
        pdf_ctrl.pack(fill="x")
        tk.Label(pdf_ctrl, textvariable=self._pdf_path,
                 bg=BG, fg=TEXT_DIM, font=FONT_LABEL, anchor="w").pack(
                     side="left", fill="x", expand=True)
        self.pdf_btn = _btn(pdf_ctrl, "PDF 저장하기", self._export_pdf, primary=True)
        self.pdf_btn.pack(side="right")
        _btn(pdf_ctrl, "PDF 열기", self._open_pdf).pack(side="right", padx=(0, 6))

        # ── 구분선 ────────────────────────────────────────────────────────────
        tk.Frame(root, bg=BORDER, height=1).pack(fill="x", padx=28, pady=(2, 0))

        # ── 수집 로그 ─────────────────────────────────────────────────────────
        log_outer = tk.Frame(root, bg=BG)
        log_outer.pack(fill="x", padx=28, pady=(12, 24))

        log_hdr = tk.Frame(log_outer, bg=BG)
        log_hdr.pack(fill="x", pady=(0, 6))
        tk.Label(log_hdr, text="수집 로그", bg=BG, fg=TEXT,
                 font=("맑은 고딕", 10, "bold")).pack(side="left")
        _btn(log_hdr, "지우기", self._clear).pack(side="right")
        _btn(log_hdr, "복사", self._copy_log).pack(side="right", padx=(0, 6))

        log_wrap = tk.Frame(log_outer, bg=BORDER, bd=1)
        log_wrap.pack(fill="x")

        self.log = tk.Text(
            log_wrap,
            bg=INPUT_BG, fg=TEXT,
            font=FONT_MONO,
            bd=0, padx=12, pady=10,
            height=10,
            state="disabled", wrap="word", relief="flat",
        )
        log_sb = tk.Scrollbar(log_wrap, orient="vertical",
                              command=self.log.yview, bg=SURFACE)
        self.log.configure(yscrollcommand=log_sb.set)
        self.log.pack(side="left", fill="both", expand=True)
        log_sb.pack(side="right", fill="y")

        self.log.tag_config("success", foreground=SUCCESS)
        self.log.tag_config("error",   foreground=ERROR)
        self.log.tag_config("info",    foreground=INFO)
        self.log.tag_config("dim",     foreground=TEXT_DIM)
        self.log.tag_config("accent",  foreground=ACCENT,
                            font=("Menlo", 10, "bold"))

        self._log("준비됨. URL을 붙여넣고 저장하기를 누르세요.", "dim")

    # ── 클립보드 / 컨텍스트 메뉴 ──────────────────────────────────────────────

    def _paste(self, event=None):
        try:
            text = self.root.clipboard_get().strip()
            if not text:
                return "break"
            existing = {l.strip() for l in self.url_text.get("1.0", "end").splitlines() if l.strip()}
            if text in existing:
                self._log(f"이미 입력된 URL — 건너뜀", "dim")
            else:
                current = self.url_text.get("1.0", "end-1c")
                if current.strip():
                    self.url_text.insert("end", "\n" + text)
                else:
                    self.url_text.insert("1.0", text)
        except tk.TclError:
            pass
        return "break"

    def _copy(self, event=None):
        try:
            sel = self.url_text.get(tk.SEL_FIRST, tk.SEL_LAST)
            self.root.clipboard_clear()
            self.root.clipboard_append(sel)
        except tk.TclError:
            pass
        return "break"

    def _cut(self, event=None):
        self._copy()
        try:
            self.url_text.delete(tk.SEL_FIRST, tk.SEL_LAST)
        except tk.TclError:
            pass
        return "break"

    def _select_all(self, event=None):
        self.url_text.tag_add(tk.SEL, "1.0", tk.END)
        self.url_text.mark_set(tk.INSERT, "1.0")
        self.url_text.see(tk.INSERT)
        return "break"

    def _clear_input(self):
        self.url_text.delete("1.0", tk.END)

    def _show_ctx(self, event):
        self._ctx_menu.tk_popup(event.x_root, event.y_root)

    # ── 로그 헬퍼 ──────────────────────────────────────────────────────────────

    def _log(self, msg: str, tag: str = ""):
        self.log.configure(state="normal")
        self.log.insert("end", msg + "\n", tag if tag else ())
        self.log.see("end")
        self.log.configure(state="disabled")

    def _clear(self):
        self.log.configure(state="normal")
        self.log.delete("1.0", "end")
        self.log.configure(state="disabled")

    def _copy_log(self):
        text = self.log.get("1.0", "end").strip()
        if text:
            self.root.clipboard_clear()
            self.root.clipboard_append(text)
            self._log("로그가 클립보드에 복사되었습니다.", "dim")

    # ── 지역 칩 ───────────────────────────────────────────────────────────────

    def _add_chip(self, parent, name: str):
        """지역 토글 칩 버튼 생성 및 등록."""
        def toggle():
            if name in self._selected_regions:
                self._selected_regions.discard(name)
                btn.config(bg=SURFACE, fg=TEXT_DIM)
            else:
                self._selected_regions.add(name)
                btn.config(bg=ACCENT, fg="#0E1218")
            self._show_dong_for(name)

        btn = _Btn(parent, name, toggle)
        btn._lbl.config(padx=8, pady=3, font=("맑은 고딕", 9))
        btn.config(fg=TEXT_DIM)
        btn.pack(side="left", padx=2, pady=1)
        self._chip_btns[name] = btn

    def _select_all_seoul(self):
        for name in SEOUL_REGIONS:
            self._selected_regions.add(name)
            if name in self._chip_btns:
                self._chip_btns[name].config(bg=ACCENT, fg="#0E1218")

    def _deselect_all(self):
        for name in list(self._selected_regions):
            self._selected_regions.discard(name)
            if name in self._chip_btns:
                self._chip_btns[name].config(bg=SURFACE, fg=TEXT_DIM)
        self._selected_dong.clear()
        self._dong_chip_btns.clear()
        for w in self._dong_chips_frame.winfo_children():
            w.destroy()
        if self._dong_section.winfo_ismapped():
            self._dong_section.pack_forget()
            self._dong_sep.pack_forget()

    def _show_dong_for(self, _gu_name: str):
        """선택된 모든 구의 동을 동 패널에 표시. 구 해제 시 해당 구 동 제거."""
        # 선택 해제된 구의 동을 selected_dong에서 제거
        for gu in SEOUL_REGIONS:
            if gu not in self._selected_regions:
                for dong in SEOUL_DONG.get(gu, []):
                    self._selected_dong.discard(dong)

        # 현재 선택된 구들의 모든 동 수집 (SEOUL_REGIONS 순서 유지)
        all_dong = []
        for gu in SEOUL_REGIONS:
            if gu in self._selected_regions:
                all_dong.extend(SEOUL_DONG.get(gu, []))

        # 패널 숨기기
        if not all_dong:
            self._dong_chip_btns.clear()
            for w in self._dong_chips_frame.winfo_children():
                w.destroy()
            if self._dong_section.winfo_ismapped():
                self._dong_section.pack_forget()
                self._dong_sep.pack_forget()
            return

        # 기존 동 칩 제거 후 재생성
        self._dong_chip_btns.clear()
        for w in self._dong_chips_frame.winfo_children():
            w.destroy()

        COLS = 8
        for r_start in range(0, len(all_dong), COLS):
            row_f = tk.Frame(self._dong_chips_frame, bg=SURFACE)
            row_f.pack(fill="x", pady=1)
            for dong in all_dong[r_start:r_start + COLS]:
                self._add_dong_chip(row_f, dong, selected=(dong in self._selected_dong))

        selected_gu = [g for g in SEOUL_REGIONS if g in self._selected_regions]
        self._dong_title_lbl.config(text=f"{', '.join(selected_gu)}  >  동 선택")

        # 접혀 있으면 다시 펼치기
        if not self._dong_chips_open:
            self._dong_chips_open = True
            self._dong_inner_sep.pack(fill="x", padx=14)
            self._dong_chips_frame.pack(fill="x", padx=14, pady=(4, 6))
            self._dong_toggle_btn.config(text="▲ 접기")

        if not self._dong_section.winfo_ismapped():
            self._dong_section.pack(fill="x", before=self._filter_sec)
            self._dong_sep.pack(fill="x", padx=14, pady=(0, 4), before=self._filter_sec)

    def _add_dong_chip(self, parent, name: str, selected: bool = False):
        def toggle():
            if name in self._selected_dong:
                self._selected_dong.discard(name)
                btn.config(bg=SURFACE, fg=TEXT_DIM)
            else:
                self._selected_dong.add(name)
                btn.config(bg=INFO, fg="#0E1218")

        btn = _Btn(parent, name, toggle)
        btn._lbl.config(padx=8, pady=3, font=("맑은 고딕", 9))
        if selected:
            btn.config(bg=INFO, fg="#0E1218")
        else:
            btn.config(fg=TEXT_DIM)
        btn.pack(side="left", padx=2, pady=1)
        self._dong_chip_btns[name] = btn

    def _toggle_dong(self):
        self._dong_chips_open = not self._dong_chips_open
        if self._dong_chips_open:
            self._dong_inner_sep.pack(fill="x", padx=14)
            self._dong_chips_frame.pack(fill="x", padx=14, pady=(4, 6))
            self._dong_toggle_btn.config(text="▲ 접기")
        else:
            self._dong_chips_frame.pack_forget()
            self._dong_inner_sep.pack_forget()
            self._dong_toggle_btn.config(text="▶ 펼치기")

    def _select_all_dong(self):
        for name, btn in self._dong_chip_btns.items():
            self._selected_dong.add(name)
            btn.config(bg=INFO, fg="#0E1218")

    def _deselect_all_dong(self):
        for name, btn in self._dong_chip_btns.items():
            self._selected_dong.discard(name)
            btn.config(bg=SURFACE, fg=TEXT_DIM)
        self._selected_dong.clear()

    # ── 필터 ─────────────────────────────────────────────────────────────────

    def _on_ratio_change(self, val=None):
        v = self._f_rent_ratio.get()
        self._f_ratio_lbl.config(text="제한 없음" if v == 0 else f"{v}% 이상")

    def _make_floor_chip(self, parent, name: str) -> "_Btn":
        def toggle():
            if name in self._f_floors:
                self._f_floors.discard(name)
                btn.config(bg=SURFACE, fg=TEXT_DIM)
            else:
                self._f_floors.add(name)
                btn.config(bg=SUCCESS, fg="#0E1218")
        btn = _Btn(parent, name, toggle)
        btn._lbl.config(padx=10, pady=3, font=("맑은 고딕", 9))
        btn.config(fg=TEXT_DIM)
        btn.pack(side="left", padx=2, pady=1)
        return btn

    def _make_dir_chip(self, parent, name: str) -> "_Btn":
        def toggle():
            if name in self._f_directions:
                self._f_directions.discard(name)
                btn.config(bg=SURFACE, fg=TEXT_DIM)
            else:
                self._f_directions.add(name)
                btn.config(bg=INFO, fg="#0E1218")
        btn = _Btn(parent, name, toggle)
        btn._lbl.config(padx=8, pady=3, font=("맑은 고딕", 9))
        btn.config(fg=TEXT_DIM)
        btn.pack(side="left", padx=2, pady=1)
        return btn

    def _toggle_filter(self):
        self._filter_open = not self._filter_open
        if self._filter_open:
            self._filter_body.pack(fill="x")
            self._filter_toggle_btn.config(text="▲ 접기")
        else:
            self._filter_body.pack_forget()
            self._filter_toggle_btn.config(text="▼ 펼치기")

    def _clear_filters(self):
        for v in (self._f_price_min, self._f_price_max,
                  self._f_area_min, self._f_area_max,
                  self._f_movein_yr, self._f_movein_mo,
                  self._f_household_min):
            v.set("")
        for btn in self._f_dir_btns.values():
            btn.config(bg=SURFACE, fg=TEXT_DIM)
        self._f_directions.clear()
        self._f_rent_ratio.set(0)
        self._f_ratio_lbl.config(text="제한 없음")
        for btn in self._f_floor_btns.values():
            btn.config(bg=SURFACE, fg=TEXT_DIM)
        self._f_floors.clear()

    def _get_filters(self) -> dict:
        def _int(v):
            try: return int(v.get().strip())
            except: return None
        def _float(v):
            try: return float(v.get().strip())
            except: return None
        return {
            "price_min":     (_float(self._f_price_min) or 0) * 10000 or None,
            "price_max":     (_float(self._f_price_max) or 0) * 10000 or None,
            "area_min":      _float(self._f_area_min),
            "area_max":      _float(self._f_area_max),
            "movein_yr":     self._parse_year(self._f_movein_yr.get()),
            "movein_mo":     _int(self._f_movein_mo) or 1,
            "directions":    set(self._f_directions),
            "rent_ratio":    self._f_rent_ratio.get(),   # 0 = 제한 없음
            "floors":        set(self._f_floors),
            "household_min": _int(self._f_household_min),
        }

    @staticmethod
    def _parse_year(s: str):
        """'2027' → 2027, '27' → 2027, 빈값 → None."""
        try:
            yr = int(str(s).strip())
            return yr + 2000 if yr < 100 else yr
        except (ValueError, TypeError):
            return None

    @staticmethod
    def _parse_price(s: str) -> float:
        """'13억5,000' or '80,000' → 만원 float. 파싱 불가 시 0."""
        s = str(s or "").replace(",", "").replace(" ", "")
        m = re.match(r"(\d+(?:\.\d+)?)억(\d*)", s)
        if m:
            return float(m.group(1)) * 10000 + (int(m.group(2)) if m.group(2) else 0)
        try:
            return float(s)
        except ValueError:
            return 0.0

    @staticmethod
    def _parse_movein(s: str):
        """'2027년 11월' / '2027.11.' → (2027, 11) or None. '즉시'/'협의' → None(통과)."""
        s = str(s or "")
        if not s or any(k in s for k in ("즉시", "협의", "미정")):
            return None
        m = re.search(r"(\d{4})[년.\s]+(\d{1,2})", s)
        if m:
            return int(m.group(1)), int(m.group(2))
        return None

    def _passes_filter(self, fields: dict) -> tuple[bool, str]:
        """(통과여부, 제외이유). True=저장, False=건너뜀."""
        f = self._get_filters()

        # 매매가
        if f["price_min"] or f["price_max"]:
            price = self._parse_price(fields.get("price_main", ""))
            if price > 0:
                if f["price_min"] and price < f["price_min"]:
                    return False, f"매매가 {fields.get('price_main','')} < {self._f_price_min.get()}억"
                if f["price_max"] and price > f["price_max"]:
                    return False, f"매매가 {fields.get('price_main','')} > {self._f_price_max.get()}억"

        # 전용면적
        if f["area_min"] or f["area_max"]:
            area_s = str(fields.get("area_exclusive", "") or "").replace("평", "")
            try:
                area = float(area_s)
                if f["area_min"] and area < f["area_min"]:
                    return False, f"전용 {area}평 < {self._f_area_min.get()}평"
                if f["area_max"] and area > f["area_max"]:
                    return False, f"전용 {area}평 > {self._f_area_max.get()}평"
            except (ValueError, TypeError):
                pass

        # 입주가능일
        if f["movein_yr"]:
            ym = self._parse_movein(fields.get("move_in_date", ""))
            if ym and ym < (f["movein_yr"], f["movein_mo"]):
                return False, f"입주일 {ym[0]}년{ym[1]}월 < 필터"

        # 방향
        if f["directions"]:
            direction = str(fields.get("direction", "") or "")
            if direction and direction not in f["directions"]:
                return False, f"방향 {direction}"

        # 기보증금 비율 (기보증금 / 매매가 × 100 ≥ 설정값)
        if f["rent_ratio"] > 0:
            price = self._parse_price(fields.get("price_main", ""))
            rent_s = str(fields.get("rent_price", "") or "")
            # "7억 9,000 (2026.06. 거래)" → 앞부분만 파싱
            rent = self._parse_price(rent_s.split("(")[0])
            if price > 0 and rent > 0:
                ratio = rent / price * 100
                if ratio < f["rent_ratio"]:
                    return False, f"기보증금 비율 {ratio:.0f}% < {f['rent_ratio']}%"
            elif price > 0 and rent == 0:
                return False, "기보증금 없음"

        # 해당층 (저/중/고)
        if f["floors"]:
            floor_s = str(fields.get("floor", "") or "")
            # "5/15" 형태에서 해당층 추출
            m = re.match(r"(\d+)/(\d+)", floor_s)
            if m:
                cur, total = int(m.group(1)), int(m.group(2))
                if total > 0:
                    ratio = cur / total
                    if ratio <= 0.33:
                        floor_type = "저층"
                    elif ratio <= 0.66:
                        floor_type = "중층"
                    else:
                        floor_type = "고층"
                    if floor_type not in f["floors"]:
                        return False, f"{floor_type} 제외"
            elif floor_s:
                # "저층"/"중층"/"고층" 텍스트가 직접 있는 경우
                matched = any(fl in floor_s for fl in f["floors"])
                if not matched:
                    return False, f"층 '{floor_s}' 제외"

        # 단지 세대수
        if f["household_min"]:
            household_str = str(fields.get("household_by_type", "") or "")
            total_str = household_str.split("세대")[0]
            try:
                if int(total_str) < f["household_min"]:
                    return False, f"단지 세대수 {total_str}세대 < {f['household_min']}세대"
            except (ValueError, TypeError):
                pass

        return True, ""

    # ── 지역 검색 ─────────────────────────────────────────────────────────────

    _REGION_PLACEHOLDER = "예: 용두동, 강남구, 마포구"

    def _region_focus_in(self, event=None):
        if self.region_entry.get() == self._REGION_PLACEHOLDER:
            self.region_entry.delete(0, tk.END)
            self.region_entry.config(fg=TEXT)

    def _region_focus_out(self, event=None):
        if not self.region_entry.get().strip():
            self.region_entry.insert(0, self._REGION_PLACEHOLDER)
            self.region_entry.config(fg=TEXT_DIM)

    def _region_paste(self, event=None):
        try:
            self.region_entry.delete(0, tk.END)
            self.region_entry.insert(0, self.root.clipboard_get())
            self.region_entry.config(fg=TEXT)
        except tk.TclError:
            pass
        return "break"

    def _start_region(self):
        if self.running:
            return
        if self._selected_dong:
            regions = sorted(self._selected_dong)
        elif self._selected_regions:
            regions = sorted(self._selected_regions)
        else:
            name = self.region_entry.get().strip()
            if not name or name == self._REGION_PLACEHOLDER:
                messagebox.showwarning("입력 없음", "지역을 선택하거나 직접 입력해 주세요.")
                return
            regions = [name]

        self.running = True
        self.region_btn.config(text="검색 중…", state="disabled", bg=SURFACE, fg=TEXT_DIM)
        self.save_btn.config(state="disabled")
        threading.Thread(target=self._run_region, args=(regions,), daemon=True).start()

    def _run_region(self, regions: list[str]):
        q = self.q

        def log(msg, tag="dim"):
            if any(k in msg for k in ["지역 코드", "완료", "수집", "인증"]):
                tag = "info"
            q.put(("log", msg, tag))

        total_ok = total_skip = 0

        for idx, region_name in enumerate(regions, 1):
            log(f"\n── [{idx}/{len(regions)}] {region_name} {'─' * 28}", "accent")
            try:
                articles = search_region_articles(region_name, log=log)
            except RuntimeError as e:
                log(f"  ✗ 실패: {e}", "error")
                continue

            if not articles:
                log("  검색 결과 없음. 지역명을 다시 확인해 주세요.", "error")
                continue

            excel = Path(self.excel_path.get())
            wb, ws = load_or_create_workbook(excel)
            ok = skip = filtered = 0
            for fields in articles:
                article_no = str(fields.get("article_no", ""))
                if not article_no:
                    continue
                if is_duplicate(ws, article_no,
                                fields.get("complex_name", ""),
                                fields.get("floor", "")):
                    skip += 1
                    continue
                passes, reason = self._passes_filter(fields)
                if not passes:
                    log(f"  필터 제외: {fields.get('complex_name','')} — {reason}", "dim")
                    filtered += 1
                    continue
                next_row = ws.max_row + 1
                append_row(ws, fields, next_row)
                ok += 1
            wb.save(excel)
            log(f"  저장 {ok}건 / 중복 {skip}건 / 필터 {filtered}건", "info")
            total_ok += ok
            total_skip += skip

        log(
            f"\n── 전체 완료: 저장 {total_ok}건 / 중복 건너뜀 {total_skip}건  {'─' * 16}",
            "accent",
        )
        q.put(("region_done", None, None))

    # ── 액션 ──────────────────────────────────────────────────────────────────

    def _update_pdf_path(self):
        pdf = Path(self.excel_path.get()).with_suffix(".pdf")
        self._pdf_path.set(str(pdf))

    def _export_pdf(self):
        if not _HAS_XLWINGS:
            messagebox.showerror("패키지 없음", "xlwings가 설치되지 않았습니다.\npip3 install xlwings")
            return
        excel = Path(self.excel_path.get())
        if not excel.exists():
            messagebox.showwarning("파일 없음",
                                   f"저장된 엑셀 파일이 없습니다.\n\n{excel}")
            return
        pdf = excel.with_suffix(".pdf")
        self._log(f"\nPDF 변환 시작 → {pdf.name}", "info")
        self.pdf_btn.config(state="disabled", text="변환 중…")

        def run():
            try:
                app = xw.App(visible=False)
                try:
                    wb = app.books.open(str(excel))
                    for sheet in wb.sheets:
                        ps = sheet.api.page_setup
                        ps.orientation = 2          # xlLandscape
                        ps.fit_to_pages_wide = 1
                        ps.fit_to_pages_tall = False
                        # 좁은 여백: 0.25인치 좌우, 0.5인치 상하
                        pts = app.api.inches_to_points
                        ps.left_margin   = pts(0.25)
                        ps.right_margin  = pts(0.25)
                        ps.top_margin    = pts(0.5)
                        ps.bottom_margin = pts(0.5)
                    wb.to_pdf(str(pdf))
                    wb.close()
                    self.q.put(("pdf_done", str(pdf), None))
                finally:
                    app.quit()
            except Exception as e:
                self.q.put(("pdf_error", str(e), None))

        threading.Thread(target=run, daemon=True).start()

    def _choose_path(self):
        p = filedialog.asksaveasfilename(
            defaultextension=".xlsx",
            filetypes=[("Excel 파일", "*.xlsx")],
            initialfile="네이버_부동산_매물.xlsx",
        )
        if p:
            self.excel_path.set(p)

    def _new_file(self):
        import datetime
        today = datetime.date.today().strftime("%Y%m%d")
        p = filedialog.asksaveasfilename(
            defaultextension=".xlsx",
            filetypes=[("Excel 파일", "*.xlsx")],
            initialfile=f"네이버_부동산_매물_{today}.xlsx",
        )
        if p:
            self.excel_path.set(p)
            self._log(f"새 파일로 변경됨: {p}", "info")

    def _open_excel(self):
        path = Path(self.excel_path.get())
        if not path.exists():
            messagebox.showwarning("파일 없음",
                                   f"아직 저장된 파일이 없습니다.\n\n{path}")
            return
        if sys.platform == "darwin":
            subprocess.run(["open", str(path)])
        elif sys.platform == "win32":
            os.startfile(str(path))
        else:
            subprocess.run(["xdg-open", str(path)])

    def _open_pdf(self):
        path = Path(self._pdf_path.get())
        if not path.exists():
            messagebox.showwarning("파일 없음",
                                   f"아직 저장된 PDF가 없습니다.\n먼저 PDF 저장하기를 눌러주세요.\n\n{path}")
            return
        if sys.platform == "darwin":
            subprocess.run(["open", str(path)])
        elif sys.platform == "win32":
            os.startfile(str(path))
        else:
            subprocess.run(["xdg-open", str(path)])

    def _start(self):
        if self.running:
            return

        raw  = self.url_text.get("1.0", "end").strip()
        urls = [u.strip() for u in raw.splitlines() if u.strip()]

        if not urls:
            messagebox.showwarning("입력 없음", "URL을 하나 이상 입력해 주세요.")
            return

        self.running = True
        self.save_btn.config(
            text="수집 중…", state="disabled",
            bg=SURFACE, fg=TEXT_DIM,
        )
        threading.Thread(target=self._scrape, args=(urls,), daemon=True).start()

    # ── 스크래핑 (백그라운드 스레드) ──────────────────────────────────────────

    def _scrape(self, urls: list[str]):
        q = self.q

        def log(msg, tag="dim"):
            if any(k in msg for k in ["완료", "수집", "인증"]):
                tag = "info"
            q.put(("log", msg, tag))

        log(f"\n── URL 입력 ({len(urls)}개) {'─' * 32}", "accent")

        excel = Path(self.excel_path.get())
        wb, ws = load_or_create_workbook(excel)

        ok = skip = fail = filtered = 0

        # 1. 이미 등록된 매물 사전 제거
        urls_to_fetch = []
        for url in urls:
            try:
                article_no, _ = parse_url(url)
            except ValueError as e:
                log(f"  ✗ URL 오류: {e}", "error")
                fail += 1
                continue
            if is_duplicate(ws, article_no):
                log(f"  → 이미 등록된 매물 — 건너뜀  ({article_no})", "dim")
                skip += 1
            else:
                urls_to_fetch.append(url)

        if not urls_to_fetch:
            log(f"  저장 {ok}건 / 중복 {skip}건 / 필터 {filtered}건", "info")
            log(f"\n── 완료: 저장 {ok}건 / 중복 건너뜀 {skip}건  {'─' * 22}", "accent")
            q.put(("done", None, None))
            return

        # 2. 수집 (지역 검색과 동일한 방식)
        try:
            articles = collect_articles_by_url_list(urls_to_fetch, log=log)
        except RuntimeError as e:
            log(f"  ✗ 수집 실패: {e}", "error")
            fail += len(urls_to_fetch)
            log(f"  저장 {ok}건 / 중복 {skip}건 / 필터 {filtered}건", "info")
            log(f"\n── 완료: 저장 {ok}건 / 중복 건너뜀 {skip}건  {'─' * 22}", "accent")
            q.put(("done", None, None))
            return

        # 3. 중복 재확인 + 필터 + 저장
        for fields in articles:
            article_no = str(fields.get("article_no", ""))

            if is_duplicate(ws, article_no,
                            fields.get("complex_name", ""),
                            fields.get("floor", "")):
                log(f"  → 단지+층 중복 — 건너뜀  ({fields.get('complex_name','')} {fields.get('floor','')})", "dim")
                skip += 1
                continue

            passes, reason = self._passes_filter(fields)
            if not passes:
                log(f"  필터 제외: {reason}", "dim")
                filtered += 1
                continue

            next_row = ws.max_row + 1
            append_row(ws, fields, next_row)
            wb.save(excel)
            ok += 1

        log(f"  저장 {ok}건 / 중복 {skip}건 / 필터 {filtered}건", "info")
        log(
            f"\n── 완료: 저장 {ok}건 / 중복 건너뜀 {skip}건  {'─' * 22}",
            "accent",
        )
        q.put(("done", None, None))

    # ── 큐 폴링 ───────────────────────────────────────────────────────────────

    def _poll(self):
        try:
            while True:
                kind, a, b = self.q.get_nowait()
                if kind == "log":
                    self._log(a, b)
                elif kind == "done":
                    self.running = False
                    self.save_btn.config(
                        text="저장하기", state="normal",
                        bg=ACCENT, fg="#0E1218",
                    )
                elif kind == "region_done":
                    self.running = False
                    self.region_btn.config(
                        text="검색 시작", state="normal",
                        bg=ACCENT, fg="#0E1218",
                    )
                    self.save_btn.config(state="normal")
                elif kind == "pdf_done":
                    self._log(f"PDF 저장 완료 → {a}", "success")
                    self.pdf_btn.config(state="normal", text="PDF 저장하기")
                elif kind == "pdf_error":
                    self._log(f"PDF 변환 실패: {a}", "error")
                    self.pdf_btn.config(state="normal", text="PDF 저장하기")
        except queue.Empty:
            pass
        self.root.after(80, self._poll)

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    App().run()
