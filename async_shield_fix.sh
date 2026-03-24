#!/bin/bash
# VladBingo - Async Database Shield Fix

cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path
from asgiref.sync import sync_to_async

# Setup Paths
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler
from bingo.models import User

# Define Database operations as sync functions
def get_or_create_user(uid, first_name):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    return user

async def start(update: Update, context):
    uid = update.effective_user.id
    first_name = update.effective_user.first_name
    
    # THE KEY FIX: Wrap the database call in sync_to_async
    user = await sync_to_async(get_or_create_user)(uid, first_name)
    
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={user.selected_card}"
    
    msg = (f"🎰 **VLAD BINGO IS LIVE!** 🎰\n\n"
           f"👤 Player: {first_name}\n"
           f"🎫 Your Card: #{user.selected_card}\n"
           f"💰 Balance: {user.operational_credit} ETB\n\n"
           f"Click below to enter the Live Hall!")
    
    kbd = [[InlineKeyboardButton("🎮 OPEN LIVE HALL", web_app=WebAppInfo(url=live_url))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def post_init(app):
    await app.bot.delete_webhook(drop_pending_updates=True)
    print("🚀 Fresh bot session started with Async Shield.")

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    run()
EOF

echo "✅ Async Shield applied to Bot logic!"
