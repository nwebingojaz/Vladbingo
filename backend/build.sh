#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
# This will now succeed because of the default value
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input
python manage.py init_bingo || true
