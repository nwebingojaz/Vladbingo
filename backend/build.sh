#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input
# RUN THE FORCE ADMIN COMMAND
python manage.py force_admin
python manage.py init_bingo || true
