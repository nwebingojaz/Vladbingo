#!/bin/bash
# VladBingo - User-Friendly Button Interface & Empty Default Card

# 1. Update Models (Set default card to 0, meaning 'none')
cat <<EOF > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_card = models.PositiveSmallIntegerField(default=0) # 0 means no card selected

class PermanentCard(models.Model):
    card_number = models.PositiveSmallIntegerField(unique=True)
    board = models.JSONField()

class GameRound(models.Model):
    created_at = models.DateTimeField(default=timezone.now)
    called_numbers = models.JSONField(default=list)
    status = models.CharField(max_length=16, default="PENDING")

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    type = models.CharField(max_length=20, default="DEPOSIT")
EOF

# 2. Update Bot Main (Button-Driven Menu)
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path
from asgiref.sync import sync_to_async

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from bingo.models import User
from bingo.services.chapa import init_deposit

def get_user_db(uid, name):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}", defaults={'first_name': name})
    return user

async def start(update: Update, context):
    user = await sync_to_async(get_user_db)(update.effective_user.id, update.effective_user.first_name)
    card_display = f"#{user.selected_card}" if user.selected_card > 0 else "❌ NONE SELECTED"
    
    msg = (f"🎰 **VLAD BINGO MAIN MENU** 🎰\n\n"
           f"👤 **Player:** {update.effective_user.first_name}\n"
           f"🎫 **Active Card:** {card_display}\n"
           f"💰 **Balance:** {user.operational_credit} ETB\n\n"
           f"Choose an option below:")
    
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/"
    
    kbd = [
        [InlineKeyboardButton("🎮 OPEN LIVE HALL", web_app=WebAppInfo(url=live_url))],
        [InlineKeyboardButton("🎲 Select My Card", callback_data="btn_select"),
         InlineKeyboardButton("💰 Check Balance", callback_data="btn_balance")],
        [InlineKeyboardButton("💳 Deposit Money", callback_data="btn_deposit"),
         InlineKeyboardButton("🏧 Withdraw Wins", callback_data="btn_withdraw")]
    ]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

# Handle Button Clicks
async def button_handler(update: Update, context):
    query = update.callback_query
    await query.answer()
    
    if query.data == "btn_balance":
        user = await sync_to_async(get_user_db)(query.from_user.id, "")
        await query.edit_message_text(f"💰 **Your Balance:** {user.operational_credit} ETB\n\nUse /start to go back.", parse_mode='Markdown')
    
    elif query.data == "btn_select":
        await query.edit_message_text("🔢 **Type a number (1-100)** to pick your lucky card!")

    elif query.data == "btn_deposit":
        await query.edit_message_text("💳 **Type /deposit <amount>**\nExample: `/deposit 100` (Min 20 ETB)", parse_mode='Markdown')

async def handle_text(update: Update, context):
    text = update.message.text
    if text.isdigit():
        num = int(text)
        if 1 <= num <= 100:
            user = await sync_to_async(get_user_db)(update.effective_user.id, "")
            user.selected_card = num
            await sync_to_async(user.save)()
            await update.message.reply_text(f"✅ **Card #{num} Locked!**\nUse /start to open the Hall.", parse_mode='Markdown')

async def post_init(app):
    await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(button_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ UI Overhaul applied!"
