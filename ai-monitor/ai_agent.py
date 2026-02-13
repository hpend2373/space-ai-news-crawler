#!/usr/bin/env python3
"""
AI Release Watch Agent

Fetches official AI updates (X via Nitter + official blogs/news pages) for:
- OpenAI
- Anthropic
- Google AI (Google AI blog + DeepMind blog)

Generates a modern HTML report covering only the last N hours (default: 24).
"""

import argparse
import hashlib
import html as html_lib
import json
import os
import random
import re
import socket
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple
from urllib.error import HTTPError, URLError
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET


BASE_DIR = Path(__file__).parent
CONFIG_FILE = BASE_DIR / "config.json"
OUTPUT_DIR = BASE_DIR / "reports"
LOG_DIR = BASE_DIR / "logs"
CACHE_DIR = BASE_DIR / ".cache"

DASHBOARD_FILE = BASE_DIR / "dashboard.html"
DASHBOARD_MD_FILE = BASE_DIR / "dashboard.md"
HEALTH_FILE = BASE_DIR / "health_last.json"
TRANSLATION_CACHE_FILE = CACHE_DIR / "translation_cache.json"

NITTER_COOKIE_CACHE = CACHE_DIR / "nitter_cookies.json"

DEFAULT_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/122.0.0.0 Safari/537.36"
)


# ---------------------------------------------------------------------------
# Network readiness guard
# ---------------------------------------------------------------------------
# Codex Automation sandbox may start the script before the macOS network stack
# is fully available, causing all DNS lookups to fail with [Errno 8].
_NET_PROBE_HOSTS = ["dns.google", "one.one.one.one", "news.google.com"]
_NET_MAX_WAIT_S = 30
_NET_POLL_INTERVAL_S = 2


def _wait_for_network(*, max_wait: float = _NET_MAX_WAIT_S, poll: float = _NET_POLL_INTERVAL_S) -> bool:
    """Block until DNS resolution succeeds for at least one probe host, or *max_wait* seconds elapse."""
    deadline = time.monotonic() + max_wait
    attempt = 0
    while True:
        for host in _NET_PROBE_HOSTS:
            try:
                socket.getaddrinfo(host, 443, socket.AF_UNSPEC, socket.SOCK_STREAM)
                if attempt > 0:
                    print(f"[net-guard] DNS OK after {attempt} retries ({host})", file=sys.stderr)
                return True
            except OSError:
                pass
        attempt += 1
        if time.monotonic() >= deadline:
            print(f"[net-guard] DNS still failing after {max_wait}s — proceeding anyway", file=sys.stderr)
            return False
        time.sleep(poll)


def _now_local() -> datetime:
    return datetime.now().astimezone()


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _ensure_dirs() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    CACHE_DIR.mkdir(parents=True, exist_ok=True)


def _log(msg: str) -> None:
    _ensure_dirs()
    ts = _now_local().strftime("%Y-%m-%d %H:%M:%S%z")
    line = f"[{ts}] {msg}\n"
    try:
        (LOG_DIR / "ai_news_agent.log").open("a", encoding="utf-8").write(line)
    except Exception:
        # Logging must never break report generation.
        pass


def _http_get(
    url: str,
    timeout_s: int,
    headers: Optional[Dict[str, str]] = None,
    *,
    retries: int = 2,
    backoff_s: float = 0.8,
) -> Tuple[int, Dict[str, str], bytes, Optional[str]]:
    req_headers = {
        "User-Agent": DEFAULT_UA,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
    }
    if headers:
        req_headers.update(headers)

    last_status: int = 0
    last_headers: Dict[str, str] = {}
    last_body: bytes = b""
    last_err: Optional[str] = None

    attempts = max(1, int(retries) + 1)
    for attempt in range(attempts):
        req = urllib.request.Request(url, headers=req_headers)
        try:
            with urllib.request.urlopen(req, timeout=timeout_s) as resp:
                return getattr(resp, "status", 200), dict(resp.headers), resp.read(), None
        except HTTPError as e:
            try:
                body = e.read()
            except Exception:
                body = b""

            reason = getattr(e, "reason", None)
            err = f"HTTP {e.code}: {reason}" if reason else f"HTTP {e.code}"

            last_status, last_headers, last_body, last_err = e.code, dict(e.headers), body, err

            # Nitter sometimes returns a 503 challenge page ("Verifying your browser").
            # Retrying doesn't help; the caller needs to solve it.
            if e.code == 503 and b"Verifying your browser" in body:
                return last_status, last_headers, last_body, last_err

            # Retry transient server errors.
            if e.code >= 500 and attempt < attempts - 1:
                time.sleep(backoff_s * (2**attempt))
                continue
            return last_status, last_headers, last_body, last_err
        except URLError as e:
            reason = getattr(e, "reason", None)
            err = f"URLError: {reason}" if reason else f"URLError: {e}"
            last_status, last_headers, last_body, last_err = 0, {}, b"", err
            if attempt < attempts - 1:
                time.sleep(backoff_s * (2**attempt))
                continue
            _log(f"HTTP error for {url}: {err}")
            return last_status, last_headers, last_body, last_err
        except Exception as e:
            err = f"{type(e).__name__}: {e}"
            last_status, last_headers, last_body, last_err = 0, {}, b"", err
            if attempt < attempts - 1:
                time.sleep(backoff_s * (2**attempt))
                continue
            _log(f"HTTP error for {url}: {err}")
            return last_status, last_headers, last_body, last_err

    return last_status, last_headers, last_body, last_err


def _strip_html(s: str) -> str:
    if not s:
        return ""
    s = s.replace("\r\n", "\n")
    s = re.sub(r"<br\s*/?>", "\n", s, flags=re.I)
    s = re.sub(r"</p\s*>", "\n", s, flags=re.I)
    s = re.sub(r"<[^>]+>", "", s)
    s = html_lib.unescape(s)
    # Collapse whitespace but keep newlines.
    s = re.sub(r"[ \t\f\v]+", " ", s)
    s = re.sub(r"\n\s*\n\s*\n+", "\n\n", s)
    return s.strip()


def _safe_text(s: str, limit: int) -> str:
    s = (s or "").strip()
    if len(s) <= limit:
        return s
    return s[: max(0, limit - 1)].rstrip() + "…"


def _parse_nitter_title_dt(title_dt: str) -> Optional[datetime]:
    """
    Parse Nitter tweet timestamp from the anchor title text.
    Examples:
    - "Feb 9, 2026 · 5:20 PM UTC"
    - "Feb 6, 2026 · 16:20 UTC"
    """
    title_dt = (title_dt or "").strip()
    if not title_dt:
        return None

    m = re.search(
        r"([A-Z][a-z]{2}\s+\d{1,2},\s+\d{4}).*?(\d{1,2}:\d{2})\s*([AP]M)\s*UTC",
        title_dt,
    )
    if m:
        dt = datetime.strptime(f"{m.group(1)} {m.group(2)} {m.group(3)}", "%b %d, %Y %I:%M %p")
        return dt.replace(tzinfo=timezone.utc)

    m2 = re.search(
        r"([A-Z][a-z]{2}\s+\d{1,2},\s+\d{4}).*?(\d{1,2}:\d{2})\s*UTC",
        title_dt,
    )
    if m2:
        dt = datetime.strptime(f"{m2.group(1)} {m2.group(2)}", "%b %d, %Y %H:%M")
        return dt.replace(tzinfo=timezone.utc)
    return None


def _parse_compact_int(s: str) -> int:
    """
    Parse numbers like "1,234", "12K", "1.2M" into an int.
    Unknown/empty -> 0.
    """
    s = (s or "").strip()
    if not s:
        return 0
    s = s.replace(",", "").replace(" ", "").upper()

    m = re.match(r"^(\d+(?:\.\d+)?)([KMB])?$", s)
    if not m:
        # Fallback: strip non-digits.
        digits = re.sub(r"[^\d]", "", s)
        return int(digits) if digits else 0

    num = float(m.group(1))
    suf = m.group(2) or ""
    mult = 1.0
    if suf == "K":
        mult = 1_000.0
    elif suf == "M":
        mult = 1_000_000.0
    elif suf == "B":
        mult = 1_000_000_000.0
    return int(num * mult)


def _extract_nitter_stat(chunk: str, icon: str) -> int:
    """
    Extract engagement stat from a Nitter timeline-item chunk.
    icon: "comment" | "retweet" | "heart"
    """
    if not chunk:
        return 0

    # Don't try to regex-extract the whole tweet-stats block: it contains nested <div>
    # tags and a naive "(.*?)</div>" will truncate at the first inner </div>.
    stats_block = chunk

    patterns = [
        rf'icon-{re.escape(icon)}[^<]*</span>\s*<span[^>]*class="stat-num"[^>]*>\s*([^<]+)',
        rf'icon-{re.escape(icon)}[^<]*</span>\s*<span[^>]*>\s*([^<]+)',
        rf'icon-{re.escape(icon)}[^<]*</span>\s*([0-9][0-9.,KMBkmb]*)',
    ]
    for pat in patterns:
        m = re.search(pat, stats_block, re.S | re.I)
        if not m:
            continue
        raw = _strip_html(m.group(1))
        return _parse_compact_int(raw)
    return 0


def _looks_korean(s: str) -> bool:
    if not s:
        return False
    return bool(re.search(r"[가-힣]", s))


