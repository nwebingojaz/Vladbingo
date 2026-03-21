#!/usr/bin/env bash
# exit on error
set -o errexit

# Install dependencies
pip install -r backend/requirements.txt

# Create static directory
mkdir -p backend/staticfiles

# Collect static files
python backend/manage.py collectstatic --no-input

# EMERGENCY: Generate the migrations on the server since Termux is broken
python backend/manage.py makemigrations bingo --no-input

# Run migrations
python backend/manage.py migrate --no-input
