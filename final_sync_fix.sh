#!/bin/bash
# VladBingo - Final Model & Admin Sync

# 1. Update models.py (Ensuring selected_card is present)
cat <<EOF > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    is_agent = models.BooleanField(default=False)
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_card = models.PositiveSmallIntegerField(default=1)

class PermanentCard(models.Model):
    card_number = models.PositiveSmallIntegerField(unique=True)
    board = models.JSONField()

class GameRound(models.Model):
    created_at = models.DateTimeField(default=timezone.now)
    called_numbers = models.JSONField(default=list)
    status = models.CharField(max_length=16, default="PENDING")
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    running_balance = models.DecimalField(max_digits=12, decimal_places=2)
    note = models.TextField(blank=True)
EOF

# 2. Update admin.py (Matching the model exactly)
cat <<EOF > backend/bingo/admin.py
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User, PermanentCard, GameRound, Transaction

class CustomUserAdmin(BaseUserAdmin):
    fieldsets = BaseUserAdmin.fieldsets + (
        ('Bingo Info', {'fields': ('operational_credit', 'selected_card', 'is_agent')}),
    )
    list_display = ('username', 'operational_credit', 'selected_card', 'is_staff')

admin.site.register(User, CustomUserAdmin)
admin.site.register(PermanentCard)
admin.site.register(GameRound)
admin.site.register(Transaction)
EOF

# 3. Update build.sh to FORCE the new field into the database
cat <<EOF > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input
python manage.py init_bingo
EOF

echo "✅ Model and Admin are now perfectly synced!"
