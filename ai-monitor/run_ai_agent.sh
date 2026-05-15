#!/bin/bash

# AI News Brief Collector - ai_agent.py 실행 스크립트

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Python 가상환경 활성화 (있다면)
if [ -d "venv" ]; then
    source venv/bin/activate
fi

# ai_agent.py 실행 (24시간 윈도우)
echo "🤖 AI News 수집 시작... ($(date '+%Y-%m-%d %H:%M:%S'))"

python3 ai_agent.py run --hours 24

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ AI News 수집 완료! ($(date '+%Y-%m-%d %H:%M:%S'))"
else
    echo "❌ AI News 수집 실패 (exit code: $EXIT_CODE)"
fi

exit $EXIT_CODE
