#!/usr/bin/env python3
"""
Space Stock Brief HTTP Server
stock_feed_inbox.md를 iOS 앱에서 HTTP로 읽을 수 있도록 서빙합니다.

사용법:
  python3 serve_space.py [포트]   (기본: 8766)

엔드포인트:
  GET /inbox.md   → stock_feed_inbox.md 내용 반환
  GET /status     → JSON 상태 정보
"""

import http.server
import json
import os
import sys
from datetime import datetime

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8766
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
INBOX_PATH = os.path.join(SCRIPT_DIR, "stock_feed_inbox.md")


class SpaceHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/inbox.md":
            self.serve_inbox()
        elif self.path == "/status":
            self.serve_status()
        else:
            self.send_error(404, "Not Found")

    def serve_inbox(self):
        if not os.path.exists(INBOX_PATH):
            self.send_error(404, "inbox.md not found")
            return

        with open(INBOX_PATH, "r", encoding="utf-8") as f:
            content = f.read()

        data = content.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/markdown; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def serve_status(self):
        info = {"ok": True, "file": INBOX_PATH}
        if os.path.exists(INBOX_PATH):
            stat = os.stat(INBOX_PATH)
            info["modified"] = datetime.fromtimestamp(stat.st_mtime).isoformat()
            info["size"] = stat.st_size
        else:
            info["ok"] = False
            info["error"] = "file not found"

        data = json.dumps(info, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        ts = datetime.now().strftime("%H:%M:%S")
        print(f"[{ts}] {args[0]}")


if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", PORT), SpaceHandler)
    print(f"🚀 Space Brief server on http://0.0.0.0:{PORT}")
    print(f"   inbox.md: {INBOX_PATH}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n서버 종료")
        server.server_close()
