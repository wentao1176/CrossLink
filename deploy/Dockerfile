FROM python:3.12-slim
WORKDIR /app
COPY server/requirements.lock /app/requirements.lock
RUN pip install --no-cache-dir -r requirements.lock && useradd --system --uid 10001 crosslink && mkdir -p /data/files && chown crosslink /data/files
COPY server/app /app/app
USER crosslink
ENV PYTHONDONTWRITEBYTECODE=1 FILE_STORAGE_PATH=/data/files
EXPOSE 8000
CMD ["uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--ws-max-size", "262144", "--no-access-log"]
