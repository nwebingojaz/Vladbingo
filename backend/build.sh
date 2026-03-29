#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input

# THE NUCLEAR FIX: DROP OLD TABLES TO STOP DUPLICATE ERROR
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    cursor.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
innerEOF

# FRESH MIGRATIONS
rm -f bingo/migrations/00*.py
python manage.py makemigrations bingo
python manage.py migrate
python manage.py init_bingo
