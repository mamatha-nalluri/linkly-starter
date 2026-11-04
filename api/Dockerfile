FROM python:3.12-slim-bookworm
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir --no-compile -r requirements.txt && groupadd --gid 10001 app && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app
COPY --chown=10001:10001 app.py healthcheck.py ./
USER 10001:10001
EXPOSE 5000
HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=5 CMD ["python","healthcheck.py"]
CMD ["gunicorn","--bind","0.0.0.0:5000","--worker-tmp-dir","/tmp","app:app"]
