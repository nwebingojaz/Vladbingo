#!/bin/bash
# VladBingo - Deep Clean & Import Fix

# 1. Ensure all directories have __init__.py (Crucial for Imports!)
touch backend/bingo/__init__.py
touch backend/bingo/services/__init__.py
touch backend/bingo/bot/__init__.py

# 2. Rewrite Chapa Service with correct name
cat <<EOF > backend/bingo/services/chapa.py
import os, requests, uuid
def init_deposit(user, amount):
    CHAPA_KEY = os.environ.get("CHAPA_SECRET_KEY")
    WEBHOOK = os.environ.get("WEBHOOK_URL")
    ref = f"dep-{uuid.uuid4().hex[:6]}"
    payload = {
        "amount": str(amount), "currency": "ETB", "tx_ref": ref,
        "email": f"user_{user.id}@vladbingo.com", "callback_url": WEBHOOK
    }
    headers = {"Authorization": f"Bearer {CHAPA_KEY}"}
    res = requests.post("https://api.chapa.co/v1/transaction/initialize", json=payload, headers=headers)
    return res.json(), ref
EOF

# 3. Rewrite Bot Main with Path Insurance
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path
from asgiref.sync import sync_to_async

# THE IMPORT FIX: Add the backend folder to Python path
CURRENT_DIR = Path(__file__).resolve().parent # bot folder
BINGO_DIR = CURRENT_DIR.parent # bingo folder
BACKEND_DIR = BINGO_DIR.parent # backend folder
sys.path.append(str(BACKEND_DIR))

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler
from bingo.models import User, Transaction
from bingo.services.chapa import init_deposit

def get_user_db(uid):
    return User.objects.get_or_create(username=f"tg_{uid}")[0]

async def start(update: Update, context):
    user = await sync_to_async(get_user_db)(update.effective_user.id)
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={user.selected_card}"
    msg = (f"🎰 **VLAD BINGO** 🎰\n\n"
           f"🎫 Your Card: #{user.selected_card}\n"
           f"💰 Balance: {user.operational_credit} ETB\n\n"
           f"🕹 **COMMANDS:**\n"
           f"🎲 /select <number>\n"
           f"💳 /deposit <amount> (Min 20)\n"
           f"🏧 /withdraw <amount>")
    kbd = [[InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url=live_url))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def deposit(update, context):
    try:
        amount = int(context.args[0])
        if amount < 20:
            await update.message.reply_text("⚠️ Minimum 20 ETB.")
            return
        user = await sync_to_async(get_user_db)(update.effective_user.id)
        # Calling the imported function
        res, ref = await sync_to_async(init_deposit)(user, amount)
        link = res['data']['checkout_url']
        await update.message.reply_text(f"💳 [Click to pay {amount} ETB]({link})", parse_mode='Markdown')
    except Exception as e:
        await update.message.reply_text(f"❌ Error: {e}")

async def post_init(app):
    await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("deposit", deposit))
    print("🤖 Bot is fixed and online!")
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ Deep Clean & Path Fix Applied!"
