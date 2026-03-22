#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py makemigrations --no-input
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input
# This creates cards only if the table exists and is empty
python manage.py init_bingo || true
