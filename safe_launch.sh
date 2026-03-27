#!/bin/bash
# VladBingo - Safe Production Launch (Persistent Data)

# 1. Update build.sh (Removed the Wipe command)
cat <<'EOF' > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input

# Standard Migrations (SAFE: Does not delete data)
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input

# Ensure Admin exists with your specific password
python manage.py shell <<innerEOF
from bingo.models import User
u, created = User.objects.get_or_create(username='admin')
if created:
    u.set_password('VladBingoPassword123')
    u.is_staff = True
    u.is_superuser = True
    u.is_active = True
    u.save()
    print("✅ Admin created")
else:
    print("ℹ️ Admin already exists, data preserved")
innerEOF

# Initialize cards only if empty
python manage.py init_bingo || true
EOF

chmod +x backend/build.sh
echo "✅ Safe Launch script prepared!"
