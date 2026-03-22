#!/usr/bin/env bash
# exit on error
set -o errexit

cd backend

# 1. Install dependencies
pip install -r requirements.txt

# 2. Collect static files
python manage.py collectstatic --no-input

# 3. Apply migrations with the FAKE-INITIAL flag
# This tells Django: "If the table exists, just pretend the migration ran."
python manage.py migrate --fake-initial --no-input

# 4. Run the card generator
python manage.py init_bingo || true
