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
