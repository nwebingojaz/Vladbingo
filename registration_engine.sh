#!/bin/bash
# VladBingo - Professional Registration Flow (Name + One-Tap Phone)

# 1. Update Models (Add real_name and phone_number)
cat <<'EOF' > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_cards = models.JSONField(default=list)
    bot_state = models.CharField(max_length=30, default="START") # START, REG_NAME, REG_PHONE, IDLE
    real_name = models.CharField(max_length=100, blank=True)
    phone_number = models.CharField(max_length=20, blank=True)

class PermanentCard(models.Model):
    card_number = models.PositiveSmallIntegerField(unique=True)
    board = models.JSONField()

class GameRound(models.Model):
    created_at = models.DateTimeField(default=timezone.now)
    called_numbers = models.JSONField(default=list)
    players = models.JSONField(default=dict) 
    bet_amount = models.DecimalField(max_digits=10, decimal_places=2, default=20)
    status = models.CharField(max_length=20, default="LOBBY")

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    type = models.CharField(max_length=20, default="DEPOSIT")
    note = models.TextField(default="")
EOF

# 2. Update Bot Main with Registration Flow
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, KeyboardButton, ReplyKeyboardMarkup, ReplyKeyboardRemove, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR)); os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings"); django.setup()
from bingo.models import User

def get_user_db(uid, name=""):
    return User.objects.get_or_create(username=f"tg_{uid}")[0]

async def start(update: Update, context):
    user = await sync_to_async(get_user_db)(update.effective_user.id)
    
    # Check if registered
    if not user.real_name:
        user.bot_state = "REG_NAME"
        await sync_to_async(user.save)()
        await update.message.reply_text("👋 **Welcome to Vlad Bingo!**\n\nTo start playing, please enter your **Full Name**:", parse_mode='Markdown')
        return

    if not user.phone_number:
        user.bot_state = "REG_PHONE"
        await sync_to_async(user.save)()
        contact_btn = [[KeyboardButton("📲 Share Phone Number", request_contact=True)]]
        await update.message.reply_text("Great! Now click the button below to share your phone number for fast withdrawals:", 
                                      reply_markup=ReplyKeyboardMarkup(contact_btn, one_time_keyboard=True, resize_keyboard=True))
        return

    # If already registered, show Main Menu
    cards = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "None"
    msg = f"🎰 **VLAD BINGO** 🎰\n👤 **Player:** {user.real_name}\n💰 **Balance:** {user.operational_credit} ETB\n🎫 **Cards:** {cards}"
    kbd = [[InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))],
           [InlineKeyboardButton("➕ Add Card", callback_data="add"), InlineKeyboardButton("➖ Remove", callback_data="rem")],
           [InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🏧 Withdraw", callback_data="wd")]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def text_handler(update: Update, context):
    uid = update.effective_user.id
    user = await sync_to_async(get_user_db)(uid)
    text = update.message.text

    if user.bot_state == "REG_NAME":
        user.real_name = text
        user.bot_state = "REG_PHONE"
        await sync_to_async(user.save)()
        contact_btn = [[KeyboardButton("📲 Share Phone Number", request_contact=True)]]
        await update.message.reply_text(f"Nice to meet you, {text}!\n\nPlease tap the button to verify your phone:", 
                                      reply_markup=ReplyKeyboardMarkup(contact_btn, one_time_keyboard=True, resize_keyboard=True))

    elif user.bot_state == "SELECTING" and text.isdigit():
        val = int(text)
        user.selected_cards.append(val); await sync_to_async(user.save)()
        await update.message.reply_text(f"✅ Card #{val} added! Type /start to see menu.")

async def contact_handler(update: Update, context):
    uid = update.effective_user.id
    user = await sync_to_async(get_user_db)(uid)
    if update.message.contact:
        user.phone_number = update.message.contact.phone_number
        user.bot_state = "IDLE"
        await sync_to_async(user.save)()
        await update.message.reply_text("🎉 **Registration Complete!**\nYou are ready to play.", reply_markup=ReplyKeyboardRemove(), parse_mode='Markdown')
        await start(update, context)

async def post_init(app): await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.add_handler(MessageHandler(filters.CONTACT, contact_handler))
    app.add_handler(CallbackQueryHandler(lambda u,c: None)) # Placeholder
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ Registration Engine applied!"
