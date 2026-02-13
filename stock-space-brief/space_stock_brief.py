#!/usr/bin/env python3
"""
Space Stock Brief (Codex automation helper)

- Reads watchlist.txt (one per line, # comments allowed).
- Computes:
  - window_end = now (KST)
  - search_start = window_end - 24h
  - new_start = max(last_success_at, search_start)
- Fetches news from a small set of reliable sources (RSS + SEC submissions):
  - Rocket Lab: Rocket Lab Updates RSS + Google News RSS queries
  - Planet Labs: Planet Pulse RSS + Google News RSS queries
  - SpaceX: NASA Breaking News RSS + SpaceNews RSS + Google News RSS queries
  - Space economy: NASA Breaking News RSS + SpaceNews RSS + Google News RSS queries
- Writes:
  - stock_feed.html (self-contained modern light dashboard)
  - .space_stock_agent_state.json (window state)
- Prints Korean Markdown for the Codex Inbox.
  - 인박스에는 외부 기사 URL을 넣지 않고(출처는 이름만), 로컬 리포트 링크만 둔다.
"""

from __future__ import annotations

import json
import re
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.error
import urllib.request
import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Callable, Iterable
from xml.etree import ElementTree as ET

try:
    from zoneinfo import ZoneInfo
except Exception:  # pragma: no cover
    ZoneInfo = None  # type: ignore


ROOT = Path(__file__).resolve().parent
WATCHLIST_PATH = ROOT / "watchlist.txt"
STATE_PATH = ROOT / ".space_stock_agent_state.json"
HTML_PATH = ROOT / "stock_feed.html"
HTML_ERROR_PATH = ROOT / "stock_feed_error.html"
OPEN_SCRIPT = ROOT / "open_stock_feed_in_atlas.sh"

KST = ZoneInfo("Asia/Seoul") if ZoneInfo else timezone(timedelta(hours=9))

AGENT_VERSION = "2026-02-12.5"

USER_AGENT = "space-stock-brief/1.0 (Codex automation; personal use)"

# Codex Automation 세션마다 네트워크 경로가 달라질 수 있어 no-proxy/환경 프록시를 모두 시도한다.
_NO_PROXY_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))
_ENV_PROXY_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler())

# DNS fails intermittently in automation sessions. Keep a small host->IP cache
# from past successful runs and use it with curl --resolve when DNS is down.
_STATIC_HOST_IP_HINTS: dict[str, list[str]] = {
    "rocketlabcorp.com": ["172.67.204.102", "104.21.93.41"],
    "investors.rocketlabcorp.com": ["23.201.35.48"],
    "www.planet.com": ["34.120.196.216"],
    "www.nasa.gov": ["192.0.66.108"],
    "spacenews.com": ["192.0.78.25", "192.0.78.24"],
    "data.sec.gov": ["23.221.159.210"],
    "news.google.com": ["142.251.118.113", "142.251.118.139", "142.251.118.100", "142.251.118.102"],
}


def _is_ipv4(s: str) -> bool:
    return bool(re.fullmatch(r"(?:\d{1,3}\.){3}\d{1,3}", s or ""))


def _load_host_ip_cache_from_state(path: Path) -> dict[str, list[str]]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    out: dict[str, list[str]] = {}
    src = raw.get("host_ip_cache") if isinstance(raw, dict) else None
    if not isinstance(src, dict):
        return {}
    for host, ips in src.items():
        if not isinstance(host, str) or not isinstance(ips, list):
            continue
        keep = [str(x).strip() for x in ips if _is_ipv4(str(x).strip())]
        if keep:
            out[host.strip().lower()] = keep[:6]
    return out


HOST_IP_CACHE: dict[str, list[str]] = _load_host_ip_cache_from_state(STATE_PATH)


def _cache_host_ips(host: str, ips: list[str]) -> None:
    h = (host or "").strip().lower()
    if not h:
        return
    merged = []
    for ip in (HOST_IP_CACHE.get(h) or []) + ips:
        ip = (ip or "").strip()
        if _is_ipv4(ip) and ip not in merged:
            merged.append(ip)
    if merged:
        HOST_IP_CACHE[h] = merged[:6]


def _network_preflight(
    *,
    total_wait_s: int = 120,
    progress: Callable[[int, float, str], None] | None = None,
) -> tuple[bool, str | None]:
    """
    Codex Automation sessions can intermittently lose DNS/network. When that happens,
    every fetch fails and the script wastes time. Preflight with short retries.
    Returns (ok, error_message).
    """

    def one(url: str) -> tuple[bool, str | None]:
        try:
            data = _fetch_bytes(url, timeout=6.0, retries=1, sleep_s=0.2)
            if data:
                return True, None
            return False, "empty response"
        except Exception as e:  # noqa: BLE001
            return False, _brief_exc(e)

    probe_urls = (
        "https://spacenews.com/feed/",
        "https://rocketlabcorp.com/updates/rss/",
        "https://www.nasa.gov/rss/dyn/breaking_news.rss",
    )
    deadline = time.time() + max(0, int(total_wait_s))
    attempt = 0
    probe_idx = 0
    last_err = None
    hard_block_hits = 0
    while True:
        attempt += 1
        # 한 번에 하나의 소스만 순환 점검해 무응답 대기를 줄인다.
        url = probe_urls[probe_idx % len(probe_urls)]
        probe_idx += 1
        ok, err = one(url)
        if ok:
            return True, None
        last_err = err
        em = (err or "").lower()
        if (
            "failed to connect to" in em
            or "network is unreachable" in em
            or "operation timed out" in em
            or "connection timed out" in em
        ):
            hard_block_hits += 1
        # If multiple direct-IP connection attempts fail quickly, this run likely
        # has no outbound egress. Stop early instead of stalling for minutes.
        if hard_block_hits >= 3 and attempt >= 4:
            return False, f"EGRESS_BLOCKED: {err or 'outbound connectivity unavailable'}"

        if time.time() >= deadline:
            return False, (last_err or "unknown error")

        # Exponential-ish backoff (2, 4, 8, ...), capped.
        sleep_s = min(12, 2 * attempt)
        if time.time() + sleep_s > deadline:
            sleep_s = max(0.0, deadline - time.time())
        if sleep_s <= 0:
            return False, (last_err or "unknown error")
        if progress is not None:
            try:
                progress(attempt, max(0.0, deadline - time.time()), last_err or "")
            except Exception:
                pass
        time.sleep(sleep_s)


@dataclass(frozen=True)
class NewsItem:
    title: str
    url: str
    published_at: datetime
    source_name: str
    source_url: str | None = None
    guid: str | None = None


@dataclass(frozen=True)
class FilingItem:
    form: str
    accession: str
    accepted_at: datetime | None
    filing_date: str | None
    primary_doc: str | None
    url: str | None


def _parse_iso_datetime(value: str) -> datetime:
    v = (value or "").strip()
    if not v:
        raise ValueError("empty datetime")
    if v.endswith("Z"):
        v = v[:-1] + "+00:00"
    dt = datetime.fromisoformat(v)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=KST)
    return dt


def _fmt_kst(dt: datetime) -> str:
    return dt.astimezone(KST).strftime("%Y-%m-%d %H:%M KST")


def _read_watchlist(path: Path) -> list[str]:
    if not path.exists():
        return []
    out: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        out.append(s)
    return out