def _is_ai_related_text(text: str) -> bool:
    """
    Heuristic filter to keep the "X 트렌딩 AI" section actually about AI.
    Nitter search queries can be noisy (e.g., "agent" == FBI agent), so we double-check
    the tweet body for AI/company/product terms.
    """
    s = (text or "").strip()
    if not s:
        return False

    low = s.lower()
    must_sub = [
        "openai",
        "anthropic",
        "deepmind",
        "google deepmind",
        "notebooklm",
        "chatgpt",
        "gpt",
    ]
    for kw in must_sub:
        if kw in low:
            return True

    # "gemini"/"claude" are ambiguous words outside AI contexts; require extra hints.
    if "gemini" in low:
        if "google" in low or re.search(r"\bai\b", low) or re.search(r"\bllm\b", low) or "model" in low or "api" in low:
            return True
    if "claude" in low:
        if "anthropic" in low or re.search(r"\bai\b", low) or re.search(r"\bllm\b", low) or "model" in low or "api" in low:
            return True

    generic_ai = False
    if "인공지능" in s:
        generic_ai = True
    if re.search(r"\bai\b", low):
        generic_ai = True
    if re.search(r"\bllm\b", low):
        generic_ai = True
    if "artificial intelligence" in low:
        generic_ai = True
    if "large language model" in low:
        generic_ai = True
    if "language model" in low:
        generic_ai = True

    if not generic_ai:
        return False

    # "AI"만 있는 일반 잡담/정치 이슈는 제외하고, 릴리스/제품/연구 맥락만 통과.
    ctx_terms = [
        "model",
        "release",
        "released",
        "launch",
        "launched",
        "announce",
        "announced",
        "update",
        "updated",
        "api",
        "preview",
        "beta",
        "agent",
        "reasoning",
        "research",
        "benchmark",
        "prompt",
        "chatbot",
        "codex",
        "gemini",
        "claude",
        "chatgpt",
        "gpt",
    ]
    return any(t in low for t in ctx_terms)


def _is_low_quality_trending(text: str) -> bool:
    """
    Filter obvious non-news spam/noise for X trending cards.
    """
    s = (text or "").strip()
    if not s:
        return True
    if len(s) < 24:
        return True
    low = s.lower()

    spam_markers = [
        "airdrop",
        "giveaway",
        "join now",
        "pump",
        "moon",
        "memecoin",
        "token",
        "ca:",
        "contract address",
        "buy now",
        "epstein",
        "fbi",
        "olympic",
    ]
    for m in spam_markers:
        if m in low:
            return True

    # Heavy ticker noise like "$ABC $XYZ" often means speculative token posts.
    if len(re.findall(r"\$[A-Za-z0-9_]{2,}", s)) >= 2:
        return True
    return False


def _tcache_key(provider: str, target_lang: str, text: str) -> str:
    h = hashlib.sha1((text or "").encode("utf-8")).hexdigest()
    return f"v1|{provider}|{target_lang}|{h}"


