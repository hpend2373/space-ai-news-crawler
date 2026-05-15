#!/bin/bash

# Brief 앱 설정 자동화 스크립트

echo "🚀 Brief 앱 설정을 시작합니다..."

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 경로 정의
STOCK_DIR="/Users/minyeop/ai app/stock-space-brief"
AI_DIR="/Users/minyeop/ai app/ai-news-brief"

echo ""
echo "📁 프로젝트 디렉토리 확인 중..."

# Stock + Space Brief 디렉토리 확인
if [ -d "$STOCK_DIR" ]; then
    echo -e "${GREEN}✓${NC} Stock + Space Brief: $STOCK_DIR"
else
    echo -e "${RED}✗${NC} Stock + Space Brief 디렉토리 없음: $STOCK_DIR"
    echo "   → 디렉토리를 만들거나 BriefPaths.root 경로를 수정하세요"
fi

# AI News Brief 디렉토리 확인
if [ -d "$AI_DIR" ]; then
    echo -e "${GREEN}✓${NC} AI News Brief: $AI_DIR"
else
    echo -e "${YELLOW}!${NC} AI News Brief 디렉토리 없음: $AI_DIR"
    echo "   → 디렉토리를 만들겠습니다..."
    mkdir -p "$AI_DIR"
    echo -e "${GREEN}✓${NC} 디렉토리 생성 완료"
fi

echo ""
echo "📝 스크립트 파일 확인 중..."

# Stock + Space 스크립트
STOCK_SCRIPT="$STOCK_DIR/run_space_stock_collector.sh"
if [ -f "$STOCK_SCRIPT" ]; then
    echo -e "${GREEN}✓${NC} Stock 스크립트 존재: $STOCK_SCRIPT"
    
    # 실행 권한 확인
    if [ -x "$STOCK_SCRIPT" ]; then
        echo -e "${GREEN}✓${NC} 실행 권한 있음"
    else
        echo -e "${YELLOW}!${NC} 실행 권한 부여 중..."
        chmod +x "$STOCK_SCRIPT"
        echo -e "${GREEN}✓${NC} 권한 부여 완료"
    fi
else
    echo -e "${RED}✗${NC} Stock 스크립트 없음: $STOCK_SCRIPT"
fi

# AI News 스크립트
AI_SCRIPT="$AI_DIR/run_ai_agent.sh"
if [ -f "$AI_SCRIPT" ]; then
    echo -e "${GREEN}✓${NC} AI News 스크립트 존재: $AI_SCRIPT"
    
    # 실행 권한 확인
    if [ -x "$AI_SCRIPT" ]; then
        echo -e "${GREEN}✓${NC} 실행 권한 있음"
    else
        echo -e "${YELLOW}!${NC} 실행 권한 부여 중..."
        chmod +x "$AI_SCRIPT"
        echo -e "${GREEN}✓${NC} 권한 부여 완료"
    fi
else
    echo -e "${YELLOW}!${NC} AI News 스크립트 없음: $AI_SCRIPT"
    echo "   → run_ai_agent.sh를 생성하겠습니다..."
    
    cat > "$AI_SCRIPT" << 'EOF'
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
EOF
    
    chmod +x "$AI_SCRIPT"
    echo -e "${GREEN}✓${NC} 스크립트 생성 및 권한 부여 완료"
fi

echo ""
echo "🐍 Python 환경 확인 중..."

# Python 버전 확인
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    echo -e "${GREEN}✓${NC} Python 설치됨: $PYTHON_VERSION"
else
    echo -e "${RED}✗${NC} Python3가 설치되어 있지 않습니다"
    echo "   → https://www.python.org/downloads/ 에서 Python을 설치하세요"
fi

# Ollama 확인
echo ""
echo "🧠 Ollama 확인 중..."

if command -v ollama &> /dev/null; then
    echo -e "${GREEN}✓${NC} Ollama 설치됨"
    
    # qwen3:8b 모델 확인
    if ollama list | grep -q "qwen3:8b"; then
        echo -e "${GREEN}✓${NC} qwen3:8b 모델 설치됨"
    else
        echo -e "${YELLOW}!${NC} qwen3:8b 모델 없음"
        echo "   → 설치하시겠습니까? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            ollama pull qwen3:8b
        fi
    fi
else
    echo -e "${YELLOW}!${NC} Ollama가 설치되어 있지 않습니다 (번역 기능 사용 불가)"
    echo "   → https://ollama.ai 에서 Ollama를 설치하세요"
fi

echo ""
echo "📦 필요한 파일 확인 중..."

# Stock + Space 파일들
declare -a STOCK_FILES=(
    "space_stock_brief.py"
    "stock_feed_inbox.md"
)

for file in "${STOCK_FILES[@]}"; do
    if [ -f "$STOCK_DIR/$file" ]; then
        echo -e "${GREEN}✓${NC} $file"
    else
        echo -e "${YELLOW}!${NC} $file (수집 후 생성됨)"
    fi
done

# AI News 파일들
declare -a AI_FILES=(
    "ai_agent.py"
    "dashboard.md"
    "config.json"
)

for file in "${AI_FILES[@]}"; do
    if [ -f "$AI_DIR/$file" ]; then
        echo -e "${GREEN}✓${NC} $file"
    else
        echo -e "${YELLOW}!${NC} $file (필요 시 생성 필요)"
    fi
done

echo ""
echo "✅ 설정 확인 완료!"
echo ""
echo "📱 다음 단계:"
echo "1. Xcode에서 프로젝트 열기"
echo "2. Product → Build (⌘B)"
echo "3. Product → Run (⌘R)"
echo "4. 앱 실행 → 모드 선택 → 폴더 접근 허용"
echo "5. '정보 수집' 버튼 클릭"
echo ""
echo "🔗 도움말: README_INTEGRATION.md 참고"
