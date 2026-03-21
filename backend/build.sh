#!/usr/bin/env bash
# exit on error
set -o errexit

# Install dependencies
pip install -r backend/requirements.txt

# Collect static files
python backend/manage.py collectstatic --no-input

# Check if migrations need to be created (Safety check)
python backend/manage.py makemigrations --no-input

# Run migrations
python backend/manage.py migrate --no-input