def _load_translation_cache() -> Dict[str, Dict[str, str]]:
    try:
        data = json.loads(TRANSLATION_CACHE_FILE.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return data  # type: ignore[return-value]
    except Exception:
        pass
    return {}


def _save_translation_cache(cache: Dict[str, Dict[str, str]]) -> None:
    try:
        TRANSLATION_CACHE_FILE.write_text(
            json.dumps(cache, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    except Exception:
        # Cache must never break report generation.
        return


def _translate_google_gtx(text: str, target_lang: str, timeout_s: int) -> Tuple[Optional[str], Optional[str]]:
    """
    Best-effort translation via translate.googleapis.com (unofficial, no API key).
    Returns: (translated_text|None, error|None)
    """
    text = (text or "").strip()
    if not text:
        return "", None

    url = (
        "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl="
        + urllib.parse.quote(target_lang)
        + "&dt=t&q="
        + urllib.parse.quote(text)
    )
    status, _, body_b, err = _http_get(url, timeout_s, headers={"Accept": "*/*"}, retries=1)
    if status != 200 or not body_b:
        return None, err or f"HTTP {status}"

    try:
        data = json.loads(body_b.decode("utf-8", "ignore"))
        segs = data[0] if isinstance(data, list) and data else []
        out = ""
        if isinstance(segs, list):
            for seg in segs:
                if isinstance(seg, list) and seg and isinstance(seg[0], str):
                    out += seg[0]
        out = out.strip()
        return out or None, None
    except Exception as e:
        return None, f"parse_error: {e}"


def _translate_text(
    text: str,
    *,
    provider: str,
    target_lang: str,
    timeout_s: int,
    cache: Dict[str, Dict[str, str]],
) -> Tuple[str, bool, Optional[str]]:
    """
    Returns: (text_out, translated?, error?)
    """
    text = (text or "").strip()
    if not text:
        return "", False, None

    # If we're targeting Korean and the text already looks like Korean, skip.
    if target_lang.lower().startswith("ko") and _looks_korean(text):
        return text, False, None

    key = _tcache_key(provider, target_lang, text)
    hit = cache.get(key)
    if isinstance(hit, dict) and isinstance(hit.get("trans"), str) and hit.get("trans"):
        return str(hit["trans"]), True, None

    if provider == "google_gtx":
        trans, err = _translate_google_gtx(text, target_lang, timeout_s=timeout_s)
    else:
        return text, False, f"unknown_provider: {provider}"

    if trans:
        cache[key] = {"orig": text, "trans": _safe_text(trans, 800)}
        return trans, True, None
    return text, False, err


def _parse_rfc822_dt(s: str) -> Optional[datetime]:
    if not s:
        return None
    try:
        dt = parsedate_to_datetime(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except Exception:
        return None


def _parse_month_day_year(s: str) -> Optional[datetime]:
    if not s:
        return None
    try:
        dt = datetime.strptime(s.strip(), "%b %d, %Y")
        # Date-only sources: choose end-of-day local time to avoid false negatives.
        local_tz = _now_local().tzinfo or timezone.utc
        dt = dt.replace(hour=23, minute=59, second=59, tzinfo=local_tz)
        return dt.astimezone(timezone.utc)
    except Exception:
        return None


def _format_local(dt_utc: datetime) -> str:
    try:
        dt_local = dt_utc.astimezone()
        return dt_local.strftime("%Y-%m-%d %H:%M")
    except Exception:
        return dt_utc.strftime("%Y-%m-%d %H:%M")


@dataclass(frozen=True)
class NewsItem:
    provider_id: str
    provider_name: str
    source: str  # X | RSS | WEB | DIGEST
    title: str
    url: str
    published_at_utc: datetime
    summary: str
    raw_text: str = ""
    meta: str = ""

    def dedupe_key(self) -> str:
        u = (self.url or "").strip()
        if u:
            return f"url:{u}"
        t = (self.title or "").strip().lower()
        d = self.published_at_utc.strftime("%Y-%m-%d")
        return f"t:{t}|d:{d}|p:{self.provider_id}|s:{self.source}"


@dataclass(frozen=True)
class NitterSearchHit:
    url: str
    published_at_utc: datetime
    content: str
    username: str = ""
    fullname: str = ""
    replies: int = 0
    retweets: int = 0
    likes: int = 0

    def score(self) -> int:
        # Weight reshares slightly higher than replies.
        return int(self.likes) + int(self.retweets) * 2 + int(self.replies)


class NitterClient:
    def __init__(self, instances: List[str], timeout_s: int) -> None:
        self._instances = [i.rstrip("/") for i in instances if i.strip()]
        self._timeout_s = timeout_s
        self._cookie_by_instance: Dict[str, str] = {}
        self._load_cache()

    def _load_cache(self) -> None:
        try:
            data = json.loads(NITTER_COOKIE_CACHE.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                for k, v in data.items():
                    if isinstance(k, str) and isinstance(v, str) and v:
                        self._cookie_by_instance[k] = v
        except Exception:
            return

    def _save_cache(self) -> None:
        try:
            NITTER_COOKIE_CACHE.write_text(json.dumps(self._cookie_by_instance, indent=2), encoding="utf-8")
        except Exception:
            return

    @staticmethod
    def _solve_verification_cookie(body: str) -> Optional[str]:
        # Example JS:
        # const a0_0x2a54=['<HEX>','res=','array'];
        # let c='...'; let n1=parseInt('0x'+c[0]); while(true){ let s=s1['array'](c+i); if(s[n1]===0xb0&&s[n1+1]===0xb){document.cookie='res='+c+i;break}}
        m = re.search(r"\['([0-9A-F]{20,})'", body)
        if not m:
            return None
        c = m.group(1)
        try:
            n1 = int(c[0], 16)
        except Exception:
            n1 = 0

        m2 = re.search(r"s\[n1\]===0x([0-9a-f]+)&&s\[n1\+0x1\]===0x([0-9a-f]+)", body, re.I)
        b1 = int(m2.group(1), 16) if m2 else 0xB0
        b2 = int(m2.group(2), 16) if m2 else 0x0B

        i = 0
        while i < 5_000_000:
            h = hashlib.sha1((c + str(i)).encode("utf-8")).digest()
            if n1 + 1 < len(h) and h[n1] == b1 and h[n1 + 1] == b2:
                return f"res={c}{i}"
            i += 1
        return None

    @staticmethod
    def _is_verification_page(body: str) -> bool:
        b = (body or "").lower()
        return "verifying your browser" in b and "document.cookie" in b

    @staticmethod
    def _headers_for_instance(instance: str) -> Dict[str, str]:
        """
        Some Nitter instances block browser-like UAs and allow CLI-like UAs.
        """
        inst = (instance or "").lower()
        if "tiekoetter.com" in inst:
            return {"User-Agent": "curl/8.7.1"}
        return {}

    def _fetch_html(self, instance: str, path_or_url: str) -> Tuple[int, str, Optional[str]]:
        if path_or_url.startswith("http://") or path_or_url.startswith("https://"):
            url = path_or_url
        else:
            url = f"{instance}/{path_or_url.lstrip('/')}"
        cookie = self._cookie_by_instance.get(instance)
        headers = self._headers_for_instance(instance)
        if cookie:
            headers["Cookie"] = cookie
        status, _, body_b, err = _http_get(url, self._timeout_s, headers=headers)
        body = body_b.decode("utf-8", "ignore")

        # Some Nitter instances return challenge pages as 200/403/503.
        # Detect by body and solve regardless of HTTP status.
        if self._is_verification_page(body):
            solved = self._solve_verification_cookie(body)
            if solved:
                self._cookie_by_instance[instance] = solved
                self._save_cache()
                retry_headers = self._headers_for_instance(instance)
                retry_headers["Cookie"] = solved
                status, _, body_b, err = _http_get(url, self._timeout_s, headers=retry_headers)
                body = body_b.decode("utf-8", "ignore")
        return status, body, err

    def _fetch_profile_html(self, instance: str, handle: str) -> Tuple[int, str, Optional[str]]:
        return self._fetch_html(instance, f"/{handle.lstrip('@')}")

    @staticmethod
    def _parse_profile_tweets(instance: str, handle: str, body: str, max_posts: int) -> List[NewsItem]:
        items: List[NewsItem] = []

        chunks = body.split('<div class="timeline-item')
        for chunk in chunks[1:]:
            # URL + datetime
            m_date = re.search(
                r'class="tweet-date"\s*>\s*<a\s+href="([^"]+)"\s+title="([^"]+UTC)"',
                chunk,
                re.S,
            )
            if not m_date:
                continue
            href = m_date.group(1).strip()
            title_dt = m_date.group(2).strip()

            dt = _parse_nitter_title_dt(title_dt)
            if not dt:
                continue

            # Content
            m_content = re.search(r'class="tweet-content[^"]*"[^>]*>(.*?)</div>', chunk, re.S)
            content_html = m_content.group(1) if m_content else ""
            content = _strip_html(content_html)
            if not content:
                continue

            url = href
            if url.startswith("/"):
                url = f"{instance}{url}"

            items.append(
                NewsItem(
                    provider_id=handle.lower(),
                    provider_name=handle,
                    source="X",
                    title=_safe_text(content.replace("\n", " "), 140),
                    url=url,
                    published_at_utc=dt,
                    summary=_safe_text(content, 420),
                    raw_text=content,
                )
            )
            if len(items) >= max_posts:
                break

        return items

    @staticmethod
    def _parse_profile_tweets_fallback(instance: str, handle: str, body: str, max_posts: int) -> List[NewsItem]:
        """
        Nitter HTML is not stable across instances/versions. This fallback avoids relying on
        exact chunk boundaries and supports both AM/PM and 24h UTC formats in the title.
        """
        items: List[NewsItem] = []

        tweet_re = re.compile(
            r'<div class="timeline-item[^"]*"[^>]*>.*?'
            r'<span class="tweet-date">\s*<a\s+href="([^"]+)"\s+title="([^"]+)".*?>.*?</a>\s*</span>.*?'
            r'<div class="tweet-content[^"]*"[^>]*>(.*?)</div>',
            re.S,
        )

        for m in tweet_re.finditer(body):
            href = (m.group(1) or "").strip()
            title_dt = (m.group(2) or "").strip()
            content_html = m.group(3) if m.group(3) else ""
            content = _strip_html(content_html)
            if not href or not content:
                continue

            dt = _parse_nitter_title_dt(title_dt)

            if not dt:
                continue

            url = href
            if url.startswith("/"):
                url = f"{instance}{url}"

            items.append(
                NewsItem(
                    provider_id=handle.lower(),
                    provider_name=handle,
                    source="X",
                    title=_safe_text(content.replace("\n", " "), 140),
                    url=url,
                    published_at_utc=dt,
                    summary=_safe_text(content, 420),
                    raw_text=content,
                )
            )
            if len(items) >= max_posts:
                break

        return items

    @staticmethod
    def _sniff_search_no_results(body: str) -> bool:
        b = (body or "").lower()
        # Nitter instances vary, but most show a "No results" style message.
        return "no results" in b or "no tweets" in b or "no matches" in b

    @staticmethod
    def _parse_search_tweets(instance: str, body: str, max_posts: int) -> List[NitterSearchHit]:
        hits: List[NitterSearchHit] = []
        if not body:
            return hits

        chunks = body.split('<div class="timeline-item')
        for chunk in chunks[1:]:
            # URL + datetime
            m_date = re.search(
                r'class="tweet-date"\s*>\s*<a\s+href="([^"]+)"\s+title="([^"]+)"',
                chunk,
                re.S,
            )
            if not m_date:
                continue
            href = (m_date.group(1) or "").strip()
            title_dt = (m_date.group(2) or "").strip()
            dt = _parse_nitter_title_dt(title_dt)
            if not dt:
                continue

            # Content
            m_content = re.search(r'class="tweet-content[^"]*"[^>]*>(.*?)</div>', chunk, re.S)
            content_html = m_content.group(1) if m_content else ""
            content = _strip_html(content_html)
            if not content:
                continue

            # Author
            username = ""
            m_user = re.search(r'data-username="([^"]+)"', chunk)
            if m_user:
                username = (m_user.group(1) or "").strip()
            if not username:
                m_user2 = re.search(r'class="username"[^>]*>@?([^<\\s]+)', chunk)
                if m_user2:
                    username = (m_user2.group(1) or "").strip().lstrip("@")

            fullname = ""
            m_full = re.search(r'class="fullname"[^>]*title="([^"]+)"', chunk)
            if m_full:
                fullname = _strip_html(m_full.group(1))
            if not fullname:
                m_full2 = re.search(r'class="fullname"[^>]*>(.*?)</a>', chunk, re.S)
                if m_full2:
                    fullname = _strip_html(m_full2.group(1))

            # Engagement stats
            replies = _extract_nitter_stat(chunk, "comment")
            retweets = _extract_nitter_stat(chunk, "retweet")
            likes = _extract_nitter_stat(chunk, "heart")

            url = href
            if url.startswith("/"):
                url = f"{instance}{url}"

            hits.append(
                NitterSearchHit(
                    url=url,
                    published_at_utc=dt,
                    content=content,
                    username=username,
                    fullname=fullname,
                    replies=replies,
                    retweets=retweets,
                    likes=likes,
                )
            )
            if len(hits) >= max_posts:
                break
        return hits

    def search_tweets(self, query: str, max_posts: int) -> Tuple[List[NitterSearchHit], List[str]]:
        errs: List[str] = []
        q = (query or "").strip()
        if not q:
            return [], []

        for instance in self._instances:
            url = f"{instance}/search?f=tweets&q={urllib.parse.quote(q)}"
            status, body, err = self._fetch_html(instance, url)
            if status != 200 or not body:
                errs.append(f"{instance}: {err or f'HTTP {status}'}")
                continue

            hits = self._parse_search_tweets(instance, body, max_posts=max_posts)
            if hits:
                return hits, []
            if self._sniff_search_no_results(body):
                return [], []

            reason = self._sniff_parse_failure(body)
            dumped = self._maybe_dump_debug_html(f"search_{_safe_text(q, 24)}", instance, status, body)
            extra = f" ({reason})" if reason else ""
            if dumped:
                extra += f" [dump: {dumped}]"
            errs.append(f"{instance}: 검색 결과 0개(파싱 실패){extra}")

        return [], errs

    @staticmethod
    def _sniff_parse_failure(body: str) -> str:
        # Keep this short; it shows up in source health warnings.
        if "Verifying your browser" in body:
            return "challenge page"
        if "timeline-item" not in body:
            return "no timeline items"
        if "tweet-date" not in body:
            return "missing tweet-date"
        if "tweet-content" not in body:
            return "missing tweet-content"
        return "unexpected markup"

    @staticmethod
    def _maybe_dump_debug_html(handle: str, instance: str, status: int, body: str) -> Optional[str]:
        # Opt-in dump for debugging intermittent Nitter markup changes.
        if os.environ.get("AI_MONITOR_NITTER_DUMP", "").strip() not in ("1", "true", "TRUE", "yes", "YES"):
            return None
        try:
            _ensure_dirs()
            ts = _now_local().strftime("%Y%m%d_%H%M%S")
            safe_handle = re.sub(r"[^A-Za-z0-9_.-]+", "_", handle or "handle")
            out = CACHE_DIR / f"nitter_dump_{safe_handle}_{ts}.html"
            out.write_text(
                f"<!-- instance={instance} status={status} -->\n" + (body or ""),
                encoding="utf-8",
            )
            return str(out)
        except Exception:
            return None

    def fetch_posts(self, handle: str, max_posts: int) -> Tuple[List[NewsItem], List[str]]:
        errs: List[str] = []
        for instance in self._instances:
            status, body, err = self._fetch_profile_html(instance, handle)
            if status != 200 or not body:
                errs.append(f"{instance}: {err or f'HTTP {status}'}")
                continue

            parsed = self._parse_profile_tweets(instance, handle, body, max_posts=max_posts)
            if not parsed:
                parsed = self._parse_profile_tweets_fallback(instance, handle, body, max_posts=max_posts)
            if parsed:
                return parsed, []
            reason = self._sniff_parse_failure(body)
            dumped = self._maybe_dump_debug_html(handle, instance, status, body)
            extra = f" ({reason})" if reason else ""
            if dumped:
                extra += f" [dump: {dumped}]"
            errs.append(f"{instance}: 게시물 0개(파싱 실패){extra}")
        return [], errs


def _parse_rss(url: str, timeout_s: int) -> Tuple[List[Tuple[str, str, datetime, str]], Optional[str]]:
    status, _, body_b, err = _http_get(url, timeout_s)
    if status != 200 or not body_b:
        return [], err or f"HTTP {status}"

    try:
        root = ET.fromstring(body_b)
    except Exception as e:
        return [], f"XML 파싱 오류: {e}"

    channel = root.find("channel")
    if channel is None:
        return [], "채널 누락"

    out: List[Tuple[str, str, datetime, str]] = []
    for item in channel.findall("item"):
        title = (item.findtext("title") or "").strip()
        link = (item.findtext("link") or "").strip()
        pub = (item.findtext("pubDate") or "").strip()
        if not pub:
            # Common alternate: dc:date
            for child in item:
                if child.tag.endswith("date") and (child.text or "").strip():
                    pub = (child.text or "").strip()
                    break

        dt = _parse_rfc822_dt(pub)
        if not dt:
            continue

        desc = (item.findtext("description") or "").strip()
        desc = _strip_html(desc)
        out.append((title, link, dt, desc))
    return out, None


def _fetch_anthropic_news(listing_url: str, timeout_s: int, max_articles: int = 18) -> Tuple[List[NewsItem], List[str]]:
    errs: List[str] = []
    status, _, body_b, err = _http_get(listing_url, timeout_s)
    if status != 200 or not body_b:
        return [], [f"{listing_url}: {err or f'HTTP {status}'}"]

    body = body_b.decode("utf-8", "ignore")
    hrefs = re.findall(r'href="([^"]+)"', body)

    urls: List[str] = []
    seen: set = set()
    for href in hrefs:
        if not href:
            continue
        if href.startswith("/news/"):
            u = "https://www.anthropic.com" + href
        elif href.startswith("https://www.anthropic.com/news/"):
            u = href
        else:
            continue
        u = u.split("#", 1)[0]
        if u in seen:
            continue
        seen.add(u)
        urls.append(u)
        if len(urls) >= max_articles:
            break

    items: List[NewsItem] = []
    for u in urls:
        s, _, b, e = _http_get(u, timeout_s)
        if s != 200 or not b:
            errs.append(f"{u}: {e or f'HTTP {s}'}")
            continue
        h = b.decode("utf-8", "ignore")

        m_title = re.search(r'<meta\s+property="og:title"\s+content="([^"]+)"', h)
        title = m_title.group(1).strip() if m_title else ""
        if not title:
            m_h1 = re.search(r"<h1[^>]*>(.*?)</h1>", h, re.S)
            title = _strip_html(m_h1.group(1)) if m_h1 else ""

        m_desc = re.search(r'<meta\s+(?:property="og:description"|name="description")\s+content="([^"]*)"', h)
        desc = (m_desc.group(1) if m_desc else "").strip()

        m_date = re.search(r'<div\s+class="body-3\s+agate">\s*([A-Z][a-z]{2}\s+\d{1,2},\s+\d{4})\s*</div>', h)
        dt = _parse_month_day_year(m_date.group(1)) if m_date else None
        if not dt:
            # If date isn't found, skip; we can't enforce the 24h rule reliably.
            continue

        items.append(
            NewsItem(
                provider_id="anthropic",
                provider_name="Anthropic",
                source="WEB",
                title=_safe_text(title, 120),
                url=u,
                published_at_utc=dt,
                summary=_safe_text(desc, 260),
                raw_text=f"{title}\n\n{desc}".strip(),
            )
        )

    return items, errs


def _fetch_google_news_digest(queries: List[str], timeout_s: int, max_total: int) -> Tuple[List[NewsItem], List[str]]:
    errs: List[str] = []
    items: List[NewsItem] = []
    for q in queries:
        if len(items) >= max_total:
            break
        q = (q or "").strip()
        if not q:
            continue

        url = _google_news_rss_url(q)
        status, _, body_b, err = _http_get(url, timeout_s)
        if status != 200 or not body_b:
            errs.append(f"Google News RSS: {err or f'HTTP {status}'} ({q})")
            continue

        try:
            root = ET.fromstring(body_b)
        except Exception as e:
            errs.append(f"Google News RSS XML 파싱 오류: {e} ({q})")
            continue

        channel = root.find("channel")
        if channel is None:
            errs.append(f"Google News RSS 채널 누락 ({q})")
            continue

        for it in channel.findall("item"):
            if len(items) >= max_total:
                break
            title = (it.findtext("title") or "").strip()
            link = (it.findtext("link") or "").strip()
            pub = (it.findtext("pubDate") or "").strip()
            dt = _parse_rfc822_dt(pub)
            if not dt:
                continue
            src_el = it.find("source")
            src = (src_el.text or "").strip() if src_el is not None else ""
            desc = _strip_html((it.findtext("description") or "").strip())

            items.append(
                NewsItem(
                    provider_id="digest",
                    provider_name="AI 소식",
                    source="DIGEST",
                    title=_safe_text(title, 140),
                    url=link,
                    published_at_utc=dt,
                    summary=_safe_text(desc or src, 240),
                    raw_text=f"{title}\n{src}\n{desc}".strip(),
                )
            )
    return items, errs


def _google_news_rss_url(q: str) -> str:
    q = (q or "").strip()
    return (
        "https://news.google.com/rss/search?q="
        + urllib.parse.quote(q)
        + "&hl=en-US&gl=US&ceid=US:en"
    )


def _signal_score(item: NewsItem, hi: List[str], lo: List[str]) -> int:
    text = f"{item.title}\n{item.summary}\n{item.raw_text}".lower()
    score = 0
    for w in hi:
        if w.lower() in text:
            score += 2
    for w in lo:
        if w.lower() in text:
            score -= 2
    # Boost official feed items over digest.
    if item.source in ("X", "RSS", "WEB"):
        score += 1
    return score


def _dedupe(items: Iterable[NewsItem]) -> List[NewsItem]:
    out: List[NewsItem] = []
    seen: set = set()
    for it in items:
        k = it.dedupe_key()
        if k in seen:
            continue
        seen.add(k)
        out.append(it)
    return out


def _load_config() -> Dict:
    return json.loads(CONFIG_FILE.read_text(encoding="utf-8"))


def _render_html(
    *,
    window_hours: int,
    generated_local: datetime,
    cutoff_utc: datetime,
    highlights: List[NewsItem],
    provider_order: List[Tuple[str, str]],
    by_provider: Dict[str, List[NewsItem]],
    x_trending: List[NewsItem],
    digest: List[NewsItem],
    source_health: List[str],
    translations: Dict[str, Dict[str, str]],
    show_original: bool,
) -> str:
    gen_str = generated_local.strftime("%Y-%m-%d %H:%M %Z")
    cutoff_local = cutoff_utc.astimezone().strftime("%Y-%m-%d %H:%M %Z")

    def badge(provider_id: str) -> str:
        pid = provider_id.lower()
        if "openai" in pid:
            return "badge badge-openai"
        if "anthropic" in pid:
            return "badge badge-anthropic"
        if "google" in pid or "deepmind" in pid:
            return "badge badge-google"
        if "digest" in pid:
            return "badge badge-digest"
        return "badge"

    def src_badge(src: str) -> str:
        s = src.upper()
        label = s
        if s == "WEB":
            label = "웹"
        elif s == "DIGEST":
            label = "뉴스"
        cls = "src"
        if s == "X":
            cls += " src-x"
        elif s == "RSS":
            cls += " src-rss"
        elif s == "WEB":
            cls += " src-web"
        else:
            cls += " src-digest"
        return f'<span class="{cls}">{html_lib.escape(label)}</span>'

    def card(it: NewsItem, show_provider: bool = True) -> str:
        tr = translations.get(it.dedupe_key(), {}) if translations else {}
        title_ko = (tr.get("title") or "").strip() or it.title
        summary_ko = (tr.get("summary") or "").strip() or it.summary

        prov = (
            f'<span class="{badge(it.provider_id)}">{html_lib.escape(it.provider_name)}</span>' if show_provider else ""
        )
        title = html_lib.escape(title_ko)
        summary = html_lib.escape(summary_ko)
        t = html_lib.escape(_format_local(it.published_at_utc))
        url = html_lib.escape(it.url)

        meta_html = ""
        if (it.meta or "").strip():
            meta_html = f'<div class="card-meta">{html_lib.escape(it.meta)}</div>'

        orig_block = ""
        if show_original:
            o_title = (it.title or "").strip()
            o_summary = (it.summary or "").strip()
            show_o_title = bool(o_title) and (o_title != title_ko.strip())
            show_o_summary = bool(o_summary) and (o_summary != summary_ko.strip())
            if show_o_title or show_o_summary:
                parts: List[str] = []
                if show_o_title:
                    parts.append(f'<div class="card-orig-line"><span>원문</span> {html_lib.escape(o_title)}</div>')
                if show_o_summary:
                    parts.append(
                        f'<div class="card-orig-line"><span>요약(원문)</span> {html_lib.escape(o_summary)}</div>'
                    )
                orig_block = '<div class="card-orig">' + "".join(parts) + "</div>"

        return f"""
          <a class="card" href="{url}" target="_blank" rel="noreferrer">
            <div class="card-top">
              <div class="card-badges">
                {prov}
                {src_badge(it.source)}
              </div>
              <div class="card-time">{t}</div>
            </div>
            <div class="card-title">{title}</div>
            {meta_html}
            <div class="card-summary">{summary}</div>
            {orig_block}
          </a>
        """

    highlights_html = (
        "\n".join(card(it) for it in highlights)
        if highlights
        else f'<div class="empty">최근 {window_hours}시간 내 중요한 업데이트가 없습니다.</div>'
    )

    providers_html_parts: List[str] = []
    for pid, prov_name in provider_order:
        items = by_provider.get(pid, [])
        x_items = [i for i in items if i.source == "X"]
        rss_items = [i for i in items if i.source == "RSS"]
        web_items = [i for i in items if i.source == "WEB"]

        feed_html = ""
        for group_title, group_items in (
            ("공식 X", x_items),
            ("공식 블로그/뉴스", rss_items + web_items),
        ):
            if not group_items:
                feed_html += f'<div class="feed-block"><div class="feed-h">{html_lib.escape(group_title)}</div><div class="empty small">항목 없음</div></div>'
                continue
            feed_html += f'<div class="feed-block"><div class="feed-h">{html_lib.escape(group_title)}</div><div class="feed">'
            feed_html += "\n".join(card(i, show_provider=False) for i in group_items[:10])
            feed_html += "</div></div>"

        providers_html_parts.append(
            f"""
	            <section class="provider">
	              <div class="provider-h">
	                <div class="provider-title">{html_lib.escape(prov_name)}</div>
	                <div class="provider-sub">최근 {window_hours}시간</div>
	              </div>
	              {feed_html}
	            </section>
            """
        )
    providers_html = "\n".join(providers_html_parts) if providers_html_parts else ""

    digest_html = (
        "\n".join(card(it) for it in digest)
        if digest
        else '<div class="empty">다이제스트 항목이 없습니다.</div>'
    )

    x_trending_html = (
        "\n".join(card(it, show_provider=False) for it in x_trending)
        if x_trending
        else '<div class="empty">트렌딩 항목이 없습니다.</div>'
    )

    health_html = (
        "<ul class=\"health\">"
        + "\n".join(f"<li>{html_lib.escape(x)}</li>" for x in source_health)
        + "</ul>"
        if source_health
        else '<div class="empty small">오류 없음</div>'
    )

    # Inline CSS: modern, high-contrast, clean type. Avoid emoji.
    return f"""<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="color-scheme" content="dark" />
  <title>AI 릴리스 워치 (최근 {window_hours}시간)</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;500;600;700&family=Space+Grotesk:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap');
    :root {{
      --bg0: #070A10;
      --bg1: #0B1020;
      --panel: rgba(255,255,255,.06);
      --panel2: rgba(255,255,255,.035);
      --line: rgba(240,244,255,.12);
      --text: rgba(240,244,255,.92);
      --muted: rgba(240,244,255,.62);
      --muted2: rgba(240,244,255,.46);
      --a: #5BF2C6;
      --b: #5BB6FF;
      --c: #FFD36E;
      --danger: #FF5B7A;
      --shadow: 0 12px 40px rgba(0,0,0,.35);
    }}
    * {{ box-sizing: border-box; }}
    html, body {{ height: 100%; }}
	    body {{
	      margin: 0;
	      color: var(--text);
	      font-family: "Space Grotesk", "Noto Sans KR", ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif;
      background:
        radial-gradient(1200px 800px at 20% 10%, rgba(91,182,255,.18), transparent 60%),
        radial-gradient(900px 700px at 80% 20%, rgba(91,242,198,.14), transparent 62%),
        radial-gradient(1000px 900px at 50% 100%, rgba(255,211,110,.10), transparent 55%),
        linear-gradient(180deg, var(--bg0), var(--bg1));
      overflow-x: hidden;
    }}
    .grid {{
      background-image:
        linear-gradient(to right, rgba(255,255,255,.05) 1px, transparent 1px),
        linear-gradient(to bottom, rgba(255,255,255,.05) 1px, transparent 1px);
      background-size: 56px 56px;
      background-position: center;
      mask-image: radial-gradient(650px 500px at 50% 0%, black 40%, transparent 80%);
      position: fixed;
      inset: 0;
      pointer-events: none;
      opacity: .35;
    }}
    .wrap {{
      max-width: 1120px;
      margin: 0 auto;
      padding: 28px 18px 56px;
      position: relative;
    }}
    header {{
      display: flex;
      gap: 18px;
      justify-content: space-between;
      align-items: flex-end;
      padding: 18px 18px 22px;
      border: 1px solid var(--line);
      background: linear-gradient(180deg, rgba(255,255,255,.075), rgba(255,255,255,.03));
      border-radius: 18px;
      box-shadow: var(--shadow);
      backdrop-filter: blur(10px);
    }}
    .title {{
      font-size: 28px;
      font-weight: 700;
      line-height: 1.1;
      letter-spacing: -0.02em;
    }}
    .subtitle {{
      margin-top: 8px;
      color: var(--muted);
      font-size: 14px;
    }}
    .meta {{
      text-align: right;
      color: var(--muted);
      font-size: 12px;
      font-family: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
    }}
    .meta strong {{
      color: var(--text);
      font-weight: 500;
    }}
    .section {{
      margin-top: 20px;
      border: 1px solid var(--line);
      background: rgba(255,255,255,.04);
      border-radius: 18px;
      overflow: hidden;
      box-shadow: 0 10px 30px rgba(0,0,0,.22);
    }}
    .section-h {{
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      padding: 16px 18px;
      background: rgba(255,255,255,.035);
      border-bottom: 1px solid var(--line);
    }}
    .section-h .h {{
      font-size: 16px;
      font-weight: 700;
      letter-spacing: -0.01em;
    }}
    .section-h .note {{
      font-size: 12px;
      color: var(--muted2);
      font-family: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
    }}
    .cards {{
      display: grid;
      grid-template-columns: repeat(12, 1fr);
      gap: 12px;
      padding: 14px;
    }}
    .cards .card {{
      grid-column: span 6;
    }}
    @media (max-width: 900px) {{
      .cards .card {{ grid-column: span 12; }}
      header {{ flex-direction: column; align-items: flex-start; }}
      .meta {{ text-align: left; }}
    }}
    .card {{
      display: block;
      text-decoration: none;
      color: inherit;
      border: 1px solid rgba(255,255,255,.10);
      background: linear-gradient(180deg, rgba(255,255,255,.06), rgba(255,255,255,.03));
      border-radius: 14px;
      padding: 14px 14px 12px;
      box-shadow: 0 8px 24px rgba(0,0,0,.18);
      transition: transform .18s ease, border-color .18s ease, background .18s ease;
    }}
    .card:hover {{
      transform: translateY(-2px);
      border-color: rgba(255,255,255,.22);
      background: linear-gradient(180deg, rgba(255,255,255,.085), rgba(255,255,255,.035));
    }}
    .card-top {{
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 10px;
      margin-bottom: 10px;
    }}
    .card-badges {{
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;
    }}
    .card-time {{
      color: var(--muted2);
      font-size: 12px;
      font-family: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
      white-space: nowrap;
    }}
    .card-title {{
      font-size: 15px;
      font-weight: 600;
      letter-spacing: -0.01em;
      line-height: 1.3;
      margin-bottom: 8px;
    }}
    .card-meta {{
      margin-bottom: 8px;
      color: var(--muted2);
      font-size: 12px;
      line-height: 1.35;
      font-family: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
    }}
	    .card-summary {{
	      font-size: 13px;
	      color: var(--muted);
	      line-height: 1.45;
	    }}
	    .card-orig {{
	      margin-top: 10px;
	      padding-top: 10px;
	      border-top: 1px dashed rgba(255,255,255,.14);
	      color: var(--muted2);
	      font-size: 12px;
	      line-height: 1.4;
	    }}
	    .card-orig-line {{
	      margin-top: 6px;
	    }}
	    .card-orig-line span {{
	      display: inline-block;
	      min-width: 72px;
	      font-family: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
	      letter-spacing: .04em;
	      color: rgba(240,244,255,.62);
	    }}
	    .badge {{
	      display: inline-flex;
	      align-items: center;
	      padding: 3px 10px;
      border-radius: 999px;
      font-size: 12px;
      background: rgba(255,255,255,.07);
      border: 1px solid rgba(255,255,255,.10);
      color: rgba(240,244,255,.86);
    }}
    .badge-openai {{ border-color: rgba(91,182,255,.35); background: rgba(91,182,255,.12); }}
    .badge-anthropic {{ border-color: rgba(255,211,110,.35); background: rgba(255,211,110,.10); }}
    .badge-google {{ border-color: rgba(91,242,198,.35); background: rgba(91,242,198,.10); }}
    .badge-digest {{ border-color: rgba(255,91,122,.30); background: rgba(255,91,122,.10); }}
    .src {{
      display: inline-flex;
      align-items: center;
      padding: 2px 8px;
      border-radius: 999px;
      font-size: 11px;
      letter-spacing: .06em;
      font-family: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
      border: 1px solid rgba(255,255,255,.14);
      background: rgba(255,255,255,.05);
      color: rgba(240,244,255,.72);
    }}
    .src-x {{ border-color: rgba(91,182,255,.35); color: rgba(91,182,255,.95); }}
    .src-rss {{ border-color: rgba(91,242,198,.35); color: rgba(91,242,198,.95); }}
    .src-web {{ border-color: rgba(255,211,110,.35); color: rgba(255,211,110,.95); }}
    .src-digest {{ border-color: rgba(255,91,122,.35); color: rgba(255,91,122,.95); }}
    .empty {{
      padding: 18px;
      color: var(--muted);
      font-size: 13px;
    }}
    .empty.small {{
      padding: 10px 0;
      color: var(--muted2);
    }}
    .providers {{
      display: grid;
      grid-template-columns: 1fr 1fr 1fr;
      gap: 14px;
      padding: 14px;
    }}
    @media (max-width: 1100px) {{
      .providers {{ grid-template-columns: 1fr; }}
    }}
    .provider {{
      border: 1px solid rgba(255,255,255,.10);
      background: rgba(255,255,255,.03);
      border-radius: 16px;
      overflow: hidden;
    }}
    .provider-h {{
      padding: 14px 14px 10px;
      border-bottom: 1px solid rgba(255,255,255,.10);
      background: rgba(255,255,255,.03);
      display: flex;
      align-items: baseline;
      justify-content: space-between;
    }}
    .provider-title {{
      font-weight: 700;
      letter-spacing: -0.01em;
    }}
    .provider-sub {{
      color: var(--muted2);
      font-size: 12px;
      font-family: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
    }}
    .feed-block {{
      padding: 12px 14px 4px;
    }}
    .feed-h {{
      font-size: 12px;
      letter-spacing: .08em;
      text-transform: uppercase;
      color: var(--muted2);
      margin-bottom: 10px;
      font-family: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
    }}
    .feed {{
      display: grid;
      grid-template-columns: 1fr;
      gap: 10px;
      padding-bottom: 10px;
    }}
    .health {{
      margin: 0;
      padding: 12px 28px 18px;
      color: var(--muted);
      font-size: 13px;
      line-height: 1.4;
    }}
    footer {{
      margin-top: 22px;
      color: var(--muted2);
      font-size: 12px;
      font-family: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
      text-align: center;
      opacity: .9;
    }}
  </style>
</head>
<body>
  <div class="grid"></div>
  <div class="wrap">
	    <header>
	      <div>
	        <div class="title">AI 릴리스 워치</div>
	        <div class="subtitle">OpenAI, Anthropic, Google AI 공식 업데이트. 범위: 최근 {window_hours}시간 (컷오프: {cutoff_local}).</div>
	      </div>
	      <div class="meta">
	        <div><strong>생성</strong> {gen_str}</div>
	        <div><strong>소스</strong> X(Nitter), RSS, 웹, Google News RSS</div>
	      </div>
	    </header>

	    <div class="section">
	      <div class="section-h">
	        <div class="h">하이라이트 (중요 업데이트)</div>
	        <div class="note">키워드 시그널 점수 기준</div>
	      </div>
	      <div class="cards">
	        {highlights_html}
	      </div>
	    </div>

	    <div class="section">
	      <div class="section-h">
	        <div class="h">공식 채널</div>
	        <div class="note">제공사별</div>
	      </div>
	      <div class="providers">
	        {providers_html}
	      </div>
	    </div>

	    <div class="section">
	      <div class="section-h">
	        <div class="h">X 트렌딩 AI</div>
	        <div class="note">Nitter 검색 기반 · 참여도(좋아요/리포스트/댓글) 상위</div>
	      </div>
	      <div class="cards">
	        {x_trending_html}
	      </div>
	    </div>

	    <div class="section">
	      <div class="section-h">
	        <div class="h">AI 소식 정리</div>
	        <div class="note">Google News RSS (쿼리: when:1d)</div>
	      </div>
	      <div class="cards">
	        {digest_html}
	      </div>
	    </div>

	    <div class="section">
	      <div class="section-h">
	        <div class="h">소스 상태</div>
	        <div class="note">가져오기/파싱 오류</div>
	      </div>
	      {health_html}
	    </div>

	    <footer>
	      ai-monitor/ai_agent.py로 생성. 범위: 최근 {window_hours}시간.
	    </footer>
  </div>
</body>
</html>
"""


def _render_markdown(
    *,
    window_hours: int,
    generated_local: datetime,
    cutoff_utc: datetime,
    highlights: List[NewsItem],
    provider_order: List[Tuple[str, str]],
    by_provider: Dict[str, List[NewsItem]],
    x_trending: List[NewsItem],
    digest: List[NewsItem],
    source_health: List[str],
    translations: Dict[str, Dict[str, str]],
    show_original: bool,
) -> str:
    gen_str = generated_local.strftime("%Y-%m-%d %H:%M %Z")
    cutoff_local = cutoff_utc.astimezone().strftime("%Y-%m-%d %H:%M %Z")

    def fmt_item(it: NewsItem) -> str:
        tr = translations.get(it.dedupe_key(), {}) if translations else {}
        title_ko = (tr.get("title") or "").strip() or it.title
        summary_ko = (tr.get("summary") or "").strip() or it.summary

        t = _format_local(it.published_at_utc)
        src = (it.source or "").upper()
        src_label = {"X": "X", "RSS": "RSS", "WEB": "웹", "DIGEST": "뉴스"}.get(src, src)
        lines = [
            f"- [{it.provider_name}][{src_label}] {t} {title_ko}",
            f"  - {it.url}",
        ]
        if (it.meta or "").strip():
            lines.append(f"  - {it.meta}")
        if summary_ko:
            lines.append(f"  - {summary_ko}")
        if show_original:
            o_title = (it.title or "").strip()
            o_summary = (it.summary or "").strip()
            if o_title and o_title != title_ko.strip():
                lines.append(f"  - 원문: {o_title}")
            if o_summary and o_summary != summary_ko.strip():
                lines.append(f"  - 원문 요약: {o_summary}")
        return "\n".join(lines).strip()

    md: List[str] = []
    md.append(f"# AI 릴리스 워치 (최근 {window_hours}시간)")
    md.append("")
    md.append(f"- 생성: {gen_str}")
    md.append(f"- 기준(컷오프): {cutoff_local}")
    md.append("")
    md.append("## 하이라이트")
    md.append("")
    if highlights:
        md.extend(fmt_item(i) for i in highlights)
    else:
        md.append("- (없음)")
    md.append("")
    md.append("## 공식 채널")
    md.append("")
    for pid, name in provider_order:
        items = by_provider.get(pid, [])
        md.append(f"### {name}")
        md.append("")
        if not items:
            md.append(f"- 최근 {window_hours}시간 항목 없음")
            md.append("")
            continue
        for src in ("X", "RSS", "WEB"):
            subset = [i for i in items if i.source == src]
            if not subset:
                continue
            src_label = {"X": "X", "RSS": "RSS", "WEB": "웹"}.get(src, src)
            md.append(f"- {src_label}")
            md.extend(fmt_item(i) for i in subset[:10])
            md.append("")
    md.append("## X 트렌딩 AI")
    md.append("")
    if x_trending:
        md.extend(fmt_item(i) for i in x_trending[:20])
    else:
        md.append("- (없음)")
    md.append("")
    md.append("## AI 소식 정리")
    md.append("")
    if digest:
        md.extend(fmt_item(i) for i in digest[:20])
    else:
        md.append("- (없음)")
    md.append("")
    md.append("## 소스 상태")
    md.append("")
    if source_health:
        md.extend(f"- {x}" for x in source_health)
    else:
        md.append("- 정상")
    md.append("")
    return "\n".join(md) + "\n"


def run(window_hours: int) -> int:
    # Wait for network readiness (Codex sandbox may not have DNS immediately)
    _wait_for_network()

    _ensure_dirs()
    cfg = _load_config()

    timeout_s = int(cfg.get("nitter", {}).get("timeout_seconds", 30))
    max_posts_per_handle = int(cfg.get("nitter", {}).get("max_posts_per_handle", 12))
    instances = cfg.get("nitter", {}).get("instances", [])

    hi_kw = list(cfg.get("keywords", {}).get("high_signal", []))
    lo_kw = list(cfg.get("keywords", {}).get("low_signal", []))

    nitter = NitterClient(instances=instances, timeout_s=timeout_s) if instances else None

    providers = cfg.get("providers", [])
    # Use a single "now" instant to avoid timezone/env skew between local/UTC clocks.
    now_utc = _now_utc()
    generated_local = now_utc.astimezone()
    cutoff_utc = now_utc - timedelta(hours=window_hours)

    digest_cfg = cfg.get("digest", {})
    queries = digest_cfg.get("google_news_rss_queries", []) or []
    max_total = int(digest_cfg.get("max_items_total", 12))

    xtr_cfg = cfg.get("x_trending", {}) or {}
    xtr_enabled = bool(xtr_cfg.get("enabled", False))
    xtr_queries = xtr_cfg.get("queries", []) or []
    xtr_max_posts_per_query = int(xtr_cfg.get("max_posts_per_query", 24))
    xtr_max_items_total = int(xtr_cfg.get("max_items_total", 10))
    xtr_min_score = int(xtr_cfg.get("min_score", 0))

    retry_cfg = cfg.get("run", {}).get("retry_on_total_failure", {}) or {}
    max_attempts = int(retry_cfg.get("max_attempts", 2))
    base_delay_s = float(retry_cfg.get("delay_seconds", 12))
    backoff_mult = float(retry_cfg.get("backoff_multiplier", 2.0))
    max_delay_s = float(retry_cfg.get("max_delay_seconds", 180))
    jitter_s = float(retry_cfg.get("jitter_seconds", 0.0))

    def collect_once() -> Tuple[
        Dict[str, List[NewsItem]],
        List[NewsItem],
        List[NewsItem],
        List[NewsItem],
        List[str],
        int,
        List[Tuple[str, str]],
    ]:
        all_items: List[NewsItem] = []
        source_health: List[str] = []

        by_provider: Dict[str, List[NewsItem]] = {}
        provider_order: List[Tuple[str, str]] = []
        expected_sources: int = 0

        for p in providers:
            pid = (p.get("id") or "").strip()
            pname = (p.get("name") or pid).strip() or pid
            if not pid:
                continue

            provider_order.append((pid, pname))
            if nitter:
                expected_sources += len(p.get("x_handles", []) or [])
            expected_sources += len(p.get("rss", []) or [])
            expected_sources += len(p.get("web", []) or [])

            prov_items: List[NewsItem] = []

            # X via Nitter
            if nitter:
                for handle in p.get("x_handles", []) or []:
                    handle = (handle or "").lstrip("@").strip()
                    if not handle:
                        continue
                    posts, errs = nitter.fetch_posts(handle, max_posts=max_posts_per_handle)
                    if errs:
                        source_health.extend([f"Nitter {handle}: {e}" for e in errs])

                    for it in posts:
                        if it.published_at_utc < cutoff_utc:
                            continue
                        prov_items.append(
                            NewsItem(
                                provider_id=pid,
                                provider_name=pname,
                                source="X",
                                title=it.title,
                                url=it.url,
                                published_at_utc=it.published_at_utc,
                                summary=it.summary,
                                raw_text=it.raw_text,
                            )
                        )

            # RSS feeds
            for rss_url in p.get("rss", []) or []:
                rss_url = (rss_url or "").strip()
                if not rss_url:
                    continue
                parsed, err = _parse_rss(rss_url, timeout_s=timeout_s)
                if err:
                    source_health.append(f"RSS {pid}: {rss_url}: {err}")
                    continue
                for title, link, dt, desc in parsed:
                    if dt < cutoff_utc:
                        continue
                    prov_items.append(
                        NewsItem(
                            provider_id=pid,
                            provider_name=pname,
                            source="RSS",
                            title=_safe_text(title or "(untitled)", 120),
                            url=link,
                            published_at_utc=dt,
                            summary=_safe_text(desc, 260),
                            raw_text=f"{title}\n{desc}".strip(),
                        )
                    )

            # Web sources (Anthropic news page)
            for web_url in p.get("web", []) or []:
                web_url = (web_url or "").strip()
                if not web_url:
                    continue
                if "anthropic.com/news" in web_url:
                    items, errs = _fetch_anthropic_news(web_url, timeout_s=timeout_s)
                    if errs:
                        source_health.extend(errs)
                    for it in items:
                        if it.published_at_utc < cutoff_utc:
                            continue
                        # Force provider id/name to the configured one (grouping)
                        prov_items.append(
                            NewsItem(
                                provider_id=pid,
                                provider_name=pname,
                                source="WEB",
                                title=it.title,
                                url=it.url,
                                published_at_utc=it.published_at_utc,
                                summary=it.summary,
                                raw_text=it.raw_text,
                            )
                        )
                else:
                    source_health.append(f"WEB {pid}: 지원하지 않는 웹 소스: {web_url}")

            prov_items = _dedupe(sorted(prov_items, key=lambda x: x.published_at_utc, reverse=True))
            by_provider[pid] = prov_items
            all_items.extend(prov_items)

        # Digest section (general AI news)
        expected_sources += len(queries)
        digest_items, digest_errs = _fetch_google_news_digest(queries, timeout_s=timeout_s, max_total=max_total)
        if digest_errs:
            source_health.extend(digest_errs)
        digest_items = [i for i in digest_items if i.published_at_utc >= cutoff_utc]
        digest_items = _dedupe(sorted(digest_items, key=lambda x: x.published_at_utc, reverse=True))

        # X trending section (Nitter search + engagement scoring)
        x_trending_items: List[NewsItem] = []
        if xtr_enabled:
            if not nitter:
                source_health.append("X 트렌딩: Nitter 인스턴스가 설정되지 않아 검색을 실행할 수 없습니다.")
            else:
                expected_sources += len([q for q in xtr_queries if (q or '').strip()])
                scored_hits: List[Tuple[NewsItem, int]] = []
                for idx, q in enumerate(xtr_queries, 1):
                    q = (q or "").strip()
                    if not q:
                        continue
                    hits, errs = nitter.search_tweets(q, max_posts=xtr_max_posts_per_query)
                    if errs:
                        preview = _safe_text(q, 42)
                        source_health.extend([f"X 트렌딩 q{idx} ({preview}): {e}" for e in errs])
                        continue
                    for h in hits:
                        if h.published_at_utc < cutoff_utc:
                            continue
                        if not _is_ai_related_text(h.content):
                            continue
                        if _is_low_quality_trending(h.content):
                            continue
                        score = h.score()
                        who = ""
                        if h.fullname and h.username:
                            who = f"{h.fullname} (@{h.username})"
                        elif h.username:
                            who = f"@{h.username}"
                        elif h.fullname:
                            who = h.fullname
                        meta = (
                            (who + " · " if who else "")
                            + f"좋아요 {h.likes} · 리포스트 {h.retweets} · 댓글 {h.replies}"
                        ).strip()
                        scored_hits.append(
                            (
                                NewsItem(
                                    provider_id="x_trending",
                                    provider_name="X 트렌딩 AI",
                                    source="X",
                                    title=_safe_text(h.content.replace("\n", " "), 140),
                                    url=h.url,
                                    published_at_utc=h.published_at_utc,
                                    summary=_safe_text(h.content, 420),
                                    raw_text=h.content,
                                    meta=meta,
                                ),
                                score,
                            )
                        )

                scored_hits.sort(key=lambda x: (x[1], x[0].published_at_utc), reverse=True)
                seen_keys: set = set()
                for it, score in scored_hits:
                    if xtr_min_score and score < xtr_min_score:
                        continue
                    k = it.dedupe_key()
                    if k in seen_keys:
                        continue
                    seen_keys.add(k)
                    x_trending_items.append(it)
                    if len(x_trending_items) >= xtr_max_items_total:
                        break

        return by_provider, all_items, digest_items, x_trending_items, source_health, expected_sources, provider_order

    # Collect with a small retry loop on total failure (common for transient DNS hiccups).
    print(
        f"실행 시작: 최근 {window_hours}시간 수집 (최대 시도 {max(1, max_attempts)}회)",
        flush=True,
    )
    attempts_used = 0
    while True:
        attempts_used += 1
        print(f"[시도 {attempts_used}/{max(1, max_attempts)}] 소스 수집 중...", flush=True)
        by_provider, all_items, digest_items, x_trending_items, source_health, expected_sources, provider_order = (
            collect_once()
        )
        total_items = len(all_items) + len(digest_items) + len(x_trending_items)
        total_failure = total_items == 0 and expected_sources > 0 and len(source_health) >= expected_sources
        print(
            f"[시도 {attempts_used}] 수집 결과: official={len(all_items)}, digest={len(digest_items)}, x_trending={len(x_trending_items)}, warnings={len(source_health)}",
            flush=True,
        )
        if not total_failure or attempts_used >= max(1, max_attempts):
            break
        # Exponential backoff helps when the machine just woke up and DNS/network isn't ready yet.
        delay_s = min(max_delay_s, base_delay_s * (backoff_mult ** max(0, attempts_used - 1)))
        if jitter_s > 0:
            delay_s += random.uniform(0.0, jitter_s)
        print(f"[시도 {attempts_used}] 전체 실패 감지. {delay_s:.1f}초 후 재시도합니다.", flush=True)
        _log(
            f"Total failure (attempt {attempts_used}/{max_attempts}); retrying after {delay_s:.1f}s"
        )
        time.sleep(max(0.0, delay_s))

    total_items = len(all_items) + len(digest_items) + len(x_trending_items)
    total_failure = total_items == 0 and expected_sources > 0 and len(source_health) >= expected_sources

    # (generated_local is set from now_utc above)

    # Highlights: top high-signal across official sources + news digest (official gets a score boost).
    highlight_candidates = _dedupe(all_items + digest_items)
    scored = []
    for it in highlight_candidates:
        scored.append((it, _signal_score(it, hi_kw, lo_kw)))
    scored.sort(key=lambda x: (x[1], x[0].published_at_utc), reverse=True)
    highlights = [it for it, s in scored if s >= 4][:10]

    # Translate titles/summaries for display (best-effort; falls back to original on errors).
    translate_cfg = cfg.get("translate", {}) or {}
    translate_enabled = bool(translate_cfg.get("enabled", True))
    translate_provider = str(translate_cfg.get("provider", "google_gtx"))
    translate_target = str(translate_cfg.get("target_lang", "ko"))
    translate_timeout_s = int(translate_cfg.get("timeout_seconds", 10))
    translate_show_original = bool(translate_cfg.get("show_original", False))

    translations: Dict[str, Dict[str, str]] = {}
    trans_cache_hits = 0
    trans_cache_misses = 0
    trans_errors = 0

    if translate_enabled and (all_items or digest_items or x_trending_items or highlights):
        tcache = _load_translation_cache()
        unique_for_translation = _dedupe(all_items + digest_items + x_trending_items)

        def tr_field(s: str, limit: int) -> str:
            nonlocal trans_cache_hits, trans_cache_misses, trans_errors
            s = (s or "").strip()
            if not s:
                return ""
            if translate_target.lower().startswith("ko") and _looks_korean(s):
                return s
            k = _tcache_key(translate_provider, translate_target, s)
            if k in tcache:
                trans_cache_hits += 1
            else:
                trans_cache_misses += 1
            out, _, err = _translate_text(
                s,
                provider=translate_provider,
                target_lang=translate_target,
                timeout_s=translate_timeout_s,
                cache=tcache,
            )
            if err:
                trans_errors += 1
            return _safe_text(out, limit)

        for it in unique_for_translation:
            translations[it.dedupe_key()] = {
                "title": tr_field(it.title, 160),
                "summary": tr_field(it.summary, 420),
            }

        _save_translation_cache(tcache)

    html_out = _render_html(
        window_hours=window_hours,
        generated_local=generated_local,
        cutoff_utc=cutoff_utc,
        highlights=highlights,
        provider_order=provider_order,
        by_provider=by_provider,
        x_trending=x_trending_items,
        digest=digest_items,
        source_health=source_health[:40],
        translations=translations,
        show_original=translate_show_original,
    )

    md_out = _render_markdown(
        window_hours=window_hours,
        generated_local=generated_local,
        cutoff_utc=cutoff_utc,
        highlights=highlights,
        provider_order=provider_order,
        by_provider=by_provider,
        x_trending=x_trending_items,
        digest=digest_items,
        source_health=source_health[:80],
        translations=translations,
        show_original=translate_show_original,
    )

    ts = generated_local.strftime("%Y%m%d_%H%M")
    report_file = OUTPUT_DIR / f"report_{ts}.html"
    report_md_file = OUTPUT_DIR / f"report_{ts}.md"
    last_run_file = BASE_DIR / "last_run.json"

    report_file.write_text(html_out, encoding="utf-8")
    report_md_file.write_text(md_out, encoding="utf-8")

    dashboard_updated = False
    if not total_failure:
        DASHBOARD_FILE.write_text(html_out, encoding="utf-8")
        DASHBOARD_MD_FILE.write_text(md_out, encoding="utf-8")
        dashboard_updated = True

    last_run = {
        "generated_at_local": generated_local.isoformat(),
        "window_hours": window_hours,
        "cutoff_utc": cutoff_utc.isoformat(),
        "attempts_used": attempts_used,
        "translation": {
            "enabled": translate_enabled,
            "provider": translate_provider,
            "target_lang": translate_target,
            "show_original": translate_show_original,
            "timeout_seconds": translate_timeout_s,
            "cache_file": str(TRANSLATION_CACHE_FILE),
            "cache_hits": trans_cache_hits,
            "cache_misses": trans_cache_misses,
            "errors": trans_errors,
        },
        "dashboard_updated": dashboard_updated,
        "total_failure": total_failure,
        "counts": {
            "official_items": len(all_items),
            "digest_items": len(digest_items),
            "x_trending_items": len(x_trending_items),
            "highlights": len(highlights),
            "source_health_warnings": len(source_health),
            "expected_sources": expected_sources,
        },
        "files": {
            "dashboard_html": str(DASHBOARD_FILE),
            "dashboard_md": str(DASHBOARD_MD_FILE),
            "report_html": str(report_file),
            "report_md": str(report_md_file),
        },
        "source_health": source_health[:120],
    }
    last_run_file.write_text(json.dumps(last_run, ensure_ascii=False, indent=2), encoding="utf-8")

    _log(
        f"Generated {report_file.name} (window_hours={window_hours}, dashboard_updated={dashboard_updated}, total_failure={total_failure})"
    )
    print(f"생성: {report_file}")
    print(f"생성: {report_md_file}")
    if dashboard_updated:
        print(f"생성: {DASHBOARD_FILE}")
        print(f"생성: {DASHBOARD_MD_FILE}")
    else:
        print("대시보드 업데이트 건너뜀(모든 소스 실패). 이전 대시보드를 유지합니다.")
    print(f"생성: {last_run_file}")
    if source_health:
        print(f"소스 상태 경고: {len(source_health)}건 (리포트 참고)")
    return 1 if total_failure else 0


def health(timeout_s: int = 8) -> int:
    """
    Quick network/DNS healthcheck for configured sources.

    Writes: health_last.json
    """
    _ensure_dirs()
    cfg = _load_config()

    generated_local = _now_local()

    providers = cfg.get("providers", []) or []
    nitter_cfg = cfg.get("nitter", {}) or {}
    instances = nitter_cfg.get("instances", []) or []
    digest_cfg = cfg.get("digest", {}) or {}
    queries = digest_cfg.get("google_news_rss_queries", []) or []

    hosts: set = set()
    url_checks: List[Tuple[str, str]] = []

    def add_url(label: str, url: str) -> None:
        u = (url or "").strip()
        if not u:
            return
        url_checks.append((label, u))
        try:
            host = urllib.parse.urlsplit(u).hostname
        except Exception:
            host = None
        if host:
            hosts.add(host)

    for inst in instances:
        try:
            host = urllib.parse.urlsplit((inst or "").strip()).hostname
        except Exception:
            host = None
        if host:
            hosts.add(host)

    for p in providers:
        pid = (p.get("id") or "").strip()
        pname = (p.get("name") or pid).strip() or pid
        for rss_url in p.get("rss", []) or []:
            add_url(f"{pname} RSS", rss_url)
        for web_url in p.get("web", []) or []:
            add_url(f"{pname} 웹", web_url)

    for idx, q in enumerate(queries, 1):
        add_url(f"Google News RSS 쿼리 {idx}", _google_news_rss_url(q))

    # Translation provider health (optional).
    tcfg = cfg.get("translate", {}) or {}
    if bool(tcfg.get("enabled", False)) and str(tcfg.get("provider", "")).strip() == "google_gtx":
        tl = str(tcfg.get("target_lang", "ko"))
        test = "AI news translation healthcheck"
        add_url(
            "번역 API(GTX)",
            "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl="
            + urllib.parse.quote(tl)
            + "&dt=t&q="
            + urllib.parse.quote(test),
        )

    dns_results: Dict[str, Dict] = {}
    for host in sorted(hosts):
        try:
            infos = socket.getaddrinfo(host, 443, proto=socket.IPPROTO_TCP)
            addrs = sorted({i[4][0] for i in infos if i and i[4]})
            dns_results[host] = {"ok": True, "addrs": addrs[:8]}
        except Exception as e:
            dns_results[host] = {"ok": False, "error": f"{type(e).__name__}: {e}"}

    http_results: List[Dict] = []
    for label, url in url_checks:
        status, _, body_b, err = _http_get(url, timeout_s, retries=0)
        ok = status == 200 and bool(body_b)
        http_results.append(
            {
                "label": label,
                "url": url,
                "ok": ok,
                "status": status,
                "error": None if ok else (err or f"HTTP {status}"),
            }
        )

    nitter_results: List[Dict] = []
    if instances:
        nitter = NitterClient(instances=instances, timeout_s=timeout_s)
        for p in providers:
            for handle in p.get("x_handles", []) or []:
                h = (handle or "").lstrip("@").strip()
                if not h:
                    continue
                posts, errs = nitter.fetch_posts(h, max_posts=1)
                ok = bool(posts)
                nitter_results.append(
                    {
                        "handle": h,
                        "ok": ok,
                        "posts_parsed": len(posts),
                        "errors": errs,
                    }
                )

    out = {
        "generated_at_local": generated_local.isoformat(),
        "timeout_seconds": timeout_s,
        "dns": dns_results,
        "http": http_results,
        "nitter": nitter_results,
    }
    HEALTH_FILE.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")

    dns_ok = sum(1 for v in dns_results.values() if v.get("ok"))
    dns_fail = len(dns_results) - dns_ok
    http_ok = sum(1 for v in http_results if v.get("ok"))
    http_fail = len(http_results) - http_ok
    nitter_ok = sum(1 for v in nitter_results if v.get("ok"))
    nitter_fail = len(nitter_results) - nitter_ok

    print(f"헬스체크 완료: {generated_local.strftime('%Y-%m-%d %H:%M %Z')}")
    print(f"- DNS: 성공 {dns_ok} / 실패 {dns_fail} (호스트 {len(dns_results)}개)")
    print(f"- HTTP: 성공 {http_ok} / 실패 {http_fail} (URL {len(http_results)}개)")
    if instances:
        print(f"- Nitter: 성공 {nitter_ok} / 실패 {nitter_fail} (핸들 {len(nitter_results)}개)")
    print(f"저장: {HEALTH_FILE}")

    any_fail = dns_fail > 0 or http_fail > 0 or (instances and nitter_fail > 0)
    if any_fail:
        print("")
        if dns_fail:
            print("DNS 실패:")
            for host, v in sorted(dns_results.items()):
                if not v.get("ok"):
                    print(f"- {host}: {v.get('error')}")
        if http_fail:
            print("HTTP 실패:")
            for v in http_results:
                if not v.get("ok"):
                    print(f"- {v.get('label')}: {v.get('status')} {v.get('error')} ({v.get('url')})")
        if instances and nitter_fail:
            print("Nitter 실패:")
            for v in nitter_results:
                if not v.get("ok"):
                    errs = v.get("errors") or []
                    err_str = errs[0] if errs else "unknown error"
                    print(f"- @{v.get('handle')}: {err_str}")
    return 1 if any_fail else 0


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(prog="ai_agent.py", add_help=True)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_run = sub.add_parser("run", help="Fetch sources and generate report")
    p_run.add_argument("--hours", type=int, default=None, help="Window in hours (default: config.filter.hours)")

    p_health = sub.add_parser("health", help="Healthcheck sources (DNS/HTTP) and write health_last.json")
    p_health.add_argument("--timeout", type=int, default=8, help="Timeout seconds per request (default: 8)")

    args = parser.parse_args(argv)

    if args.cmd == "run":
        cfg = _load_config()
        window_hours = int(args.hours) if args.hours else int(cfg.get("filter", {}).get("hours", 24))
        return run(window_hours=window_hours)

    if args.cmd == "health":
        return health(timeout_s=int(args.timeout))

    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
