#!/bin/bash
# VladBingo - Admin Password & Staff Permission Hammer

cat <<'EOF' > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend

# 1. Install & Static
pip install -r requirements.txt
python manage.py collectstatic --no-input

# 2. Database Sync
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input

# 3. THE ADMIN HAMMER (Forces password and staff status)
python manage.py shell <<innerEOF
from bingo.models import User
# We look for the user 'admin'
u, created = User.objects.get_or_create(username='admin')
u.set_password('VladBingoPassword123')
u.is_staff = True
u.is_superuser = True
u.is_active = True
u.save()
print("🔨 Admin Hammer: Account 'admin' forced to 'VladBingoPassword123'")
innerEOF

# 4. Card Init
python manage.py init_bingo || true
EOF

chmod +x backend/build.sh
echo "✅ Admin Hammer logic applied!"