def _load_state(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _save_state(path: Path, state: dict) -> None:
    path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _warm_host_ip_cache() -> None:
    hosts = [
        "rocketlabcorp.com",
        "investors.rocketlabcorp.com",
        "www.planet.com",
        "www.nasa.gov",
        "spacenews.com",
        "data.sec.gov",
        "news.google.com",
    ]
    for host in hosts:
        try:
            infos = socket.getaddrinfo(host, None, socket.AF_INET, socket.SOCK_STREAM)
        except Exception:
            continue
        ips: list[str] = []
        for info in infos:
            try:
                ip = str(info[4][0]).strip()
            except Exception:
                continue
            if _is_ipv4(ip) and ip not in ips:
                ips.append(ip)
        if ips:
            _cache_host_ips(host, ips)


def _fetch_bytes(url: str, *, timeout: float = 30.0, retries: int = 3, sleep_s: float = 0.8) -> bytes:
    errors: list[str] = []

    def add_err(label: str, e: Exception) -> None:
        msg = str(e).strip().replace("\n", " ")
        if msg:
            errors.append(f"{label}: {type(e).__name__}: {msg[:170]}")
        else:
            errors.append(f"{label}: {type(e).__name__}")

    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})

    def urllib_try(opener: urllib.request.OpenerDirector, *, label: str, attempts: int) -> bytes | None:
        for attempt in range(1, max(1, attempts) + 1):
            try:
                with opener.open(req, timeout=timeout) as resp:
                    return resp.read()
            except Exception as e:  # noqa: BLE001 - robustness for automations
                add_err(label, e)
                time.sleep(sleep_s * attempt)
        return None

    data = urllib_try(_NO_PROXY_OPENER, label="urllib_no_proxy", attempts=retries)
    if data:
        return data

    has_proxy_env = any(
        os.environ.get(k)
        for k in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy")
    )
    if has_proxy_env:
        data = urllib_try(_ENV_PROXY_OPENER, label="urllib_env_proxy", attempts=max(1, min(retries, 2)))
        if data:
            return data

    max_time = str(int(max(5.0, float(timeout))))

    def curl_try(extra: list[str] | None = None, *, label: str = "direct", no_proxy: bool = True) -> bytes | None:
        cmd = [
            "/usr/bin/curl",
            "-fsSL",
            "--compressed",
            "--connect-timeout",
            "10",
            "--retry",
            "1",
            "--retry-delay",
            "1",
            "--retry-all-errors",
            "--max-time",
            max_time,
            "-A",
            USER_AGENT,
        ]
        if no_proxy:
            cmd.extend(["--noproxy", "*", "--proxy", ""])
        if extra:
            cmd.extend(extra)
        cmd.append(url)
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if proc.returncode != 0:
            stderr = (proc.stderr or proc.stdout or b"").decode("utf-8", errors="replace").strip().replace("\n", " ")
            if not stderr:
                stderr = "no stderr"
            add_err(f"curl_{label}", RuntimeError(f"rc={proc.returncode}: {stderr[:170]}"))
            return None
        return proc.stdout

    # Fallback 1: direct curl.
    data = curl_try(label="direct", no_proxy=True)
    if data:
        return data

    # Fallback 2: bypass broken system DNS with DNS-over-HTTPS (Cloudflare over IP).
    data = curl_try(["--doh-url", "https://1.1.1.1/dns-query"], label="doh_cf", no_proxy=True)
    if data:
        return data

    # Fallback 3: alternate DoH endpoint.
    data = curl_try(["--doh-url", "https://8.8.8.8/dns-query"], label="doh_google", no_proxy=True)
    if data:
        return data

    # Fallback 4: resolve via HTTPS DoH endpoint pinned to IP, then fetch with --resolve.
    def resolve_host_with_doh(host: str) -> list[str]:
        ips: list[str] = []
        providers = [
            ("doh_cf_json", "cloudflare-dns.com", "1.1.1.1"),
            ("doh_google_json", "dns.google", "8.8.8.8"),
        ]
        for label, doh_host, doh_ip in providers:
            qurl = "https://" + doh_host + "/resolve?" + urllib.parse.urlencode({"name": host, "type": "A"})
            cmd = [
                "/usr/bin/curl",
                "-fsS",
                "--connect-timeout",
                "6",
                "--max-time",
                "10",
                "--noproxy",
                "*",
                "--proxy",
                "",
                "--resolve",
                f"{doh_host}:443:{doh_ip}",
                "-H",
                "accept: application/dns-json",
                qurl,
            ]
            proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
            if proc.returncode != 0:
                stderr = (proc.stderr or b"").decode("utf-8", errors="replace").strip().replace("\n", " ")
                add_err(label, RuntimeError(f"rc={proc.returncode}: {(stderr or 'no stderr')[:140]}"))
                continue
            try:
                payload = json.loads((proc.stdout or b"{}").decode("utf-8", errors="replace"))
            except Exception as e:  # noqa: BLE001
                add_err(label, e)
                continue
            answers = payload.get("Answer") or []
            for a in answers:
                ip = str((a or {}).get("data") or "").strip()
                if re.fullmatch(r"(?:\d{1,3}\.){3}\d{1,3}", ip):
                    ips.append(ip)
            if ips:
                _cache_host_ips(host, ips)
                break
        return ips[:3]

    # Fallback 5: explicit DNS lookup via dig + --resolve to bypass libc resolver.
    def resolve_host_with_dig(host: str) -> list[str]:
        ips: list[str] = []
        for ns in ("1.1.1.1", "8.8.8.8"):
            try:
                proc = subprocess.run(
                    ["/usr/bin/dig", "+short", "A", host, f"@{ns}"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=False,
                    timeout=5,
                )
            except Exception as e:  # noqa: BLE001
                add_err(f"dig_{ns}", e if isinstance(e, Exception) else RuntimeError(str(e)))
                continue
            text = (proc.stdout or b"").decode("utf-8", errors="replace")
            for line in text.splitlines():
                s = line.strip()
                if re.fullmatch(r"(?:\d{1,3}\.){3}\d{1,3}", s):
                    ips.append(s)
            if ips:
                _cache_host_ips(host, ips)
                break
            if proc.returncode != 0:
                err = (proc.stderr or b"").decode("utf-8", errors="replace").strip().replace("\n", " ")
                add_err(f"dig_{ns}", RuntimeError(f"rc={proc.returncode}: {err[:120] or 'no stderr'}"))
        return ips[:3]

    parts = urllib.parse.urlsplit(url)
    host = parts.hostname or ""
    port = 443 if parts.scheme.lower() == "https" else 80
    if host:
        # First: try cached/static host IPs (no DNS dependency).
        hinted_ips: list[str] = []
        for ip in (HOST_IP_CACHE.get(host.lower()) or []) + (_STATIC_HOST_IP_HINTS.get(host.lower()) or []):
            ip = (ip or "").strip()
            if _is_ipv4(ip) and ip not in hinted_ips:
                hinted_ips.append(ip)
        for ip in hinted_ips[:4]:
            data = curl_try(["--resolve", f"{host}:{port}:{ip}"], label=f"hint_resolve_{ip}", no_proxy=True)
            if data:
                _cache_host_ips(host, [ip])
                return data

        for ip in resolve_host_with_doh(host):
            data = curl_try(["--resolve", f"{host}:{port}:{ip}"], label=f"doh_resolve_{ip}", no_proxy=True)
            if data:
                _cache_host_ips(host, [ip])
                return data
        for ip in resolve_host_with_dig(host):
            data = curl_try(["--resolve", f"{host}:{port}:{ip}"], label=f"resolve_{ip}", no_proxy=True)
            if data:
                _cache_host_ips(host, [ip])
                return data

    # Some automation sessions need an egress proxy; try one pass honoring env proxy.
    if has_proxy_env:
        data = curl_try(label="env_proxy", no_proxy=False)
        if data:
            return data

    if not errors:
        raise RuntimeError("fetch failed: unknown error")
    raise RuntimeError(" | ".join(errors[-6:]))


def _parse_rss_items(xml_bytes: bytes, *, default_source_name: str, default_source_url: str | None, google_news: bool) -> list[NewsItem]:
    root = ET.fromstring(xml_bytes)
    items = root.findall(".//item")
    out: list[NewsItem] = []
    for it in items:
        title = (it.findtext("title") or "").strip()
        url = (it.findtext("link") or "").strip()
        guid = (it.findtext("guid") or "").strip() or url
        pub = (it.findtext("pubDate") or "").strip()
        if not title or not pub:
            continue

        try:
            dt = parsedate_to_datetime(pub)
        except Exception:
            continue
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)

        source_name = default_source_name
        source_url = default_source_url
        if google_news:
            src = it.find("source")
            if src is not None and (src.text or "").strip():
                source_name = src.text.strip()
                source_url = src.attrib.get("url") or source_url

        out.append(
            NewsItem(
                title=title,
                url=url,
                published_at=dt,
                source_name=source_name,
                source_url=source_url,
                guid=guid,
            )
        )
    return out


