#!/usr/bin/env bash
# exit on error
set -o errexit

# Install dependencies
pip install -r backend/requirements.txt

# Create static directory
mkdir -p backend/staticfiles

# Collect static files
python backend/manage.py collectstatic --no-input

# Run migrations (This will now find the files we just pushed)
python backend/manage.py migrate --no-input
