#!/usr/bin/env bash
set -o errexit

# Install dependencies (Already happened, but good to have)
pip install -r backend/requirements.txt

# Run migrations to create the tables in the new Postgres DB
cd backend
python manage.py collectstatic --no-input
python manage.py migrate

# Initialize the game rooms and cards
python manage.py init_bingo