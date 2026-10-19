FROM python:3.12-slim
LABEL org.opencontainers.image.source=https://github.com/Ouinon0/clashretro-server
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && useradd --system --uid 10002 portal
COPY app.py cards.json 03_jobs.sql ./
COPY templates templates
USER portal
ENV FLASK_APP=app.py
EXPOSE 8080
# Python en PID 1 ignore SIGTERM : SIGINT déclenche un arrêt propre.
STOPSIGNAL SIGINT
CMD ["waitress-serve", "--port=8080", "--trusted-proxy=*", "--trusted-proxy-headers=x-forwarded-proto x-forwarded-host", "app:app"]
