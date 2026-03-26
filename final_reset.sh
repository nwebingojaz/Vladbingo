#!/bin/bash
# VladBingo - Final System Reset & Synchronization

# 1. Wipe old migrations (Keep the folder clean)
rm -rf backend/bingo/migrations/*
touch backend/bingo/migrations/__init__.py

# 2. CREATE MASTER MIGRATION (0001_initial.py)
cat <<'EOF' > backend/bingo/migrations/0001_initial.py
from django.db import migrations, models
import django.utils.timezone
from django.conf import settings

class Migration(migrations.Migration):
    initial = True
    dependencies = [('auth', '0012_alter_user_first_name_max_length')]
    operations = [
        migrations.CreateModel(
            name='User',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('password', models.CharField(max_length=128, verbose_name='password')),
                ('last_login', models.DateTimeField(blank=True, null=True, verbose_name='last login')),
                ('is_superuser', models.BooleanField(default=False)),
                ('username', models.CharField(max_length=150, unique=True)),
                ('first_name', models.CharField(blank=True, max_length=150)),
                ('last_name', models.CharField(blank=True, max_length=150)),
                ('email', models.EmailField(blank=True, max_length=254)),
                ('is_staff', models.BooleanField(default=False)),
                ('is_active', models.BooleanField(default=True)),
                ('date_joined', models.DateTimeField(default=django.utils.timezone.now)),
                ('operational_credit', models.DecimalField(decimal_places=2, default=0, max_digits=12)),
                ('selected_cards', models.JSONField(default=list)),
                ('bot_state', models.CharField(default='IDLE', max_length=20)),
                ('groups', models.ManyToManyField(blank=True, related_name='user_set', related_query_name='user', to='auth.group')),
                ('user_permissions', models.ManyToManyField(blank=True, related_name='user_set', related_query_name='user', to='auth.permission')),
            ],
            options={'verbose_name': 'user', 'verbose_name_plural': 'users', 'abstract': False},
        ),
        migrations.CreateModel(
            name='PermanentCard',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('card_number', models.PositiveSmallIntegerField(unique=True)),
                ('board', models.JSONField()),
            ],
        ),
        migrations.CreateModel(
            name='GameRound',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('created_at', models.DateTimeField(default=django.utils.timezone.now)),
                ('called_numbers', models.JSONField(default=list)),
                ('players', models.JSONField(default=dict)),
                ('bet_amount', models.DecimalField(decimal_places=2, default=20, max_digits=10)),
                ('status', models.CharField(default='LOBBY', max_length=20)),
            ],
        ),
        migrations.CreateModel(
            name='Transaction',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('timestamp', models.DateTimeField(default=django.utils.timezone.now)),
                ('amount', models.DecimalField(decimal_places=2, default=0, max_digits=12)),
                ('type', models.CharField(default='DEPOSIT', max_length=20)),
                ('note', models.TextField(default='')),
                ('agent', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to=settings.AUTH_USER_MODEL)),
            ],
        ),
    ]
EOF

# 3. Update build.sh (The "Force Reset" Command)
cat <<'EOF' > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input

# THE NUCLEAR FIX: Clear old migration history for bingo ONLY
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    try:
        cursor.execute("DELETE FROM django_migrations WHERE app='bingo';")
        print("✅ Cleared bingo migration history")
    except:
        pass
innerEOF

# Apply the new master migration
python manage.py migrate --fake-initial --no-input
python manage.py init_bingo || true
EOF

echo "✅ System Reset Prepared!"
