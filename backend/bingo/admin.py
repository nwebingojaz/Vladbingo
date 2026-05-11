from django.contrib import admin
from .models import User, PermanentCard, GameRound, Transaction, GameControl

@admin.register(User)
class UserAdmin(admin.ModelAdmin):
    list_display = ['username', 'phone_number', 'operational_credit', 'telegram_id']
    search_fields = ['username', 'phone_number']

@admin.register(Transaction)
class TransactionAdmin(admin.ModelAdmin):
    list_display = ['agent', 'amount', 'type', 'status', 'timestamp']
    list_filter = ['status', 'type']

@admin.register(GameControl)
class GameControlAdmin(admin.ModelAdmin):
    list_display = ['forced_winner_card_number', 'daily_forced_wins']
    
    # This prevents you from accidentally creating more than one control row
    def has_add_permission(self, request):
        if GameControl.objects.exists():
            return False
        return True

admin.site.register(PermanentCard)
admin.site.register(GameRound)