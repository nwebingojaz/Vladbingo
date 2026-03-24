#!/bin/bash
# VladBingo - Granular Card Control (Add/Remove/Clear)

# 1. Ensure Models are correct
cat <<EOF > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_cards = models.JSONField(default=list)
    bot_state = models.CharField(max_length=20, default="IDLE") # IDLE, SELECTING, REMOVING, DEPOSITING

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

# 2. Updated Bot with "Unselect" Option
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
    user.bot_state = "IDLE"
    await sync_to_async(user.save)()
    
    cards_text = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "❌ None"
    msg = (f"🎰 **VLAD BINGO CENTER** 🎰\n\n"
           f"🎫 **Your Cards:** {cards_text}\n"
           f"💰 **Balance:** {user.operational_credit} ETB\n\n"
           f"Pick an action:")
    
    kbd = [
        [InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))],
        [InlineKeyboardButton("➕ Add Card", callback_data="btn_add"),
         InlineKeyboardButton("➖ Remove Card", callback_data="btn_rem")],
        [InlineKeyboardButton("🗑 Clear All", callback_data="btn_clear"),
         InlineKeyboardButton("💰 Balance", callback_data="btn_bal")],
        [InlineKeyboardButton("💳 Deposit", callback_data="btn_dep"),
         InlineKeyboardButton("🏧 Withdraw", callback_data="btn_wd")]
    ]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def button_handler(update: Update, context):
    query = update.callback_query
    user = await sync_to_async(get_user_db)(query.from_user.id, "")
    await query.answer()
    
    if query.data == "btn_add":
        user.bot_state = "SELECTING"
        await query.edit_message_text("🔢 Type a number (**1-100**) to **ADD** a card:", parse_mode='Markdown')
    elif query.data == "btn_rem":
        user.bot_state = "REMOVING"
        await query.edit_message_text("🔢 Type the card number you want to **REMOVE**:", parse_mode='Markdown')
    elif query.data == "btn_clear":
        user.selected_cards = []
        await query.edit_message_text("✅ All cards removed. Use /start to pick new ones.")
    elif query.data == "btn_bal":
        await query.edit_message_text(f"💰 **Current Balance:** {user.operational_credit} ETB\n\nUse /start for menu.", parse_mode='Markdown')
    elif query.data == "btn_dep":
        user.bot_state = "DEPOSITING"
        await query.edit_message_text("💵 Enter amount to deposit (Min 20):")
    
    await sync_to_async(user.save)()

async def text_handler(update: Update, context):
    user = await sync_to_async(get_user_db)(update.effective_user.id, "")
    text = update.message.text
    if not text.isdigit(): return
    val = int(text)

    if user.bot_state == "SELECTING":
        is_taken = await sync_to_async(lambda: User.objects.filter(selected_cards__contains=val).exists())()
        if is_taken:
            await update.message.reply_text(f"🚫 Card #{val} is already taken!")
        else:
            if val not in user.selected_cards:
                user.selected_cards.append(val)
                await sync_to_async(user.save)()
                await update.message.reply_text(f"✅ Card #{val} added! Use /start to finish or type another number.")
            else:
                await update.message.reply_text("You already have this card.")

    elif user.bot_state == "REMOVING":
        if val in user.selected_cards:
            user.selected_cards.remove(val)
            await sync_to_async(user.save)()
            await update.message.reply_text(f"🗑 Card #{val} removed. Use /start to go back.")
        else:
            await update.message.reply_text(f"❌ You don't have Card #{val}.")

    elif user.bot_state == "DEPOSITING":
        if val >= 20:
            res, ref = await sync_to_async(init_deposit)(user, val)
            link = res['data']['checkout_url']
            await update.message.reply_text(f"💳 [Click here to pay {val} ETB]({link})", parse_mode='Markdown')
        user.bot_state = "IDLE"
        await sync_to_async(user.save)()

async def post_init(app):
    await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(button_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ Granular Control Applied! (Add/Remove Card)"
