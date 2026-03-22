#!/bin/bash
# VladBingo - Final Admin and App Sync

# 1. Fix bingo/apps.py (Ensure the name matches exactly)
cat <<EOF > backend/bingo/apps.py
from django.apps import AppConfig
class BingoConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'bingo'
EOF

# 2. Fix bingo/admin.py (The registration logic)
cat <<EOF > backend/bingo/admin.py
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User, PermanentCard, GameRound, Transaction

# Remove default registrations if they exist to avoid errors
try:
    admin.site.unregister(User)
except:
    pass

@admin.register(User)
class CustomUserAdmin(BaseUserAdmin):
    fieldsets = BaseUserAdmin.fieldsets + (
        ('Bingo Info', {'fields': ('operational_credit', 'selected_card', 'is_agent')}),
    )
    list_display = ('username', 'operational_credit', 'selected_card', 'is_staff')

@admin.register(PermanentCard)
class PermanentCardAdmin(admin.ModelAdmin):
    list_display = ('card_number',)

@admin.register(GameRound)
class GameRoundAdmin(admin.ModelAdmin):
    list_display = ('id', 'status', 'created_at')

@admin.register(Transaction)
class TransactionAdmin(admin.ModelAdmin):
    list_display = ('agent', 'amount', 'timestamp')
EOF

# 3. Ensure bingo is in settings.py INSTALLED_APPS
# (Just in case it was missing)
sed -i "s/'bingo'/'bingo.apps.BingoConfig'/g" backend/vlad_bingo/settings.py

echo "✅ Admin Logic Rebuilt!"
