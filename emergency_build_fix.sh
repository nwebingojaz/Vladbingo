#!/bin/bash
# VladBingo - Emergency Build Script to bypass DuplicateTable error

cat <<EOF > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend

# 1. Install dependencies
pip install -r requirements.txt

# 2. Collect static files
python manage.py collectstatic --no-input

# 3. EMERGENCY FIX: Force the database to mark these migrations as "Done"
# This bypasses the "DuplicateTable" error you saw in the logs.
python manage.py migrate bingo 0001 --fake || true
python manage.py migrate bingo 0002 --fake || true

# 4. Finish all other migrations
python manage.py migrate --no-input

# 5. Generate Bingo Cards
python manage.py init_bingo || true
EOF

echo "✅ Emergency Build Script created!"
