#!/bin/bash
# VladBingo - Force Admin Password Reset

# 1. Update the build script to be extremely aggressive about creating the admin
cat <<'EOF' > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input

# THE KEY FIX: Force Create/Update the Admin account
python manage.py shell <<innerEOF
from bingo.models import User
username = 'admin'
password = 'VladBingoPassword123'
email = 'bababingo22@gmail.com'

user, created = User.objects.get_or_create(username=username)
user.set_password(password)
user.is_staff = True
user.is_superuser = True
user.email = email
user.save()

if created:
    print(f"✅ Created new admin: {username}")
else:
    print(f"✅ Updated existing admin: {username}")
innerEOF

python manage.py init_bingo || true
EOF

echo "✅ Admin reset logic prepared!"
