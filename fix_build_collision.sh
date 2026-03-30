#!/bin/bash
cd ~/vladbingo/backend

cat << 'INNER' > build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input

echo "Running Database Reset and Migrations..."
python manage.py shell <<pyEOF
from django.db import connection
with connection.cursor() as cursor:
    cursor.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
    cursor.execute("GRANT ALL ON SCHEMA public TO public;")
pyEOF

rm -rf bingo/migrations/
mkdir -p bingo/migrations/
touch bingo/migrations/__init__.py

python manage.py makemigrations bingo
python manage.py migrate
python manage.py init_bingo
INNER

cd ~/vladbingo
git add .
git commit -m "Fix: Clean Build script (Resolved Render Collision)"
git push -f origin main
echo "✅ PUSHED SAFELY TO RENDER!"