def _google_news_rss(
    query: str,
    *,
    locale: str,
    timeout: float = 30.0,
    retries: int = 3,
    sleep_s: float = 0.6,
) -> list[NewsItem]:
    if locale == "ko":
        hl, gl, ceid = "ko", "KR", "KR:ko"
    else:
        hl, gl, ceid = "en-US", "US", "US:en"

    url = "https://news.google.com/rss/search?" + urllib.parse.urlencode(
        {"q": query, "hl": hl, "gl": gl, "ceid": ceid}
    )
    data = _fetch_bytes(url, timeout=timeout, retries=retries, sleep_s=sleep_s)
    return _parse_rss_items(data, default_source_name="Google News", default_source_url="https://news.google.com/", google_news=True)


def _sec_submissions_json(cik: str, *, timeout: float = 30.0, retries: int = 2) -> dict | None:
    # SEC fair access requires a descriptive UA; keep it stable and low-volume.
    url = f"https://data.sec.gov/submissions/CIK{cik.zfill(10)}.json"
    raw = _fetch_bytes(url, timeout=timeout, retries=retries, sleep_s=0.5)
    return json.loads(raw.decode("utf-8"))


def _brief_exc(e: Exception, *, limit: int = 520) -> str:
    msg = str(e).strip().replace("\n", " ")
    if msg:
        msg = msg[:limit]
        return f"{type(e).__name__}: {msg}"
    return type(e).__name__


def _sec_recent_filings(
    cik: str,
    *,
    start: datetime,
    end: datetime,
    timeout: float = 30.0,
    retries: int = 2,
) -> tuple[list[FilingItem], bool, str | None]:
    try:
        data = _sec_submissions_json(cik, timeout=timeout, retries=retries)
    except urllib.error.HTTPError as e:
        return [], False, f"HTTP {e.code}"
    except Exception as e:  # noqa: BLE001 - robustness
        return [], False, _brief_exc(e)

    if not data:
        return [], False, "empty"
    recent = (data.get("filings") or {}).get("recent") or {}
    forms: list[str] = recent.get("form") or []
    acceptance: list[str] = recent.get("acceptanceDateTime") or []
    filing_dates: list[str] = recent.get("filingDate") or []
    accessions: list[str] = recent.get("accessionNumber") or []
    primary_docs: list[str] = recent.get("primaryDocument") or []

    out: list[FilingItem] = []
    start_utc = start.astimezone(timezone.utc)
    end_utc = end.astimezone(timezone.utc)

    for i in range(min(len(forms), len(accessions))):
        form = forms[i] or ""
        acc = accessions[i] or ""
        acc_nodash = acc.replace("-", "")
        accepted_at: datetime | None = None
        if i < len(acceptance) and acceptance[i]:
            try:
                accepted_at = _parse_iso_datetime(acceptance[i])
            except Exception:
                accepted_at = None

        in_range = False
        if accepted_at is not None:
            a_utc = accepted_at.astimezone(timezone.utc)
            in_range = start_utc <= a_utc <= end_utc
        else:
            if i < len(filing_dates) and filing_dates[i]:
                try:
                    fd = datetime.fromisoformat(filing_dates[i]).replace(tzinfo=timezone.utc)
                    in_range = start_utc.date() <= fd.date() <= end_utc.date()
                except Exception:
                    in_range = False

        if not in_range:
            continue

        primary = primary_docs[i] if i < len(primary_docs) else None
        url = None
        if acc_nodash and primary:
            try:
                url = f"https://www.sec.gov/Archives/edgar/data/{int(cik)}/{acc_nodash}/{primary}"
            except Exception:
                url = None

        out.append(
            FilingItem(
                form=form,
                accession=acc,
                accepted_at=accepted_at,
                filing_date=filing_dates[i] if i < len(filing_dates) else None,
                primary_doc=primary,
                url=url,
            )
        )
    return out, True, None


def _classify_big_issue(title: str) -> str | None:
    t = title.lower()

    # Priority-ish keyword buckets.
    if re.search(r"\b(acquire|acquisition|merger)\b|인수|합병", t):
        return "M&A"
    if re.search(r"\b(funding|financing|offering|raise|debt|investment)\b|자금조달|투자\s*유치|유상증자|발행", t):
        return "자금조달"
    if re.search(r"\b(earnings|results|guidance|forecast|revenue|eps)\b|실적|가이던스|전망", t):
        return "실적/가이던스"
    if re.search(r"\b(contract|award|deal|partnership|agreement|customer)\b|계약|수주|파트너십|협약|고객", t):
        return "계약/파트너십"
    # Avoid overly broad tokens like "rocket/로켓" which can match company names (e.g., Rocket Lab).
    if re.search(
        r"\b(launch|mission|anomaly|failure|investigation|delay|scrub|static\s*fire|engine|test\s*flight|orbit|payload|reentry|landing|starship|falcon|dragon|starlink|electron|neutron|pelican|tanager|skysat|dove)\b|발사|임무|지연|사고|조사|엔진|시험",
        t,
    ):
        return "발사/운영"
    if re.search(r"\b(faa|fcc|sec|lawsuit|regulatory|license|approval|fine)\b|규제|허가|승인|소송|벌금", t):
        return "규제/법무"
    if re.search(r"\b(ceo|cfo|resign|appointed|board)\b|경영진|사임|선임", t):
        return "경영진"
    return None


def _why_it_matters(category: str | None) -> str:
    if category == "실적/가이던스":
        return "실적/가이던스 변화는 단기 밸류에이션 재평가와 변동성 확대의 직접 요인입니다."
    if category == "자금조달":
        return "자금조달은 현금런웨이, 희석, 재무구조에 영향을 주며 단기 주가 반응이 클 수 있습니다."
    if category == "M&A":
        return "인수합병은 사업구조 변화와 시너지 기대를 만들지만 통합 리스크도 동반합니다."
    if category == "계약/파트너십":
        return "대형 계약/수주는 매출 가시성과 백로그에 직접 영향을 주는 핵심 촉매입니다."
    if category == "발사/운영":
        return "발사/운영 이슈는 신뢰도와 일정, 향후 수주 가능성에 직접 연결됩니다."
    if category == "규제/법무":
        return "규제/법무 이슈는 일정 지연·비용 증가·사업 제한 리스크로 이어질 수 있습니다."
    if category == "경영진":
        return "경영진 변화는 전략/집행의 연속성에 영향을 줄 수 있어 단기 불확실성이 커질 수 있습니다."
    return "새 정보는 단기 촉매로 작동할 수 있으므로 후속 공지와 파급을 점검할 필요가 있습니다."


def _dedupe(items: Iterable[NewsItem]) -> list[NewsItem]:
    seen: set[str] = set()
    out: list[NewsItem] = []
    for it in sorted(items, key=lambda x: x.published_at, reverse=True):
        key = (it.guid or it.url or it.title).strip()
        if not key or key in seen:
            continue
        seen.add(key)
        out.append(it)
    return out


