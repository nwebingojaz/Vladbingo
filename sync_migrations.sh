#!/bin/bash
# VladBingo - Manual Migration Chain Restoration

# 1. Ensure folder exists
mkdir -p backend/bingo/migrations
touch backend/bingo/migrations/__init__.py

# 2. Manually write 0001_initial.py (The Parent)
cat <<EOF > backend/bingo/migrations/0001_initial.py
from django.db import migrations, models
import django.utils.timezone

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
                ('is_agent', models.BooleanField(default=False)),
                ('operational_credit', models.DecimalField(decimal_places=2, default=0, max_digits=12)),
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
                ('status', models.CharField(default='PENDING', max_length=16)),
                ('amount', models.DecimalField(decimal_places=2, default=0, max_digits=12)),
            ],
        ),
    ]
EOF

# 3. Manually write 0002_add_selected_card.py (The Child)
cat <<EOF > backend/bingo/migrations/0002_add_selected_card.py
from django.db import migrations, models

class Migration(migrations.Migration):
    dependencies = [('bingo', '0001_initial')]
    operations = [
        migrations.AddField(
            model_name='user',
            name='selected_card',
            field=models.PositiveSmallIntegerField(default=1),
        ),
        migrations.CreateModel(
            name='Transaction',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('timestamp', models.DateTimeField(default=django.utils.timezone.now)),
                ('amount', models.DecimalField(decimal_places=2, max_digits=12)),
                ('running_balance', models.DecimalField(decimal_places=2, max_digits=12)),
                ('note', models.TextField(blank=True)),
                ('agent', models.ForeignKey(on_delete=models.deletion.CASCADE, to='bingo.user')),
            ],
        ),
    ]
EOF

# 4. Clean up build.sh
cat <<EOF > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py migrate --no-input
python manage.py init_bingo || true
EOF

echo "✅ Full migration chain restored manually!"
