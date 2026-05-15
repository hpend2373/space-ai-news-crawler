#!/usr/bin/env python3
"""
dashboard.md HTTP 서버
iOS 앱에서 dashboard.md를 읽기 위한 간단한 HTTP 서버입니다.

사용법:
    python3 serve_dashboard.py [포트]

기본 포트: 8765
"""

import http.server
import os
import sys
import json
from datetime import datetime

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
DASHBOARD_DIR = os.path.dirname(os.path.abspath(__file__))
DASHBOARD_FILE = os.path.join(DASHBOARD_DIR, "dashboard.md")


class DashboardHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/dashboard.md" or self.path == "/":
            self._serve_dashboard()
        elif self.path == "/status":
            self._serve_status()
        else:
            self.send_error(404)

    def _serve_dashboard(self):
        try:
            with open(DASHBOARD_FILE, "r", encoding="utf-8") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/markdown; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(content.encode("utf-8"))
        except FileNotFoundError:
            self.send_error(404, "dashboard.md not found")

    def _serve_status(self):
        exists = os.path.exists(DASHBOARD_FILE)
        mtime = os.path.getmtime(DASHBOARD_FILE) if exists else 0
        status = {
            "ok": exists,
            "file": DASHBOARD_FILE,
            "modified": datetime.fromtimestamp(mtime).isoformat() if exists else None,
            "size": os.path.getsize(DASHBOARD_FILE) if exists else 0,
        }
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(status, ensure_ascii=False).encode("utf-8"))

    def log_message(self, format, *args):
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"[{timestamp}] {args[0]}")


if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", PORT), DashboardHandler)
    print(f"📡 Dashboard 서버 시작: http://0.0.0.0:{PORT}")
    print(f"   파일 경로: {DASHBOARD_FILE}")
    print(f"   엔드포인트:")
    print(f"     GET /dashboard.md  - 대시보드 마크다운")
    print(f"     GET /status        - 서버 상태 JSON")
    print(f"   Ctrl+C 로 종료")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n서버 종료")
        server.server_close()
