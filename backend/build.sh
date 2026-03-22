#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input

# FORCE migration creation on the server
python manage.py makemigrations --no-input
python manage.py makemigrations bingo --no-input

# APPLY migrations
python manage.py migrate --no-input

# Now run the generator
python manage.py init_bingo
