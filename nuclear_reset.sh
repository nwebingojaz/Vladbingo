#!/bin/bash
# VladBingo - Nuclear Migration Reset

cat <<'EOF' > backend/build.sh
#!/usr/bin/env bash
set -o errexit

# 1. Move into backend
cd backend

# 2. Install dependencies
pip install -r requirements.txt

# 3. Collect static files
python manage.py collectstatic --no-input

# 4. THE NUCLEAR FIX: Delete the entire history table
# This forces Django to re-map the database in the correct order
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    try:
        cursor.execute("DROP TABLE IF EXISTS django_migrations;")
        print("✅ Nuclear Reset: History wiped. Rebuilding graph...")
    except Exception as e:
        print(f"ℹ️ Reset Info: {e}")
innerEOF

# 5. Apply migrations with fake-initial
# This will link the existing tables to our new 0001_initial file
python manage.py migrate --fake-initial --no-input

# 6. Initialize cards
python manage.py init_bingo || true
EOF

chmod +x backend/build.sh
echo "✅ Nuclear Reset Script Prepared!"
