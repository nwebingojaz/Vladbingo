#!/bin/bash
# VladBingo - Full Model Restore + Selector Bot

# 1. Restore ALL Models (including Transaction)
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
    running_balance = models.DecimalField(max_digits=12, decimal_places=2)
    note = models.TextField(blank=True)
EOF

# 2. Final Bot Main logic with Selector
cat <<EOF > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, MessageHandler, filters
from bingo.models import User

async def start(update: Update, context):
    uid = update.effective_user.id
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={user.selected_card}"
    
    msg = (f"🎰 **VLAD BINGO BOT** 🎰\n\n"
           f"👤 Player: {update.effective_user.first_name}\n"
           f"🎫 Your Card: #**{user.selected_card}**\n"
           f"💰 Balance: {user.operational_credit} ETB\n\n"
           f"🔢 **To change your card:**\n"
           f"Just type a number between **1 and 100**.")
    
    kbd = [[InlineKeyboardButton(f"🎮 JOIN HALL WITH CARD #{user.selected_card}", web_app=WebAppInfo(url=live_url))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def handle_card_change(update: Update, context):
    text = update.message.text
    if text.isdigit():
        num = int(text)
        if 1 <= num <= 100:
            uid = update.effective_user.id
            user = User.objects.get(username=f"tg_{uid}")
            user.selected_card = num
            user.save()
            
            live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={num}"
            kbd = [[InlineKeyboardButton(f"🎮 JOIN HALL WITH CARD #{num}", web_app=WebAppInfo(url=live_url))]]
            await update.message.reply_text(f"✅ Card updated to **#{num}**!", 
                                          reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_card_change))
    print("🤖 Bot is back online...")
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ Transaction model restored and Selector logic ready!"
