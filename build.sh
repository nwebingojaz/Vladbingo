#!/bin/bash
set -o errexit
cd backend
pip install -r requirements.txt

# NUCLEAR WIPE
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    cursor.execute("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();")
    cursor.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
    cursor.execute("GRANT ALL ON SCHEMA public TO public;")
innerEOF

# STAGE 1: Setup Core Django Tables
python manage.py migrate --no-input

# STAGE 2: Fresh Bingo Migrations
rm -rf bingo/migrations/ && mkdir bingo/migrations/ && touch bingo/migrations/__init__.py
python manage.py makemigrations bingo
python manage.py migrate bingo

python manage.py collectstatic --no-input
python manage.py init_bingo
