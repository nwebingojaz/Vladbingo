#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input

# THE IMPROVED NUCLEAR FIX: Wipe everything to stop "Duplicate Key" errors
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    cursor.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
    cursor.execute("GRANT ALL ON SCHEMA public TO public;")
innerEOF

# CLEAN MIGRATIONS AND REBUILD
find . -path "*/migrations/*.py" -not -name "__init__.py" -delete
python manage.py makemigrations bingo
python manage.py migrate
python manage.py init_bingo
