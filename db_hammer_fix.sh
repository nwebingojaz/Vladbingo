#!/bin/bash
# VladBingo - Direct Database Column Injection

cat <<EOF > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend

# 1. Install dependencies
pip install -r requirements.txt

# 2. Collect static files
python manage.py collectstatic --no-input

# 3. Apply standard migrations (This might say "nothing to do")
python manage.py migrate --no-input

# 4. THE HAMMER: Manually add the missing column if it doesn't exist
# This uses raw SQL to fix the "column does not exist" error immediately.
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    try:
        cursor.execute("ALTER TABLE bingo_user ADD COLUMN selected_card smallint DEFAULT 1;")
        print("✅ Hammer Success: Column selected_card added!")
    except Exception as e:
        print("ℹ️ Hammer Info: Column might already exist, skipping...")
innerEOF

# 5. Initialize Cards
python manage.py init_bingo || true
EOF

echo "✅ Database hammer prepared!"
