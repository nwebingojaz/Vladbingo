#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
# We skip makemigrations here because we created the file manually
python manage.py migrate --no-input
python manage.py init_bingo || true
