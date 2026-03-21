#!/usr/bin/env bash
# exit on error
set -o errexit

# 1. Move into the backend directory where requirements.txt and manage.py are
cd backend

# 2. Install dependencies
pip install -r requirements.txt

# 3. Collect static files
python manage.py collectstatic --no-input

# 4. Generate migrations
python manage.py makemigrations bingo --no-input

# 5. Run migrations
python manage.py migrate --no-input