def _filter_window(items: Iterable[NewsItem], *, start: datetime, end: datetime) -> list[NewsItem]:
    out: list[NewsItem] = []
    start_utc = start.astimezone(timezone.utc)
    end_utc = end.astimezone(timezone.utc)
    for it in items:
        dt = it.published_at.astimezone(timezone.utc)
        if start_utc <= dt <= end_utc:
            out.append(it)
    return _dedupe(out)


_LOW_SIGNAL_TITLE_RE = re.compile(
    r"(?i)("
    r"\b(stock price|shares?|stake|price target|analyst|upgrade|downgrade|rating|"
    r"dividend|options|short interest|institutional|common retirement fund|"
    r"purchases? \d|boosted by|here'?s what happened|what happened)\b"
    r"|주가|목표\\s*주가|목표가|투자의견|애널리스트|상승\\s*마감|하락\\s*마감|급등|급락|상승|하락|마감"
    r")"
)


def _title_penalty(title: str) -> int:
    # Penalize headlines that are usually investor/noise rather than company activity.
    if _LOW_SIGNAL_TITLE_RE.search(title or ""):
        return 6
    return 0


def _title_mentions(title: str, terms_en: list[str], terms_kr: list[str]) -> bool:
    """
    Basic relevance filter: keep items whose *title* mentions one of the known aliases.
    (Google News can match by article text; title-based filtering is more conservative.)
    """
    t = (title or "").strip().lower()
    if not t:
        return False

    for term in (terms_en or []):
        term = (term or "").strip()
        if not term:
            continue
        if term.isupper() and len(term) <= 6:
            if re.search(rf"\b{re.escape(term.lower())}\b", t):
                return True
        else:
            if term.lower() in t:
                return True

    for term in (terms_kr or []):
        term = (term or "").strip()
        if not term:
            continue
        if term.lower() in t:
            return True

    return False


def _source_score(source_name: str) -> int:
    n = (source_name or "").strip().lower()
    if not n:
        return 0

    # Prefer primary/sector sources.
    if n in {"rocket lab updates", "rocket lab ir", "planet pulse", "nasa breaking news"}:
        return 6
    if n in {"spacenews"}:
        return 5
    if "space.com" in n:
        return 3
    if "arstechnica" in n or "ars technica" in n:
        return 3

    # Major wires / press release distributors.
    if "reuters" in n or n == "ap" or "associated press" in n:
        return 4
    if "business wire" in n or "pr newswire" in n:
        return 3
    if "wall street journal" in n or n == "wsj":
        return 3
    if "bloomberg" in n:
        return 4
    if "financial times" in n or n == "ft":
        return 3

    # Common low-signal finance blogs/aggregators (penalize but don't exclude).
    if "marketbeat" in n or "motley fool" in n or "seeking alpha" in n or "benzinga" in n:
        return -4
    if "tipranks" in n or "investorplace" in n or "stocktitan" in n:
        return -4
    if "finviz" in n:
        return -4
    if "topstarnews" in n or "톱스타뉴스" in n or "ad hoc news" in n:
        return -3

    return 0


def _evidence_sample(items: list[NewsItem], *, n: int = 3) -> str:
    if not items:
        return ""

    def rank_key(it: NewsItem) -> tuple[int, datetime]:
        # Prefer better sources and non-noise headlines, then recency.
        score = _source_score(it.source_name) * 10 - _title_penalty(it.title) * 20
        return score, it.published_at

    # If we have any non-noise + non-junk items, prefer sampling from them.
    clean = [it for it in items if _title_penalty(it.title) == 0]
    good = [it for it in clean if _source_score(it.source_name) >= 0]
    ranked = sorted((good or clean or items), key=rank_key, reverse=True)
    picked = ranked[:n]
    return " / ".join([f"{_fmt_kst(it.published_at)} {it.title} ({it.source_name})" for it in picked])


def _preview_items(items_new: list[NewsItem], items_search: list[NewsItem], *, limit: int = 6) -> list[dict]:
    combined = list(items_new) + list(items_search)
    combined = _dedupe(combined)

    def rank_key(it: NewsItem) -> tuple[int, datetime]:
        score = _source_score(it.source_name) * 10 - _title_penalty(it.title) * 20
        return score, it.published_at

    # Prefer higher-quality, non-noise items when available.
    clean = [it for it in combined if _title_penalty(it.title) == 0]
    good = [it for it in clean if _source_score(it.source_name) >= 0]
    ranked = sorted((good or clean or combined), key=rank_key, reverse=True)
    out: list[dict] = []
    for it in ranked[:limit]:
        if not it.title or not it.url:
            continue
        out.append(
            {
                "title": it.title,
                "url": it.url,
                "source": it.source_name,
                "published": _fmt_kst(it.published_at),
            }
        )
    return out


def _pick_top_issue(items: list[NewsItem]) -> tuple[NewsItem | None, str | None]:
    scored: list[tuple[int, datetime, NewsItem, str]] = []
    for it in items:
        # Big-issue selection should be conservative: avoid triggering on low-quality
        # aggregators or unrelated coverage.
        if _source_score(it.source_name) < 3:
            continue
        cat = _classify_big_issue(it.title)
        if not cat:
            continue
        base = {
            "M&A": 6,
            "자금조달": 5,
            "실적/가이던스": 5,
            "계약/파트너십": 4,
            "규제/법무": 4,
            "발사/운영": 3,
            "경영진": 3,
        }.get(cat, 1)
        score = base * 100
        score += _source_score(it.source_name) * 10
        score -= _title_penalty(it.title) * 20
        scored.append((score, it.published_at, it, cat))
    if not scored:
        return None, None
    scored.sort(key=lambda x: (x[0], x[1]), reverse=True)
    top_score, _dt, top_item, top_cat = scored[0]

    # If the best candidate is still low-signal, treat it as "no big issue".
    if top_score < 250:
        return None, None
    return top_item, top_cat


