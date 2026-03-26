#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input

# THE NUCLEAR FIX: Clear old migration history for bingo ONLY
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    try:
        cursor.execute("DELETE FROM django_migrations WHERE app='bingo';")
        print("✅ Cleared bingo migration history")
    except:
        pass
innerEOF

# Apply the new master migration
python manage.py migrate --fake-initial --no-input
python manage.py init_bingo || true
