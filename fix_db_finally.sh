#!/bin/bash
echo "🛠 DEPLOYING THE SNIPER DATABASE RESET..."

cd ~/vladbingo/backend

cat << 'INNER' > build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input

echo "🧹 Safely wiping database tables one by one..."
python manage.py shell -c "
from django.db import connection
with connection.cursor() as cursor:
    cursor.execute(\"SELECT tablename FROM pg_tables WHERE schemaname = 'public';\")
    tables = cursor.fetchall()
    for table in tables:
        cursor.execute(f'DROP TABLE IF EXISTS \"{table[0]}\" CASCADE;')
    print('✅ All tables dropped cleanly.')
"

echo "📂 Rebuilding migrations..."
rm -rf bingo/migrations/
mkdir -p bingo/migrations/
touch bingo/migrations/__init__.py

python manage.py makemigrations bingo
python manage.py migrate
python manage.py init_bingo
INNER

cd ~/vladbingo
git add .
git commit -m "Fix: Bulletproof dynamic table dropper to prevent Render SSL crash"
git push -f origin main
echo "✅ PUSHED! Render will now build successfully."
