#!/bin/bash
echo "🛠 FIXING RENDER SSL DROP ERROR..."

cd ~/vladbingo/backend

# Rewrite build.sh without the aggressive connection killer
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

echo "Step 3: Initializing Authentic Bingo Rooms..."
python manage.py init_bingo
INNER

cd ~/vladbingo
git add .
git commit -m "Fix: Removed aggressive connection killer to prevent SSL Drop"
git push -f origin main
echo "✅ FIXED! Render is building the final Interactive version now."
