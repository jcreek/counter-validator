=========================
Running your own instance
=========================

We recommend using the public instance at `https://validator.countermetrics.org <https://validator.countermetrics.org>`_.

However, if you for some reason want to run your own instance, we have you covered. You will find the necessary information below.

Running from source
-------------------

You can download the source code from `GitHub <https://github.com/Project-Counter/counter-validator>`_ and run it locally.
It is written in Python in combination with Vue for the frontend. It will require some additional setup to get it running, like
creating a database and setting up a virtual environment.

At present, we do not provide any installation instructions, but if you have experience with running Python, and especially Django,
applications, you should be able to figure it out.


Using Docker
------------

The repository ships a `Dockerfile` and `docker-compose.yml` that bring up the
validator and all of its dependencies in a single command.

N.B. The default setup is intended mostly for local experimentation. For a Production deployment, please read the `Production deployment` section.

Prerequisites
~~~~~~~~~~~~~

* Docker 20.10+ with Docker Compose v2 (`docker compose`).
* About 2 GB of free disk space for the built images.
* Outbound network access on the first build (`compose` clones the
  `ubfr/c5tools` repository on the fly).

Quick start
~~~~~~~~~~~

1. Copy the env example and edit at least `SECRET_KEY` and `DB_PASSWORD`:

   .. code-block:: bash

      cp .env.example .env
      $EDITOR .env

2. Build and start the stack:

   .. code-block:: bash

      docker compose up -d

   The ``validator-web`` container runs ``manage.py migrate`` and
   ``manage.py collectstatic`` automatically before starting gunicorn, so the
   database schema is ready as soon as the container is up. Tail the logs to
   watch progress:

   .. code-block:: bash

      docker compose logs -f validator-web

3. Create an admin user. The easiest path is to set
   ``DJANGO_SUPERUSER_EMAIL`` and ``DJANGO_SUPERUSER_PASSWORD`` in ``.env``
   before step 2 — ``validator-web`` auto-creates a superuser (with a
   verified email so it can use the API immediately) on first boot, and
   is a no-op on subsequent boots.

   If you'd rather create it interactively, do that now:

   .. code-block:: bash

      docker compose exec validator-web python manage.py createsuperuser

4. (Optional) Load the COUNTER registry data so the platform picker is
   populated:

   .. code-block:: bash

      docker compose exec validator-web python manage.py download_registry

5. Open http://localhost/ in a browser.

Services
~~~~~~~~

The compose file defines six services on a single bridge network:

* `validator-web` — Django REST API and admin (gunicorn on :8000).
* `validator-worker` — Celery worker consuming `celery,validation` queues.
* `validator-redis` — Redis 7 as the Celery broker.
* `validator-db` — PostgreSQL 16, persisted via the `postgres_data`
  named volume so validation history survives `docker compose down`.
* `c5tools` — the PHP validation engine (`ubfr/c5tools
  <https://github.com/ubfr/c5tools>`_). Built from a pinned upstream tag
  via the `build.context` git URL in `docker-compose.yml`; bump that tag to
  update.
* `validator-frontend` — nginx serving the built Vue SPA on :80 and
  reverse-proxying `/api/*`, `/admin/*`, `/media/*` and `/static/*`
  to `validator-web`.

Production deployment
~~~~~~~~~~~~~~~~~~~~~

For a production instance:

* Generate a strong `SECRET_KEY` and `DB_PASSWORD`; do not commit `.env`.
* Set `ALLOWED_HOSTS` and `CSRF_TRUSTED_ORIGINS` to your real hostname(s).
* Put a TLS-terminating reverse proxy (Caddy, nginx, Cloudflare, etc.) in
  front of `validator-frontend`.
* Configure email settings (`EMAIL_HOST` plus `DEFAULT_FROM_EMAIL`, or
  the `MAILGUN_*` variables for Mailgun) so the registration flow can
  send verification emails.
* Schedule a periodic `docker compose exec validator-web python manage.py
  download_registry` (e.g. via cron on the host) to keep the registry data
  fresh.

Updating to a new version
~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: bash

   git pull
   docker compose build
   docker compose up -d

The ``validator-web`` container applies any new migrations automatically on
startup before gunicorn binds.
