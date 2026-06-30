FROM python:3.12-slim

WORKDIR /app

# System deps for Playwright
RUN apt-get update && apt-get install -y \
    wget curl gnupg ca-certificates \
    libglib2.0-0 libnss3 libnspr4 libdbus-1-3 \
    libatk1.0-0 libatk-bridge2.0-0 libcups2 \
    libdrm2 libxcb1 libxkbcommon0 libx11-6 libxcomposite1 \
    libxdamage1 libxext6 libxfixes3 libxrandr2 libgbm1 \
    libasound2 libpango-1.0-0 libcairo2 \
    && rm -rf /var/lib/apt/lists/*

# Python deps
COPY requirements.txt .
RUN pip install --no-cache-dir fastapi uvicorn[standard] playwright requests openpyxl

# Playwright browser (chromium only)
RUN playwright install chromium --with-deps

# App files
COPY naver_land_scraper.py .
COPY web/ ./web/

# Data dir
RUN mkdir -p /data

ENV PYTHONUNBUFFERED=1
ENV DATA_DIR=/data
EXPOSE 8080

CMD ["uvicorn", "web.main:app", "--host", "0.0.0.0", "--port", "8080"]
