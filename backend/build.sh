#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input
python manage.py shell -c "from bingo.models import User; User.objects.get_or_create(username='admin', defaults={'is_staff':True, 'is_superuser':True, 'is_active':True})"
python manage.py init_bingo || true
