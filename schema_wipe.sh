#!/bin/bash
# VladBingo - Total Schema Wipe & Fresh Start

# 1. Update build.sh with the Nuclear Wipe Command
cat <<'EOF' > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend

# Install dependencies
pip install -r requirements.txt
python manage.py collectstatic --no-input

# THE NUCLEAR WIPE: Drop the whole schema and recreate it
# This kills all "Ghost Columns" and "Duplicate Tables" errors
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    cursor.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
    print("✅ Database Wiped Clean. Starting fresh build...")
innerEOF

# Apply all migrations from zero
python manage.py migrate --no-input

# Re-initialize the 100 Bingo Cards
python manage.py init_bingo || true
EOF

chmod +x backend/build.sh
echo "✅ Schema Wipe Script Prepared!"
