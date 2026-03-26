#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input

# THE DB HAMMER: Ensure 'note' column exists
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    try:
        cursor.execute("ALTER TABLE bingo_transaction ADD COLUMN note text DEFAULT '';")
        print("✅ Added missing note column")
    except:
        print("ℹ️ note column already exists")
innerEOF

python manage.py init_bingo || true
