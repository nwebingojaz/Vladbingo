from django.contrib import admin
from .models import User, PermanentCard, GameRound, Transaction
admin.site.register(PermanentCard)
admin.site.register(GameRound)
admin.site.register(Transaction)
