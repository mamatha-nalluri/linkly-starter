FROM python:3.12-slim-bookworm
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir --no-compile -r requirements.txt && groupadd --gid 10001 app && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app && mkdir -p /app/reports && chown -R 10001:10001 /app
COPY --chown=10001:10001 worker.py healthcheck.py ./
USER 10001:10001
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 CMD ["python","healthcheck.py"]
CMD ["python","worker.py"]
