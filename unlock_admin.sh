#!/bin/bash
# VladBingo - Admin Dashboard Registration

cat <<EOF > backend/bingo/admin.py
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User, PermanentCard, GameRound, Transaction

# Show the custom User fields (balance and selected card)
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

echo "✅ Admin Registration Updated!"
