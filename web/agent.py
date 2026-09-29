"""브라우저 북마클릿 에이전트용 작업 큐.

아이폰 앱(SOCKS5 릴레이) 없이도, Safari로 new.land.naver.com을 열어둔 상태에서
북마클릿(web/static/agent.js)을 실행하면 그 탭이 실제 네이버 API를 직접
호출해서 결과를 이 서버로 보고하는 방식. 지오코딩(지역명 -> 위경도)만 서버가
미리 해두고, cortarNo 조회/매물 목록/상세 조회는 전부 에이전트(브라우저 탭)가
수행한다 — 네이버가 서버/클라우드 IP를 막기 때문에 이 부분만큼은 반드시
실제 기기의 네트워크를 거쳐야 한다.
"""

import asyncio
import time
import uuid as _uuid
from pathlib import Path

from naver_land_scraper import _geocode, append_row, extract_fields, is_duplicate, load_or_create_workbook

_JOB_TTL_SECONDS = 3600


class AgentJob:
    def __init__(self, job_id, session_id, regions, filters, max_count, excel_path, log_q, loop):
        self.job_id = job_id
        self.session_id = session_id
        self.regions = regions  # [{"name", "lat", "lon"}]
        self.filters = filters
        self.max_count = max_count
        self.cursor = 0
        self.excel_path = excel_path
        self.wb, self.ws = load_or_create_workbook(excel_path)
        self.log_q = log_q
        self.loop = loop
        self.total_ok = self.total_skip = self.total_filtered = 0
        self.region_counts = {"ok": 0, "skip": 0, "filtered": 0, "unsaved": 0}
        self.created_at = time.time()
        self.last_seen = time.time()

    def log(self, msg: str, tag: str = "dim"):
        self.loop.call_soon_threadsafe(self.log_q.put_nowait, {"type": "log", "msg": msg, "tag": tag})


_jobs: dict[str, AgentJob] = {}
_session_current_job: dict[str, str] = {}  # session_id -> 가장 최근 job_id (에이전트가 폴링으로 발견용)


def _cleanup_stale():
    now = time.time()
    for jid in [j for j, job in _jobs.items() if now - job.last_seen > _JOB_TTL_SECONDS]:
        _jobs.pop(jid, None)


def create_job(session_id, region_names, filters, max_count, log_q, loop, excel_path, log_fn):
    """지역명을 서버에서 미리 지오코딩한 뒤 작업을 만든다. (네트워크 I/O 포함 — 스레드에서 호출할 것)"""
    _cleanup_stale()
    resolved = []
    for name in region_names:
        try:
            lat, lon = _geocode(name, log=log_fn)
            resolved.append({"name": name, "lat": lat, "lon": lon})
        except Exception as e:
            log_fn(f"  ✗ '{name}' 좌표 조회 실패: {e}", "error")

    job_id = str(_uuid.uuid4())[:8]
    _jobs[job_id] = AgentJob(job_id, session_id, resolved, filters, max_count, excel_path, log_q, loop)
    _session_current_job[session_id] = job_id
    return job_id, len(resolved)


def get_job(job_id: str) -> AgentJob | None:
    return _jobs.get(job_id)


def current_job_for_session(session_id: str) -> str | None:
    """이 세션에 진행 중(미완료)인 최신 job_id. 없으면 None.
    북마클릿이 job_id를 몰라도 session_id만으로 자기 작업을 찾을 수 있게 한다."""
    job_id = _session_current_job.get(session_id)
    if job_id and job_id in _jobs:
        return job_id
    return None


def next_region(job_id: str, count_rows_fn) -> dict | None:
    job = _jobs.get(job_id)
    if not job:
        return None
    job.last_seen = time.time()
    if job.cursor >= len(job.regions):
        finish(job_id, count_rows_fn)
        return None
    region = job.regions[job.cursor]
    job.region_counts = {"ok": 0, "skip": 0, "filtered": 0, "unsaved": 0}
    job.log(f"\n── [{job.cursor + 1}/{len(job.regions)}] {region['name']} ──", "accent")
    return {
        "name": region["name"], "lat": region["lat"], "lon": region["lon"],
        "index": job.cursor + 1, "total": len(job.regions),
        "filters": job.filters, "max_count": job.max_count,
    }


def report_articles(job_id: str, articles: list[dict], passes_filter_fn) -> dict:
    """articles: [{"article_no": "...", "detail": <네이버 /api/articles/{no} 원본 JSON>}, ...]

    필드 추출은 naver_land_scraper.extract_fields()를 그대로 재사용 —
    Playwright 경로와 완전히 동일한 검증된 파싱 로직을 타므로 중복 구현에
    따른 불일치 위험이 없다.
    """
    job = _jobs.get(job_id)
    if not job:
        return {"error": "unknown job"}
    job.last_seen = time.time()

    for item in articles:
        article_no = str(item.get("article_no", ""))
        detail = item.get("detail")
        if not article_no or not detail or not detail.get("articleDetail"):
            continue

        complex_no = str(detail.get("articleDetail", {}).get("hscpNo", "") or "")
        article_url = (
            f"https://new.land.naver.com/complexes/{complex_no}?articleNo={article_no}"
            if complex_no else f"https://new.land.naver.com/articles/{article_no}"
        )

        try:
            fields = extract_fields(detail, article_no, article_url)
        except Exception as e:
            job.log(f"  ⚠ 매물 {article_no} 파싱 오류: {e}", "error")
            continue

        cname = fields.get("complex_name", "")
        if any(kw in cname for kw in ("주상복합", "도시형", "생활주택")):
            job.log(f"  제외: {cname}")
            job.region_counts["filtered"] += 1
            continue

        if is_duplicate(job.ws, article_no, cname, fields.get("floor", "")):
            job.region_counts["skip"] += 1
            continue
        if not passes_filter_fn(fields, job.filters):
            job.region_counts["filtered"] += 1
            continue

        append_row(job.ws, fields, job.ws.max_row + 1)
        job.region_counts["ok"] += 1
        job.region_counts["unsaved"] += 1
        job.log(f"  {cname} — {fields.get('price_main', '')}")
        if job.region_counts["unsaved"] >= 5:
            job.wb.save(job.excel_path)
            job.region_counts["unsaved"] = 0

    return dict(job.region_counts)


def region_done(job_id: str):
    job = _jobs.get(job_id)
    if not job:
        return
    job.last_seen = time.time()
    try:
        job.wb.save(job.excel_path)
    except Exception as e:
        job.log(f"  ✗ 저장 오류: {e}", "error")
    c = job.region_counts
    job.log(f"  저장 {c['ok']}건 / 중복 {c['skip']}건 / 필터 {c['filtered']}건", "info")
    job.total_ok += c["ok"]
    job.total_skip += c["skip"]
    job.total_filtered += c["filtered"]
    job.cursor += 1


def finish(job_id: str, count_rows_fn):
    job = _jobs.pop(job_id, None)
    if not job:
        return
    job.loop.call_soon_threadsafe(job.log_q.put_nowait, {
        "type": "done", "ok": job.total_ok, "skip": job.total_skip,
        "filtered": job.total_filtered, "rows": count_rows_fn(job.excel_path),
    })
