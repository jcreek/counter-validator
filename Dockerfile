# Multi-stage Dockerfile for the COUNTER Validator self-hosting stack.
#
# Build targets:
#   web      Django + gunicorn (REST API + admin), exposes :8000
#   worker   Celery worker consuming `celery,validation` queues
#   frontend nginx serving the Vue SPA and reverse-proxying the Django app
#
# Built and orchestrated by docker-compose.yml at the repo root. To build a single
# target manually:
#   docker build --target web      -t counter-validator-web      .
#   docker build --target worker   -t counter-validator-worker   .
#   docker build --target frontend -t counter-validator-frontend .

# ---------- frontend-build: produce /frontend/dist ----------
FROM node:24-alpine AS frontend-build
WORKDIR /frontend
# .yarnrc.yml sets `nodeLinker: node-modules` for this project; it must be
# present before `yarn install` so the right linker mode is picked.
COPY frontend/.yarnrc.yml frontend/package.json frontend/yarn.lock ./
RUN corepack enable && yarn install --immutable
COPY frontend/ ./
RUN yarn build

# ---------- python-base: shared layer for web and worker ----------
FROM python:3.12 AS python-base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    POETRY_VIRTUALENVS_CREATE=false \
    POETRY_NO_INTERACTION=1
RUN apt-get update && apt-get install -y --no-install-recommends \
        libmagic1 \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir "poetry==1.8.*"
WORKDIR /app

# Install Python deps first for cache friendliness.
COPY pyproject.toml poetry.lock ./
RUN poetry install --no-root --without dev

# Copy the application source.
COPY manage.py ./
# Served at runtime by apps/core/changelog.py (reads BASE_DIR / "CHANGELOG.md").
COPY CHANGELOG.md ./
COPY apps/   ./apps/
COPY config/ ./config/
COPY tools/  ./tools/

# ---------- web: Django + gunicorn ----------
FROM python-base AS web
RUN pip install --no-cache-dir gunicorn
COPY docker/web-entrypoint.sh /usr/local/bin/web-entrypoint.sh
# Strip any CR so the shebang works even when the host checked the script out
# with CRLF line endings (Windows + core.autocrlf), then make it executable.
RUN sed -i 's/\r$//' /usr/local/bin/web-entrypoint.sh \
    && chmod +x /usr/local/bin/web-entrypoint.sh
ENV DJANGO_SETTINGS_MODULE=config.settings.production \
    STATIC_ROOT=/app/static
EXPOSE 8000
# Migrate + collectstatic + (optional) auto-create superuser from
# DJANGO_SUPERUSER_* env, then gunicorn. See docker/web-entrypoint.sh.
CMD ["/usr/local/bin/web-entrypoint.sh"]

# ---------- worker: Celery ----------
FROM python-base AS worker
ENV DJANGO_SETTINGS_MODULE=config.settings.production
CMD ["celery", "-A", "config", "worker", "-c", "2", "-Q", "celery,validation", "-l", "INFO"]

# ---------- frontend: nginx + Vue SPA ----------
FROM nginx:alpine AS frontend
COPY --from=frontend-build /frontend/dist /usr/share/nginx/html
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
