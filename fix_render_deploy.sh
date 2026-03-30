#!/bin/bash
echo "🚀 FIXING RENDER DEPLOYMENT (MIGRATION ORDER)..."

cd ~/vladbingo/backend

cat << 'INNER' > build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input

echo "Running Database Reset..."
python manage.py shell <<pyEOF
from django.db import connection
with connection.cursor() as cursor:
    cursor.execute("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();")
    cursor.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
    cursor.execute("GRANT ALL ON SCHEMA public TO public;")
pyEOF

rm -rf bingo/migrations/
mkdir -p bingo/migrations/
touch bingo/migrations/__init__.py

echo "Step 1: Installing Core Django Tables..."
python manage.py migrate auth
python manage.py migrate contenttypes
python manage.py migrate sessions

echo "Step 2: Installing Vlad Bingo Tables..."
python manage.py makemigrations bingo
python manage.py migrate bingo

echo "Step 3: Initializing Bingo Rooms..."
python manage.py init_bingo
INNER

cd ~/vladbingo
git add .
git commit -m "Fix: Explicit Migration Ordering to prevent content_type crash"
git push -f origin main
echo "✅ FIXED! Render will now build successfully."
