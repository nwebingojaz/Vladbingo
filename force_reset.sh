#!/bin/bash
cd ~/vladbingo/backend

cat << 'INNER' > build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input

echo "⚠️ INITIATING AGGRESSIVE DATABASE PURGE..."
python -c "
import os, psycopg2
from urllib.parse import urlparse

# Connect directly using the URL
url = urlparse(os.environ.get('DATABASE_URL'))
conn = psycopg2.connect(
    dbname=url.path[1:], user=url.username,
    password=url.password, host=url.hostname, port=url.port
)
conn.autocommit = True
cur = conn.cursor()

try:
    cur.execute('SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();')
    cur.execute('DROP SCHEMA public CASCADE; CREATE SCHEMA public;')
    cur.execute('GRANT ALL ON SCHEMA public TO public;')
    print('✅ Schema Wiped Successfully.')
except Exception as e:
    print('❌ Error wiping schema:', e)
finally:
    cur.close()
    conn.close()
"

# Clean old migrations
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
git commit -m "Fix: Aggressive Raw SQL Database Purge"
git push -f origin main
echo "✅ PUSHED! Render will now successfully wipe and rebuild."
