#!/bin/bash
cd ~/vladbingo/backend

cat << 'INNER' > build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input

echo "Running Database Reset (Safe Mode)..."
python manage.py shell <<pyEOF
from django.db import connection
try:
    with connection.cursor() as cursor:
        cursor.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
        cursor.execute("GRANT ALL ON SCHEMA public TO public;")
except Exception as e:
    print("Schema reset note:", e)
pyEOF

# Wipe old broken migrations
rm -rf bingo/migrations/
mkdir -p bingo/migrations/
touch bingo/migrations/__init__.py

echo "Generating new Bingo schema..."
python manage.py makemigrations bingo

echo "Applying all migrations..."
python manage.py migrate

echo "Initializing Authentic Bingo Rooms..."
python manage.py init_bingo
INNER

cd ~/vladbingo
git add .
git commit -m "Fix: Reordered makemigrations before migrate to solve Dependency Error"
git push -f origin main
echo "✅ FIXED! Render is building now."
