#!/usr/bin/env bash
set -o errexit

# THE KEY FIX: Move into the backend folder first
cd backend

# 1. Install dependencies
pip install -r requirements.txt

# 2. Collect static files
python manage.py collectstatic --no-input

# 3. Database Sync
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input

# 4. Generate Cards
python manage.py init_bingo || true
