#!/usr/bin/env bash
# Entrypoint for the validator-web container.
#
#   1. Apply database migrations.
#   2. Collect Django/DRF static assets into the shared /app/static volume
#      so the nginx frontend can serve /static/*.
#   3. If DJANGO_SUPERUSER_EMAIL and DJANGO_SUPERUSER_PASSWORD are both set,
#      idempotently create (or find) a superuser with a verified email so the
#      operator can sign in without running `manage.py createsuperuser` by
#      hand. Re-running with the same values is a no-op.
#   4. Hand off to gunicorn.

set -euo pipefail

python manage.py migrate --noinput
python manage.py collectstatic --noinput

if [ -n "${DJANGO_SUPERUSER_EMAIL:-}" ] && [ -n "${DJANGO_SUPERUSER_PASSWORD:-}" ]; then
    python manage.py shell <<'PYEOF'
import os
from django.contrib.auth import get_user_model
from allauth.account.models import EmailAddress

email = os.environ["DJANGO_SUPERUSER_EMAIL"]
password = os.environ["DJANGO_SUPERUSER_PASSWORD"]

User = get_user_model()
user, created = User.objects.get_or_create(
    email=email,
    defaults={"is_active": True, "is_superuser": True, "is_staff": True},
)
if created:
    user.set_password(password)
    user.save()
    EmailAddress.objects.get_or_create(
        user=user,
        email=email,
        defaults={"verified": True, "primary": True},
    )
    print(f"[web-entrypoint] Created superuser: {email}")
else:
    # Make sure an existing user is still flagged as superuser+staff with
    # a verified email, but don't reset their password.
    dirty = False
    if not user.is_superuser:
        user.is_superuser = True
        dirty = True
    if not user.is_staff:
        user.is_staff = True
        dirty = True
    if dirty:
        user.save()
    EmailAddress.objects.get_or_create(
        user=user,
        email=email,
        defaults={"verified": True, "primary": True},
    )
    print(f"[web-entrypoint] Superuser already exists: {email}")
PYEOF
fi

exec gunicorn config.wsgi:application \
    --bind 0.0.0.0:8000 \
    --workers 2 \
    --access-logfile -
