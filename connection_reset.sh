#!/bin/bash
# VladBingo - Connection Reset & Force Reply

cat <<EOF > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path

# 1. FIX PATHS
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
    
    # URL for Mini App
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={user.selected_card}"
    
    msg = (f"🔥 **VLAD BINGO IS ONLINE** 🔥\n\n"
           f"👤 **User:** {update.effective_user.first_name}\n"
           f"🎫 **Your Card:** #{user.selected_card}\n"
           f"💰 **Balance:** {user.operational_credit} ETB\n\n"
           f"➡ **TO CHANGE YOUR CARD:**\n"
           f"Type any number (1-100) and send it here.")
    
    kbd = [[InlineKeyboardButton("🎮 OPEN LIVE HALL", web_app=WebAppInfo(url=live_url))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def handle_text(update: Update, context):
    text = update.message.text
    if text.isdigit():
        num = int(text)
        if 1 <= num <= 100:
            uid = update.effective_user.id
            user = User.objects.get(username=f"tg_{uid}")
            
            # Check if anyone else has this card
            if User.objects.filter(selected_card=num).exclude(id=user.id).exists():
                await update.message.reply_text(f"🚫 Card #{num} is already taken by another player!")
                return

            user.selected_card = num
            user.save()
            await update.message.reply_text(f"✅ Card changed to **#{num}**! Click Open Live Hall to play.")
        else:
            await update.message.reply_text("❌ Please pick a number between 1 and 100.")

async def post_init(application: Application):
    """THE KEY FIX: Delete any old webhooks so Polling works immediately"""
    await application.bot.delete_webhook()
    print("✅ Old Webhooks cleared. Connection is fresh.")

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    # Using post_init to reset the connection
    app = Application.builder().token(token).post_init(post_init).build()
    
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    
    print("🤖 BOT IS NOW LISTENING...")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    run()
EOF

echo "✅ Connection Reset code applied!"
