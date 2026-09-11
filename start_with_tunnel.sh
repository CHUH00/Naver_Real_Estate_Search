#!/bin/bash
# 네이버 부동산 매물 수집기 — 백엔드 서버 + Cloudflare Tunnel 동시 실행
#
# 이 스크립트를 실행하면:
#  1. FastAPI 서버가 로컬 8000번 포트에서 실행됩니다.
#  2. cloudflared가 무료 임시 터널을 만들어 외부(아이폰 포함)에서
#     접속 가능한 https 주소를 발급합니다.
#  3. 그 주소를 아이폰 앱의 설정 탭 "서버 주소"에 입력하면 됩니다.
#
# 주의: 이 터미널 창(또는 스크립트)을 닫으면 서버와 터널이 함께 종료되고,
# 다음에 다시 실행하면 URL이 바뀝니다. 계속 같은 주소를 쓰고 싶다면
# 이 스크립트를 백그라운드로 계속 켜두세요 (예: `nohup ./start_with_tunnel.sh &`).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v cloudflared &>/dev/null; then
  echo "❌ cloudflared가 설치되어 있지 않습니다. 아래 명령으로 설치하세요:"
  echo "   brew install cloudflared"
  exit 1
fi

PYTHON=python3
command -v $PYTHON &>/dev/null || PYTHON=python

echo "📦 의존성 확인 중..."
$PYTHON -c "import fastapi" 2>/dev/null || pip3 install fastapi "uvicorn[standard]" --quiet
$PYTHON -c "import openpyxl" 2>/dev/null || pip3 install openpyxl --quiet
$PYTHON -c "import requests" 2>/dev/null || pip3 install requests --quiet
$PYTHON -c "from playwright.sync_api import sync_playwright" 2>/dev/null || {
  pip3 install playwright --quiet
  playwright install chromium
}

echo "🚀 서버 시작 중 (127.0.0.1:8000)..."
$PYTHON -m uvicorn web.main:app --host 127.0.0.1 --port 8000 &
SERVER_PID=$!

cleanup() {
  echo ""
  echo "🛑 종료 중..."
  kill $SERVER_PID 2>/dev/null || true
  exit 0
}
trap cleanup INT TERM

sleep 2

echo "🌐 Cloudflare Tunnel 여는 중..."
echo "   아래 https://xxxx.trycloudflare.com 형태의 주소를 아이폰 앱 설정에 입력하세요."
echo ""
cloudflared tunnel --url http://127.0.0.1:8000

cleanup