def _render_html(sections: list[dict], *, generated_at: datetime, new_start: datetime, search_start: datetime, window_end: datetime, watchlist_count: int) -> str:
    # Simple self-contained dashboard. Keep it white/light and readable.
    def esc(s: str) -> str:
        return (
            s.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
        )

    cards_html: list[str] = []
    for sec in sections:
        sources = sec.get("sources_html") or []
        sources_html = "".join(
            f'<a href="{esc(src[1])}">{esc(src[0])}</a>' for src in sources if src and src[0] and src[1]
        )
        new_cnt = int(sec.get("new_count") or 0)
        search_cnt = int(sec.get("search_count") or 0)
        news_items = sec.get("items") or []
        if news_items:
            li_html = "".join(
                f'<li><a href="{esc(it.get("url",""))}">{esc(it.get("title",""))}</a><div class="sub">{esc(it.get("source",""))} · {esc(it.get("published",""))}</div></li>'
                for it in news_items
                if it.get("title") and it.get("url")
            )
            details_html = f"""
        <details class="details">
          <summary>확인 기사 (신규 {new_cnt} / 24시간 {search_cnt})</summary>
          <ol class="newslist">{li_html}</ol>
        </details>
""".rstrip()
        else:
            details_html = f'<div class="details-empty">확인 기사 (신규 {new_cnt} / 24시간 {search_cnt}): 0건</div>'
        cards_html.append(
            f"""\n      <article class="card">\n        <h2>{esc(sec['title'])}</h2>\n        <div class="meta">{esc(sec['meta'])}</div>\n        <div class="item"><strong>무슨 일:</strong> {esc(sec['what'])}</div>\n        <div class="item"><strong>왜 중요한지:</strong> {esc(sec['why'])}</div>\n        <div class="item"><strong>날짜:</strong> {esc(sec['date'])}</div>\n        <div class="sources"><span>대표 출처:</span>{sources_html}</div>\n        {details_html}\n      </article>\n""".rstrip()
        )

    return f"""<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Stock + Space Brief</title>
  <style>
    :root {{
      --bg: #f6f7fb;
      --bg-grad: radial-gradient(1200px 600px at 10% -10%, #eef2ff 0%, rgba(238,242,255,0) 60%),
                 radial-gradient(900px 500px at 90% -20%, #e8f5ff 0%, rgba(232,245,255,0) 55%);
      --card: #ffffff;
      --text: #0f172a;
      --muted: #64748b;
      --border: rgba(15, 23, 42, 0.08);
      --shadow: 0 10px 30px rgba(15, 23, 42, 0.08);
      --link: #2563eb;
      --chip: rgba(15, 23, 42, 0.06);
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: ui-sans-serif, system-ui, -apple-system, \"Apple SD Gothic Neo\", \"Noto Sans KR\", sans-serif;
      color: var(--text);
      background: var(--bg);
      background-image: var(--bg-grad);
    }}
    .container {{
      max-width: 1100px;
      margin: 0 auto;
      padding: 24px 20px 80px;
    }}
    header {{
      position: sticky;
      top: 0;
      z-index: 20;
      backdrop-filter: blur(12px);
      background: rgba(255, 255, 255, 0.75);
      border-bottom: 1px solid var(--border);
    }}
    .header-inner {{
      max-width: 1100px;
      margin: 0 auto;
      padding: 16px 20px 18px;
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      align-items: center;
      justify-content: space-between;
    }}
    h1 {{
      font-size: 20px;
      margin: 0;
      letter-spacing: -0.2px;
    }}
    .chips {{ display: flex; flex-wrap: wrap; gap: 8px; }}
    .chip {{
      padding: 6px 12px;
      border-radius: 999px;
      background: var(--chip);
      font-size: 12px;
      color: var(--muted);
    }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 16px;
      margin-top: 18px;
    }}
    .card {{
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 18px 18px 16px;
      box-shadow: var(--shadow);
    }}
    .card h2 {{
      margin: 0 0 10px;
      font-size: 16px;
    }}
    .meta {{
      font-size: 12px;
      color: var(--muted);
      margin-bottom: 8px;
    }}
    .item {{
      margin: 8px 0;
      line-height: 1.55;
      font-size: 14px;
    }}
	    .sources {{
	      margin-top: 8px;
	      display: flex;
	      flex-wrap: wrap;
	      gap: 10px;
	      font-size: 12px;
	      color: var(--muted);
	      align-items: center;
	    }}
	    .sources span {{ margin-right: 2px; }}
	    .details, .details-empty {{
	      margin-top: 12px;
	      padding-top: 10px;
	      border-top: 1px dashed rgba(15, 23, 42, 0.12);
	      color: var(--muted);
	      font-size: 12px;
	    }}
	    details.details > summary {{
	      cursor: pointer;
	      list-style: none;
	    }}
	    details.details > summary::-webkit-details-marker {{ display: none; }}
	    .newslist {{
	      margin: 10px 0 0;
	      padding-left: 18px;
	      color: var(--text);
	      font-size: 13px;
	    }}
	    .newslist li {{ margin: 10px 0; }}
	    .newslist .sub {{
	      margin-top: 3px;
	      color: var(--muted);
	      font-size: 12px;
	    }}
	    a {{ color: var(--link); text-decoration: none; }}
	    a:hover {{ text-decoration: underline; }}
    @media (max-width: 860px) {{
      .grid {{ grid-template-columns: 1fr; }}
      .header-inner {{ gap: 10px; }}
    }}
  </style>
</head>
<body>
  <header>
    <div class=\"header-inner\">
      <h1>Stock + Space Brief</h1>
      <div class=\"chips\">
        <div class=\"chip\">생성 시각: {esc(_fmt_kst(generated_at))}</div>
        <div class=\"chip\">신규 윈도우: {esc(_fmt_kst(new_start))} ~ {esc(_fmt_kst(window_end))}</div>
        <div class=\"chip\">검색 윈도우: {esc(_fmt_kst(search_start))} ~ {esc(_fmt_kst(window_end))}</div>
        <div class=\"chip\">워치리스트: {watchlist_count}</div>
      </div>
    </div>
  </header>
  <main class=\"container\">
    <section class=\"grid\">
{''.join(cards_html)}
    </section>
  </main>
</body>
</html>
"""


