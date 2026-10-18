# ---------- stage 1: bouwen ----------
FROM python:3.14-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1

COPY requirements.txt .
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq5 \
 && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir --no-compile --prefix=/install -r requirements.txt

# ---------- stage 2: draaien ----------
FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1
WORKDIR /app

RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq5 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /install /usr/local

RUN useradd --create-home --uid 10001 appuser \
 && mkdir -p /data \
 && chown appuser:appuser /data

COPY --chown=appuser:appuser . .

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status==200 else 1)"]

CMD ["python", "app.py"]