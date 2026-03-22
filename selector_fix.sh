#!/bin/bash
# VladBingo - Professional Bot Selector Fix

cat <<EOF > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, MessageHandler, filters

# Setup Paths
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from bingo.models import User

async def start(update: Update, context):
    uid = update.effective_user.id
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    
    # URL for the Mini App with the selected card
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={user.selected_card}"
    
    msg = (f"👋 **Welcome to Vlad Bingo, {update.effective_user.first_name}!**\n\n"
           f"🎫 **Current Card:** #{user.selected_card}\n"
           f"💰 **Balance:** {user.operational_credit} ETB\n\n"
           f"🔢 **How to select a card:**\n"
           f"Just type any number between **1 and 100** to change your board!")
    
    kbd = [
        [InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url=live_url))],
        [InlineKeyboardButton("🔄 Change Card", callback_data="change_hint")]
    ]
    
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def handle_message(update: Update, context):
    text = update.message.text
    if text.isdigit():
        num = int(text)
        if 1 <= num <= 100:
            uid = update.effective_user.id
            user = User.objects.get(username=f"tg_{uid}")
            user.selected_card = num
            user.save()
            
            live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={num}"
            kbd = [[InlineKeyboardButton("🎮 ENTER HALL WITH CARD #"+str(num), web_app=WebAppInfo(url=live_url))]]
            
            await update.message.reply_text(
                f"✅ **Lucky Card #{num} Selected!**\nClick below to enter the game.",
                reply_markup=InlineKeyboardMarkup(kbd),
                parse_mode='Markdown'
            )
        else:
            await update.message.reply_text("❌ Please enter a number between 1 and 100.")

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not token:
        print("CRITICAL ERROR: No token found!")
        return
        
    app = Application.builder().token(token).build()
    
    # Handlers
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    
    print("🤖 VladBingo Bot is listening for players...")
    app.run_polling()

if __name__ == "__main__":
    run()
EOF

echo "✅ Selector logic updated!"
