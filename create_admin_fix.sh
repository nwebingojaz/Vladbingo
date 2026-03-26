#!/bin/bash
# VladBingo - Auto Admin Creator

# 1. Create a management command that doesn't ask questions
mkdir -p backend/bingo/management/commands
cat <<EOF > backend/bingo/management/commands/force_admin.py
from django.core.management.base import BaseCommand
from bingo.models import User
import os

class Command(BaseCommand):
    def handle(self, *args, **options):
        username = "admin"
        password = "VladBingoPassword123" # You can change this later in Admin
        if not User.objects.filter(username=username).exists():
            User.objects.create_superuser(username=username, password=password, email="admin@vlad.com")
            self.stdout.write("✅ Admin Created: User: admin / Pass: VladBingoPassword123")
        else:
            self.stdout.write("ℹ️ Admin already exists.")
EOF

# 2. Update build.sh to run this command
cat <<'EOF' > backend/build.sh
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
EOF

echo "✅ Auto-Admin logic applied!"
