#!/usr/bin/env bash
set -o errexit

# 1. Install dependencies
pip install -r requirements.txt

# 2. Collect static files (CSS/Images/Audio)
python manage.py collectstatic --no-input

# 3. Database Sync (The final word on migrations)
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input

# 4. Generate Cards (Only if empty)
python manage.py init_bingo || true
