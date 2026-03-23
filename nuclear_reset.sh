#!/bin/bash
# VladBingo - Nuclear Connection Reset

cat <<EOF > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path
from telegram.ext import Application

# Setup Paths
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update
from telegram.ext import CommandHandler
from bingo.models import User

async def start(update: Update, context):
    await update.message.reply_text("✅ VladBingo is finally ONLINE and unique!")

async def post_init(app):
    print("🧹 Cleaning up old connections...")
    await app.bot.delete_webhook(drop_pending_updates=True)
    # Wait 5 seconds to let Telegram servers register the disconnect
    await asyncio.sleep(5)
    print("🚀 Fresh start initialized.")

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.run_polling(drop_pending_updates=True, close_loop=False)

if __name__ == "__main__":
    run()
EOF
