#!/bin/bash
# VladBingo - Plural Field Name Sync Fix

# 1. Update Models (Use selected_cards)
cat <<EOF > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_cards = models.JSONField(default=list) # Plural
    bot_state = models.CharField(max_length=20, default="IDLE")

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
    type = models.CharField(max_length=20, default="DEPOSIT")
    status = models.CharField(max_length=20, default="SUCCESS")
EOF

# 2. Update Admin (Match the plural name)
cat <<EOF > backend/bingo/admin.py
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User, PermanentCard, GameRound, Transaction

try: admin.site.unregister(User)
except: pass

@admin.register(User)
class CustomUserAdmin(BaseUserAdmin):
    # Fixed: Changed selected_card to selected_cards
    fieldsets = BaseUserAdmin.fieldsets + (('Bingo', {'fields': ('operational_credit', 'selected_cards')}),)
    list_display = ('username', 'operational_credit', 'selected_cards')

admin.site.register(PermanentCard)
admin.site.register(GameRound)
admin.site.register(Transaction)
EOF

# 3. Update Build Script to force the database update
cat <<EOF > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input
python manage.py init_bingo || true
EOF

echo "✅ Plural Sync Applied!"
