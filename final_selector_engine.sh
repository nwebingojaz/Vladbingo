#!/bin/bash
# VladBingo - Final Selector Engine

# 1. Ensure the Model has 'selected_card'
cat <<EOF > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_card = models.PositiveSmallIntegerField(default=1)

class PermanentCard(models.Model):
    card_number = models.PositiveSmallIntegerField(unique=True)
    board = models.JSONField()

class GameRound(models.Model):
    created_at = models.DateTimeField(default=timezone.now)
    called_numbers = models.JSONField(default=list)
    status = models.CharField(max_length=16, default="PENDING")
EOF

# 2. Fix the Bot to handle number selection
cat <<EOF > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path

# Path Anchor
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
    
    msg = (f"🎰 **WELCOME TO VLAD BINGO** 🎰\n\n"
           f"🎫 Your Selected Card: #**{user.selected_card}**\n"
           f"💰 Balance: {user.operational_credit} ETB\n\n"
           f"🔢 **To change your card:**\n"
           f"Just type a number between **1 and 100** and send it!")
    
    kbd = [[InlineKeyboardButton(f"🎮 ENTER HALL WITH CARD #{user.selected_card}", web_app=WebAppInfo(url=live_url))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def change_card(update: Update, context):
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
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, change_card))
    print("🤖 Bot is Online and Ready...")
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ Selector Engine ready for push!"
