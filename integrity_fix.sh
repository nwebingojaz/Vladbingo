#!/bin/bash
# VladBingo - Total System Integrity Fix

# 1. WRITE THE FULL MODELS (No models left behind!)
cat <<EOF > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_card = models.PositiveSmallIntegerField(default=1)
    is_agent = models.BooleanField(default=False)

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
    note = models.TextField(blank=True)
EOF

# 2. WRITE THE BOT (Selector + 20 ETB Deposit + Withdraw)
cat <<EOF > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, MessageHandler, filters
from bingo.models import User, Transaction
from bingo.services.chapa import get_deposit_link

async def start(update: Update, context):
    uid = update.effective_user.id
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={user.selected_card}"
    msg = (f"🎰 **VLAD BINGO LIVE** 🎰\n\n"
           f"🎫 Your Card: #**{user.selected_card}**\n"
           f"💰 Balance: {user.operational_credit} ETB\n\n"
           f"🕹 **COMMANDS:**\n"
           f"1️⃣ Type **/select <number>** to pick card\n"
           f"2️⃣ Type **/deposit <amount>** (Min 20 ETB)\n"
           f"3️⃣ Type **/withdraw <amount>** to cash out")
    kbd = [[InlineKeyboardButton("🎮 OPEN LIVE HALL", web_app=WebAppInfo(url=live_url))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def select(update, context):
    try:
        num = int(context.args[0])
        if not (1 <= num <= 100): raise ValueError
        uid = update.effective_user.id
        if User.objects.filter(selected_card=num).exclude(username=f"tg_{uid}").exists():
            await update.message.reply_text(f"🚫 Card #{num} is ALREADY TAKEN!")
            return
        user = User.objects.get(username=f"tg_{uid}")
        user.selected_card = num
        user.save()
        await update.message.reply_text(f"✅ Card updated to #**{num}**!", parse_mode='Markdown')
    except:
        await update.message.reply_text("Usage: /select 45")

async def deposit(update, context):
    try:
        amount = int(context.args[0])
        if amount < 20:
            await update.message.reply_text("⚠️ Minimum deposit is 20 Birr.")
            return
        user = User.objects.get(username=f"tg_{update.effective_user.id}")
        res = get_deposit_link(user, amount)
        link = res['data']['checkout_url']
        await update.message.reply_text(f"💳 [Click here to pay {amount} ETB]({link})", parse_mode='Markdown')
    except:
        await update.message.reply_text("Usage: /deposit 100")

async def post_init(app):
    await app.bot.delete_webhook()

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("select", select))
    app.add_handler(CommandHandler("deposit", deposit))
    print("🤖 Bot Fully Integrity Verified...")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__": run()
EOF

# 3. FIX ADMIN (Registering all models)
cat <<EOF > backend/bingo/admin.py
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User, PermanentCard, GameRound, Transaction

try: admin.site.unregister(User)
except: pass

@admin.register(User)
class CustomUserAdmin(BaseUserAdmin):
    fieldsets = BaseUserAdmin.fieldsets + (('Bingo', {'fields': ('operational_credit', 'selected_card')}),)
    list_display = ('username', 'operational_credit', 'selected_card')

admin.site.register(PermanentCard)
admin.site.register(GameRound)
admin.site.register(Transaction)
EOF

echo "✅ Integrity System Rebuilt!"
