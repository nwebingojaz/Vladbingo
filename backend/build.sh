#!/bin/bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input

# THE NUCLEAR KILLER: Kick off all Background Workers so we can wipe the DB
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    # Terminate all other connections to this database
    cursor.execute("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();")
    # Now safe to drop
    cursor.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
    cursor.execute("GRANT ALL ON SCHEMA public TO public;")
innerEOF

find . -path "*/migrations/*.py" -not -name "__init__.py" -delete
python manage.py makemigrations bingo
python manage.py migrate
python manage.py init_bingo
