#!/bin/bash
# VladBingo Professional One-Day Build Script

echo "🚀 Starting the VladBingo Professional Build..."

# 1. Create Folder Structure
mkdir -p backend/bingo/bot backend/bingo/services backend/bingo/management/commands backend/vlad_bingo
mkdir -p frontend/src frontend/public/audio/male

# 2. Create Requirements
cat <<EOF > backend/requirements.txt
Django>=4.2
djangorestframework
python-telegram-bot
requests
python-dotenv
daphne
channels
channels-redis
dj-database-url
whitenoise
psycopg2-binary
EOF

# 3. Create Chapa Service (Automated Deposits/Withdrawals)
cat <<EOF > backend/bingo/services/chapa.py
import os, requests, uuid
CHAPA_KEY = os.environ.get("CHAPA_SECRET_KEY")
CHAPA_URL = "https://api.chapa.co/v1"

def init_deposit(user, amount):
    ref = f"dep-{uuid.uuid4().hex[:6]}"
    payload = {
        "amount": str(amount), "currency": "ETB", "tx_ref": ref,
        "email": f"{user.id}@vladbingo.com",
        "callback_url": os.environ.get("WEBHOOK_URL")
    }
    headers = {"Authorization": f"Bearer {CHAPA_KEY}"}
    res = requests.post(f"{CHAPA_URL}/transaction/initialize", json=payload, headers=headers)
    return res.json(), ref

def automated_payout(user, amount, bank_code, account_num):
    ref = f"wd-{uuid.uuid4().hex[:6]}"
    payload = {
        "account_name": user.username,
        "account_number": account_num, 
        "amount": str(amount),
        "bank_code": bank_code, 
        "reference": ref, 
        "currency": "ETB"
    }
    headers = {"Authorization": f"Bearer {CHAPA_KEY}"}
    res = requests.post(f"{CHAPA_URL}/transfers", json=payload, headers=headers)
    return res.json()
EOF

# 4. Create the shared Bingo Win-Logic
cat <<EOF > backend/bingo/services/bingo_logic.py
def check_win(board, called_numbers):
    called_set = set(called_numbers)
    # Checks for Full House (All numbers called)
    for col in board:
        for cell in col:
            if cell == "FREE": continue
            if cell not in called_set:
                return False
    return True
EOF

# 5. Create the Telegram Bot Main Engine
cat <<EOF > backend/bingo/bot/main.py
import os, django, asyncio
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, CallbackQueryHandler

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()
from bingo.models import User

async def start(update, context):
    uid = update.effective_user.id
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    kbd = [[InlineKeyboardButton("🎮 Join Game", callback_data="join"), 
            InlineKeyboardButton("💰 Wallet", callback_data="wallet")]]
    await update.message.reply_text(f"Welcome to VladBingo!\nBalance: {user.operational_credit} ETB", 
        reply_markup=InlineKeyboardMarkup(kbd))

def run():
    TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    print("🤖 VladBingo Bot is LIVE...")
    app.run_polling()

if __name__ == "__main__": run()
EOF

# 6. Create Render Blueprint (Infrastructure setup)
cat <<EOF > render.yaml
services:
  - type: web
    name: vlad-bingo-web
    env: python
    buildCommand: "./backend/build.sh"
    startCommand: "python -m daphne vlad_bingo.asgi:application"
    envVars:
      - key: REDIS_URL
        fromService:
          name: vlad-redis
          type: redis
  - type: worker
    name: vlad-bingo-bot
    env: python
    startCommand: "python backend/bingo/bot/main.py"
databases:
  - name: vlad_db
    plan: free
redis:
  - name: vlad-redis
    plan: free
EOF

# 7. Create Build Script
cat <<EOF > backend/build.sh
#!/usr/bin/env bash
set -o errexit
pip install -r backend/requirements.txt
python backend/manage.py migrate
EOF
chmod +x backend/build.sh

echo "✅ Build Complete! Ready for Git Push."