def main() -> int:
    # Emit an immediate stdout line so automation runners don't treat the task as stalled.
    sys.stdout.write(f"<!-- run-start {datetime.now(KST).isoformat()} -->\n")
    sys.stdout.flush()

    # 0) Preflight network (Codex Automation sessions can intermittently block DNS/network).
    preflight_wait_raw = os.environ.get("BRIEF_PREFLIGHT_WAIT_S", "120")
    try:
        preflight_wait = int(preflight_wait_raw)
    except Exception:
        preflight_wait = 120
    # Guardrail: avoid very long hangs in automation runs.
    preflight_wait = max(20, min(300, preflight_wait))

    def preflight_progress(attempt: int, remain_s: float, last_err: str) -> None:
        # Keep stdout alive while waiting for transient network recovery.
        msg = last_err[:120].replace("\n", " ") if last_err else "retrying"
        sys.stdout.write(f"<!-- preflight attempt={attempt} remain={int(remain_s)} err={msg} -->\n")
        sys.stdout.flush()

    preflight_ok, preflight_err = _network_preflight(total_wait_s=preflight_wait, progress=preflight_progress)
    hard_blocked = bool(preflight_err and str(preflight_err).startswith("EGRESS_BLOCKED:"))
    if not preflight_ok:
        # One shorter second chance helps when DNS is late, but skip if egress is clearly blocked.
        if not hard_blocked:
            second_wait = int(os.environ.get("BRIEF_PREFLIGHT_RETRY_S", "90"))
            second_wait = max(20, min(180, second_wait))
            sys.stdout.write(f"<!-- preflight second-chance wait={second_wait}s -->\n")
            sys.stdout.flush()
            preflight_ok2, preflight_err2 = _network_preflight(total_wait_s=second_wait, progress=preflight_progress)
            if preflight_ok2:
                preflight_ok, preflight_err = True, None
            elif preflight_err2:
                preflight_err = preflight_err2
                hard_blocked = bool(str(preflight_err2).startswith("EGRESS_BLOCKED:"))
    network_suspect = not preflight_ok
    if not network_suspect:
        _warm_host_ip_cache()

    # 1) Windows
    generated_at = datetime.now(KST)
    window_end = generated_at
    search_start = window_end - timedelta(hours=24)

    state = _load_state(STATE_PATH)
    last_success_at = None
    if isinstance(state, dict) and state.get("last_success_at"):
        try:
            last_success_at = _parse_iso_datetime(str(state["last_success_at"]))
        except Exception:
            last_success_at = None

    new_start = max(last_success_at, search_start) if last_success_at else search_start

    # 2) Watchlist
    raw_watch = _read_watchlist(WATCHLIST_PATH)
    watchlist_count = len(raw_watch)

    # If no tickers: space economy only.
    if watchlist_count == 0:
        raw_watch = []

    # Known mapping to improve query quality and avoid ambiguous tickers.
    def _watch_profile(line: str) -> tuple[str, list[str], list[str]]:
        key = line.strip()
        up = key.upper()
        if up == "RKLB" or up == "ROCKET LAB":
            return "Rocket Lab (RKLB)", ["Rocket Lab", "Rocket Lab USA", "RKLB"], ["로켓랩", "로켓 랩"]
        if up == "PL" or up == "PLANET LABS":
            return "Planet Labs (PL)", ["Planet Labs", "Planet Labs PBC"], ["플래닛랩스", "플래닛 랩스"]
        if up == "SPACEX" or up == "SPACE X":
            return "SpaceX", ["SpaceX"], ["스페이스X", "스페이스엑스"]
        # Fallback: treat as keyword
        return key, [key], [key]

    # 3) Fetch shared RSS feeds (1x each).
    fetch_error_counts: dict[str, int] = {}
    def record_error(msg: str) -> None:
        m = (msg or "").strip()
        if not m:
            return
        if len(m) > 260:
            m = m[:260].rstrip() + " ..."
        fetch_error_counts[m] = fetch_error_counts.get(m, 0) + 1

    if network_suspect:
        record_error(f"네트워크 프리플라이트 실패: {preflight_err or 'unknown error'}")
        if hard_blocked:
            record_error("네트워크 분류: EGRESS_BLOCKED (이번 실행 세션에서 외부 443 연결 불가)")

    def safe_rss(url: str, source_name: str) -> tuple[list[NewsItem], bool]:
        if hard_blocked:
            return [], False
        try:
            data = _fetch_bytes(
                url,
                timeout=(12.0 if network_suspect else 35.0),
                retries=(1 if network_suspect else 3),
                sleep_s=0.8,
            )
            return (
                _parse_rss_items(data, default_source_name=source_name, default_source_url=url, google_news=False),
                True,
            )
        except urllib.error.HTTPError as e:
            record_error(f"{source_name} RSS 실패: HTTP {e.code}")
            return [], False
        except Exception as e:  # noqa: BLE001 - robustness
            record_error(f"{source_name} RSS 실패: {_brief_exc(e)}")
            return [], False

    rocketlab_updates_rss, rocketlab_updates_ok = safe_rss("https://rocketlabcorp.com/updates/rss/", "Rocket Lab Updates")
    rocketlab_ir_rss, rocketlab_ir_ok = safe_rss("https://investors.rocketlabcorp.com/rss/news-releases.xml", "Rocket Lab IR")
    planet_rss, planet_rss_ok = safe_rss("https://www.planet.com/pulse/rss/", "Planet Pulse")
    nasa_rss, nasa_ok = safe_rss("https://www.nasa.gov/rss/dyn/breaking_news.rss", "NASA Breaking News")
    spacenews_rss, spacenews_ok = safe_rss("https://spacenews.com/feed/", "SpaceNews")

    # 4) SEC filings (Rocket Lab, Planet Labs)
    if hard_blocked:
        sec_rocket, sec_rocket_ok, sec_rocket_err = [], False, "EGRESS_BLOCKED"
        sec_planet, sec_planet_ok, sec_planet_err = [], False, "EGRESS_BLOCKED"
    else:
        sec_timeout = 8.0 if network_suspect else 30.0
        sec_retries = 1 if network_suspect else 2
        sec_rocket, sec_rocket_ok, sec_rocket_err = _sec_recent_filings(
            "1819994",
            start=search_start,
            end=window_end,
            timeout=sec_timeout,
            retries=sec_retries,
        )
        if not sec_rocket_ok and sec_rocket_err:
            record_error(f"Rocket Lab SEC 조회 실패: {sec_rocket_err}")
        time.sleep(0.25)
        sec_planet, sec_planet_ok, sec_planet_err = _sec_recent_filings(
            "1836833",
            start=search_start,
            end=window_end,
            timeout=sec_timeout,
            retries=sec_retries,
        )
        if not sec_planet_ok and sec_planet_err:
            record_error(f"Planet Labs SEC 조회 실패: {sec_planet_err}")

    # 5) Build sections
    sections: list[dict] = []

    def add_section(
        title: str,
        meta: str,
        what: str,
        why: str,
        date: str,
        sources_html: list[tuple[str, str]],
        *,
        new_count: int = 0,
        search_count: int = 0,
        items: list[dict] | None = None,
    ) -> None:
        sections.append(
            {
                "title": title,
                "meta": meta,
                "what": what,
                "why": why,
                "date": date,
                "sources_html": sources_html,
                "new_count": int(new_count),
                "search_count": int(search_count),
                "items": items or [],
            }
        )

    # Helper: throttled Google News queries.
    def google_queries(base_en: str, base_kr: str) -> list[tuple[str, str]]:
        # Keep queries modest to reduce rate-limiting, but still cover "company activity".
        en = [
            f"\"{base_en}\"",
            f"\"{base_en}\" (earnings OR results OR guidance OR funding OR financing OR offering OR contract OR award OR partnership OR agreement OR launch OR mission OR delay OR anomaly OR investigation OR regulatory OR FAA OR FCC OR SEC OR lawsuit OR acquisition OR merger OR CEO OR CFO)",
        ]
        kr = [
            f"{base_kr}",
            f"{base_kr} (실적 OR 가이던스 OR 투자 OR 자금조달 OR 계약 OR 수주 OR 파트너십 OR 발사 OR 임무 OR 지연 OR 사고 OR 조사 OR 규제 OR 소송 OR 인수 OR 합병 OR 경영진)",
        ]
        return [(q, "en") for q in en] + [(q, "ko") for q in kr]

    def fetch_google_bundle(base_en: str, base_kr: str) -> tuple[list[NewsItem], bool]:
        if hard_blocked:
            return [], False
        items: list[NewsItem] = []
        ok = False
        all_queries = google_queries(base_en, base_kr)
        if network_suspect:
            all_queries = all_queries[:2]
        for q, loc in all_queries:
            try:
                items.extend(
                    _google_news_rss(
                        q,
                        locale=loc,
                        timeout=(10.0 if network_suspect else 30.0),
                        retries=(1 if network_suspect else 3),
                        sleep_s=0.4,
                    )
                )
                ok = True
            except urllib.error.HTTPError as e:
                record_error(f"Google News({loc}) 실패: HTTP {e.code}")
            except Exception as e:  # noqa: BLE001
                record_error(f"Google News({loc}) 실패: {_brief_exc(e)}")
            time.sleep(0.35)
        return items, ok

    # Per-watchlist sections (skip if no tickers).
    for raw in raw_watch:
        title, terms_en, terms_kr = _watch_profile(raw)
        base_en = terms_en[0]
        base_kr = terms_kr[0]

        gathered: list[NewsItem] = []
        sources_html: list[tuple[str, str]] = []
        sec_filings: list[FilingItem] = []

        if title.startswith("Rocket Lab"):
            gathered.extend(rocketlab_updates_rss)
            gathered.extend(rocketlab_ir_rss)
            sec_filings = sec_rocket
            sources_html.extend(
                [
                    ("Rocket Lab Updates", "https://rocketlabcorp.com/updates/"),
                    ("Rocket Lab IR", "https://investors.rocketlabcorp.com/"),
                    ("SEC EDGAR (Rocket Lab)", "https://www.sec.gov/edgar/browse/?CIK=0001819994"),
                ]
            )
        elif title.startswith("Planet Labs"):
            gathered.extend(planet_rss)
            sec_filings = sec_planet
            sources_html.extend(
                [
                    ("Planet Pulse", "https://www.planet.com/pulse/"),
                    ("SEC EDGAR (Planet Labs)", "https://www.sec.gov/edgar/browse/?CIK=0001836833"),
                ]
            )
        elif title == "SpaceX":
            gathered.extend(nasa_rss)
            gathered.extend(spacenews_rss)
            sources_html.extend(
                [
                    ("NASA Breaking News", "https://www.nasa.gov/rss/dyn/breaking_news.rss"),
                    ("SpaceNews", "https://spacenews.com/"),
                ]
            )
        else:
            sources_html.append(("Google News", "https://news.google.com/"))

        google_items, google_ok = fetch_google_bundle(base_en, base_kr)
        gathered.extend(google_items)

        section_fetch_ok = False
        if title.startswith("Rocket Lab"):
            section_fetch_ok = bool(rocketlab_updates_ok or rocketlab_ir_ok or google_ok or sec_rocket_ok)
        elif title.startswith("Planet Labs"):
            section_fetch_ok = bool(planet_rss_ok or google_ok or sec_planet_ok)
        elif title == "SpaceX":
            section_fetch_ok = bool(nasa_ok or spacenews_ok or google_ok)
        else:
            section_fetch_ok = bool(google_ok)

        # Filter time window
        in_search = _filter_window(gathered, start=search_start, end=window_end)
        in_new = _filter_window(in_search, start=new_start, end=window_end)

        # SpaceX: keep only SpaceX-relevant titles (avoid spamming with generic space headlines)
        if title == "SpaceX":
            in_search = [it for it in in_search if re.search(r"\bSpaceX\b|스페이스", it.title, re.IGNORECASE)]
            in_new = [it for it in in_new if re.search(r"\bSpaceX\b|스페이스", it.title, re.IGNORECASE)]

        # Conservative relevance filter: keep items whose *title* mentions an alias.
        in_search = [it for it in in_search if _title_mentions(it.title, terms_en, terms_kr)]
        in_new = [it for it in in_new if _title_mentions(it.title, terms_en, terms_kr)]

        new_cnt = len(in_new)
        search_cnt = len(in_search)
        preview = _preview_items(in_new, in_search, limit=6)

        # SEC filings in new window are always "big".
        sec_in_new = []
        for f in sec_filings:
            if f.accepted_at is None:
                continue
            if new_start.astimezone(timezone.utc) <= f.accepted_at.astimezone(timezone.utc) <= window_end.astimezone(timezone.utc):
                sec_in_new.append(f)

        top_item, top_cat = _pick_top_issue(in_new)

        # Prefer SEC if exists.
        if sec_in_new:
            f = sec_in_new[0]
            meta = "신규 큰 이슈 있음 (SEC 공시)"
            what = f"SEC 공시 신규 제출({f.form})이 확인되었습니다."
            why = _why_it_matters("규제/법무")
            when = _fmt_kst(f.accepted_at) if f.accepted_at else _fmt_kst(window_end)
            date = f"{when} (발행/접수)"
            add_section(title, meta, what, why, date, sources_html, new_count=new_cnt, search_count=search_cnt, items=preview)
            continue

        if (not section_fetch_ok) and (not sec_in_new):
            meta = "수집 실패 (네트워크/차단/소스 장애)"
            what = f"수집 실패로 확인 가능한 기사/공시를 가져오지 못했습니다. (신규 기사 {new_cnt}건, 24시간 내 관련 기사 {search_cnt}건)"
            why = "네트워크 또는 소스 차단/장애 가능성이 있습니다. 다음 실행에서 재시도하세요."
            date = f"{_fmt_kst(new_start)} ~ {_fmt_kst(window_end)}"
            add_section(
                title,
                meta,
                what,
                why,
                date,
                sources_html,
                new_count=new_cnt,
                search_count=search_cnt,
                items=preview,
            )
        elif top_item and top_cat:
            meta = f"신규 큰 이슈 있음 ({top_cat})"
            what = top_item.title
            why = _why_it_matters(top_cat)
            date = f"{_fmt_kst(top_item.published_at)} (발행)"
            # Include the specific source in HTML if available and distinct.
            if top_item.source_name and top_item.url:
                sources_html = [(top_item.source_name, top_item.url)] + sources_html[:2]
            add_section(title, meta, what, why, date, sources_html, new_count=new_cnt, search_count=search_cnt, items=preview)
        else:
            meta = "신규 큰 이슈 없음 (최근 24시간 전수 검색)"
            what = "신규 큰 이슈 없음(최근 24시간 전수 검색 완료)."
            why = "단기 촉발 이벤트 부재 구간에서는 다음 공시/계약/일정 변경이 변동성의 핵심 변수가 됩니다."
            date = f"{_fmt_kst(new_start)} ~ {_fmt_kst(window_end)}"
            # Always show counts so "검색을 했는지"가 결과에 남도록 한다.
            what = f"{what} (신규 기사 {new_cnt}건, 24시간 내 관련 기사 {search_cnt}건, 큰 이슈 기준 충족 0건)"
            if search_cnt > 0:
                sample_items = in_new if in_new else in_search
                sample = _evidence_sample(sample_items, n=3)
                if sample:
                    why = f"{why} 참고 헤드라인: {sample}"
            else:
                why = f"{why} (최근 24시간 내 제목 기준 관련 기사/공시가 0건입니다.)"
            add_section(title, meta, what, why, date, sources_html, new_count=new_cnt, search_count=search_cnt, items=preview)

    # Space economy (always)
    # Build from SpaceNews + NASA + Google News (broad queries).
    space_items: list[NewsItem] = []
    space_items.extend(spacenews_rss)
    space_items.extend(nasa_rss)
    # Broad queries (keep modest).
    space_google_ok = False
    space_queries = [
        ("space economy", "en"),
        ("commercial space (contract OR award OR budget OR policy OR regulation OR satellite OR launch OR defense)", "en"),
        ("우주경제", "ko"),
        ("상업우주 (계약 OR 예산 OR 정책 OR 발사 OR 위성 OR 방산)", "ko"),
    ]
    if network_suspect:
        space_queries = space_queries[:2]
    if not hard_blocked:
        for q, loc in space_queries:
            try:
                space_items.extend(
                    _google_news_rss(
                        q,
                        locale=loc,
                        timeout=(10.0 if network_suspect else 30.0),
                        retries=(1 if network_suspect else 3),
                        sleep_s=0.4,
                    )
                )
                space_google_ok = True
            except urllib.error.HTTPError as e:
                record_error(f"Google News(space:{loc}) 실패: HTTP {e.code}")
            except Exception as e:  # noqa: BLE001
                record_error(f"Google News(space:{loc}) 실패: {_brief_exc(e)}")
            time.sleep(0.35)

    def _space_econ_relevant(it: NewsItem) -> bool:
        # SpaceNews is inherently on-topic. NASA "breaking news" can include unrelated
        # earth/climate/etc. Filter to space-industry/policy/launch/satellite topics.
        if (it.source_name or "").strip().lower() == "spacenews":
            return True
        t = (it.title or "").lower()
        if re.search(
            r"\b("
            r"contract|award|deal|partnership|agreement|customer|procurement|"
            r"budget|policy|regulation|license|faa|fcc|"
            r"satellite|launch|rocket|spacecraft|payload|orbit|"
            r"iss|space station|artemis|starship|falcon|dragon|starlink|"
            r"ariane|ula|blue origin|rocket lab|planet labs|spacex|space force|defense"
            r")\b",
            t,
        ):
            return True
        if re.search(r"우주|위성|발사|로켓|계약|수주|예산|정책|규제|상업우주|방산|스페이스", it.title or ""):
            return True
        return False

    space_items = [it for it in space_items if _space_econ_relevant(it)]

    space_in_search = _filter_window(space_items, start=search_start, end=window_end)
    space_in_new = _filter_window(space_in_search, start=new_start, end=window_end)
    top_space, top_space_cat = _pick_top_issue(space_in_new)
    space_new_cnt = len(space_in_new)
    space_search_cnt = len(space_in_search)
    space_preview = _preview_items(space_in_new, space_in_search, limit=8)

    space_sources_html = [
        ("SpaceNews", "https://spacenews.com/"),
        ("NASA Breaking News", "https://www.nasa.gov/rss/dyn/breaking_news.rss"),
        ("Google News", "https://news.google.com/"),
    ]

    space_fetch_ok = bool(spacenews_ok or nasa_ok or space_google_ok)

    if (not space_fetch_ok) and (not top_space):
        add_section(
            "우주경제",
            "수집 실패 (네트워크/차단/소스 장애)",
            f"수집 실패로 우주경제 관련 기사/발표를 가져오지 못했습니다. (신규 기사 {space_new_cnt}건, 24시간 내 관련 기사 {space_search_cnt}건)",
            "네트워크 또는 소스 차단/장애 가능성이 있습니다. 다음 실행에서 재시도하세요.",
            f"{_fmt_kst(new_start)} ~ {_fmt_kst(window_end)}",
            space_sources_html,
            new_count=space_new_cnt,
            search_count=space_search_cnt,
            items=space_preview,
        )
    elif top_space and top_space_cat:
        add_section(
            "우주경제",
            f"신규 큰 이슈 있음 ({top_space_cat})",
            top_space.title,
            _why_it_matters(top_space_cat),
            f"{_fmt_kst(top_space.published_at)} (발행)",
            [(top_space.source_name, top_space.url)] + space_sources_html[:2],
            new_count=space_new_cnt,
            search_count=space_search_cnt,
            items=space_preview,
        )
    else:
        meta = "신규 큰 이슈 없음 (최근 24시간 전수 검색 완료)"
        what = "신규 큰 이슈 없음(최근 24시간 전수 검색 완료)."
        why = "이벤트 부재 구간에서는 다음 정책/예산/대형 계약 발표가 단기 기대를 좌우할 수 있습니다."
        date = f"{_fmt_kst(new_start)} ~ {_fmt_kst(window_end)}"
        what = f"{what} (신규 기사 {space_new_cnt}건, 24시간 내 관련 기사 {space_search_cnt}건, 큰 이슈 기준 충족 0건)"
        if space_search_cnt > 0:
            sample_items = space_in_new if space_in_new else space_in_search
            sample = _evidence_sample(sample_items, n=3)
            if sample:
                why = f"{why} 참고 헤드라인: {sample}"
        else:
            why = f"{why} (최근 24시간 내 제목 기준 관련 기사/발표가 0건입니다.)"
        add_section(
            "우주경제",
            meta,
            what,
            why,
            date,
            space_sources_html,
            new_count=space_new_cnt,
            search_count=space_search_cnt,
            items=space_preview,
        )

    # 6) Decide whether this run was "successful" enough to advance the window.
    # Be conservative: only advance if every section had at least one reachable source.
    run_ok = True
    for sec in sections:
        if sec.get("meta", "").startswith("수집 실패"):
            run_ok = False
            break

    # 7) Write HTML.
    # If the run failed due to network, keep the last successful dashboard so the
    # "리포트 열기" link still opens something useful. Save the failed run to a
    # separate file for debugging.
    html_text = _render_html(
        sections,
        generated_at=generated_at,
        new_start=new_start,
        search_start=search_start,
        window_end=window_end,
        watchlist_count=watchlist_count,
    )
    wrote_main_html = False
    wrote_error_html = False
    all_failed = bool(sections) and all((sec.get("meta", "").startswith("수집 실패")) for sec in sections)
    if network_suspect and (not hard_blocked) and all_failed and os.environ.get("BRIEF_RECOVERY_TRIED") != "1":
        # Automation 세션 네트워크가 뒤늦게 살아나는 경우가 있어, 1회 재시도한다.
        retry_sleep_raw = os.environ.get("BRIEF_RECOVERY_SLEEP_S", "45")
        try:
            retry_sleep = int(retry_sleep_raw)
        except Exception:
            retry_sleep = 45
        retry_sleep = max(15, min(180, retry_sleep))
        sys.stdout.write(f"<!-- network-recovery sleep={retry_sleep}s and retry once -->\n")
        sys.stdout.flush()
        time.sleep(retry_sleep)
        env = os.environ.copy()
        env["BRIEF_RECOVERY_TRIED"] = "1"
        os.execvpe(sys.executable, [sys.executable, str(Path(__file__).resolve())], env)

    try:
        if all_failed and HTML_PATH.exists() and HTML_PATH.stat().st_size > 0:
            # Global network failure: don't overwrite the last-good report.
            HTML_ERROR_PATH.write_text(html_text, encoding="utf-8")
            wrote_error_html = True
        else:
            # Normal/partial failure: always update the dashboard so it reflects the latest attempt.
            HTML_PATH.write_text(html_text, encoding="utf-8")
            wrote_main_html = True
    except Exception:
        # If disk write fails, still produce the inbox output.
        pass

    # 8) Update state: only move last_success_at when the run is ok.
    prev_last_success_raw = state.get("last_success_at") if isinstance(state, dict) else None
    prev_last_success = str(prev_last_success_raw) if prev_last_success_raw else None

    new_state: dict = {
        "agent_version": AGENT_VERSION,
        "last_attempt_at": window_end.isoformat(),
        "run_ok": bool(run_ok),
        "new_start": new_start.isoformat(),
        "search_start": search_start.isoformat(),
        "window_end": window_end.isoformat(),
        "host_ip_cache": HOST_IP_CACHE,
    }
    if run_ok:
        new_state["last_success_at"] = window_end.isoformat()
    elif prev_last_success:
        new_state["last_success_at"] = prev_last_success
    _save_state(STATE_PATH, new_state)

    # 9) Print Inbox Markdown (Korean).
    lines: list[str] = []
    # Prefer relative link (some UIs block file://).
    lines.append("[리포트 열기](stock_feed.html)")
    # Many UIs auto-link plain absolute paths better than code-formatted ones.
    lines.append(f"리포트 파일: {str(HTML_PATH)}")
    lines.append(f"리포트 URL: file://{str(HTML_PATH)}")
    lines.append(f"에이전트 버전: {AGENT_VERSION}")
    if (not run_ok) and wrote_error_html:
        lines.append(f"실패 리포트 파일(이번 실행): {str(HTML_ERROR_PATH)}")
        lines.append(f"실패 리포트 URL: file://{str(HTML_ERROR_PATH)}")
    lines.append("")
    lines.append("생성 시각: " + _fmt_kst(generated_at))
    lines.append("신규 윈도우: " + _fmt_kst(new_start) + " ~ " + _fmt_kst(window_end))
    lines.append("검색 윈도우: " + _fmt_kst(search_start) + " ~ " + _fmt_kst(window_end))
    lines.append(f"워치리스트 항목 수: {watchlist_count}")
    lines.append("")

    if fetch_error_counts:
        lines.append("수집 상태: 일부 소스에서 오류가 발생했습니다.")
        proxy_keys = []
        for k in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"]:
            if os.environ.get(k):
                proxy_keys.append(k)
        if proxy_keys:
            # Do not print proxy values (can be sensitive). Just note their presence.
            lines.append("- 참고: 프록시 환경 변수 감지 -> 무시하고 직접 연결을 시도합니다. (" + ", ".join(proxy_keys) + ")")
        for msg, cnt in list(fetch_error_counts.items())[:10]:
            if cnt <= 1:
                lines.append("- " + msg)
            else:
                lines.append(f"- {msg} (x{cnt})")
        if not run_ok:
            lines.append("- 상태 갱신: 수집 실패로 신규 윈도우 기준(last_success_at)을 갱신하지 않았습니다.")
        lines.append("")

    for sec in sections:
        lines.append(sec["title"])
        lines.append("무슨 일: " + sec["what"])
        lines.append("왜 중요한지: " + sec["why"])
        lines.append("날짜: " + sec["date"] + ".")
        # Sources as names only (no links).
        src_names = []
        for name, _url in (sec.get("sources_html") or []):
            if name and name not in src_names:
                src_names.append(name)
        lines.append("출처: " + "; ".join(src_names) + ".")
        lines.append("")

    if wrote_main_html:
        lines.append("HTML 대시보드 갱신: stock_feed.html")
    elif wrote_error_html:
        lines.append("HTML 대시보드 유지: stock_feed.html (마지막 정상 리포트)")
        lines.append("HTML 실패 리포트 저장: stock_feed_error.html")
    else:
        lines.append("HTML 대시보드: 갱신 실패(파일 쓰기 오류)")

    out = "\n".join(lines).rstrip() + "\n"

    sys.stdout.write(out)

    # Exit code 0 even if some fetches failed; the report still updates.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
