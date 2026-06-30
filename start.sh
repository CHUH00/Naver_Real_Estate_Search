#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Python 명령어 찾기
if command -v python3 &>/dev/null; then
  PYTHON=python3
elif command -v python &>/dev/null; then
  PYTHON=python
else
  echo "❌ Python이 설치되어 있지 않습니다."
  exit 1
fi

# 의존성 확인 및 설치
echo "📦 의존성 확인 중..."
$PYTHON -c "import fastapi" 2>/dev/null || { echo "  fastapi 설치 중..."; pip3 install fastapi uvicorn[standard] --quiet; }
$PYTHON -c "import uvicorn" 2>/dev/null || pip3 install "uvicorn[standard]" --quiet
$PYTHON -c "import openpyxl" 2>/dev/null || pip3 install openpyxl --quiet
$PYTHON -c "import requests" 2>/dev/null || pip3 install requests --quiet
$PYTHON -c "from playwright.sync_api import sync_playwright" 2>/dev/null || {
  echo "  playwright 설치 중..."
  pip3 install playwright --quiet
  playwright install chromium
}

echo ""
echo "🚀 서버 시작 중..."
echo "   http://localhost:8000 에서 열립니다"
echo ""

# 브라우저 자동 열기 (3초 후)
(sleep 3 && open "http://localhost:8000" 2>/dev/null || xdg-open "http://localhost:8000" 2>/dev/null || true) &

# 서버 실행
cd "$SCRIPT_DIR"
$PYTHON -m uvicorn web.main:app --host 0.0.0.0 --port 8000 --reload
