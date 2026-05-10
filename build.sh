#!/usr/bin/env bash
# exit on error
set -o errexit

# Install dependencies
pip install -r backend/requirements.txt

# Go into backend folder
cd backend

# 1. Force create migration files just in case they were missed
python manage.py makemigrations bingo

# 2. Apply the migrations to the new database (CRITICAL STEP)
python manage.py migrate

# 3. Collect static files
python manage.py collectstatic --no-input

# 4. NOW run the init command (After database is ready)
python manage.py init_bingo