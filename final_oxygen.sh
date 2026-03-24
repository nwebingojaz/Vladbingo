#!/bin/bash
# VladBingo - Final Sync & Features (Select, Deposit, Withdraw)

# 1. Fix Chapa Service (Ensure function name is init_deposit)
cat <<EOF > backend/bingo/services/chapa.py
import os, requests, uuid
CHAPA_KEY = os.environ.get("CHAPA_SECRET_KEY")
WEBHOOK = os.environ.get("WEBHOOK_URL")

def init_deposit(user, amount):
    ref = f"dep-{uuid.uuid4().hex[:6]}"
    payload = {
        "amount": str(amount), "currency": "ETB", "tx_ref": ref,
        "email": f"user_{user.id}@vladbingo.com", "callback_url": WEBHOOK
    }
    headers = {"Authorization": f"Bearer {CHAPA_KEY}"}
    res = requests.post("https://api.chapa.co/v1/transaction/initialize", json=payload, headers=headers)
    return res.json(), ref
EOF

# 2. Fix Bot Main (Matching the function names + Adding Withdraw)
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
from bingo.models import User, Transaction
from bingo.services.chapa import init_deposit

def get_user_db(uid):
    return User.objects.get_or_create(username=f"tg_{uid}")[0]

def update_card_db(user, num):
    if User.objects.filter(selected_card=num).exclude(id=user.id).exists():
        return False
    user.selected_card = num
    user.save()
    return True

def create_withdrawal_db(user, amount):
    user.operational_credit -= amount
    user.save()
    Transaction.objects.create(agent=user, amount=-amount, type="WITHDRAWAL", status="PENDING")
    return user.operational_credit

async def start(update: Update, context):
    user = await sync_to_async(get_user_db)(update.effective_user.id)
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={user.selected_card}"
    msg = (f"🎰 **VLAD BINGO** 🎰\n\n"
           f"🎫 Your Card: #{user.selected_card}\n"
           f"💰 Balance: {user.operational_credit} ETB\n\n"
           f"🕹 **COMMANDS:**\n"
           f"🎲 `/select <number>` - Pick card\n"
           f"💳 `/deposit <amount>` - Min 20 ETB\n"
           f"🏧 `/withdraw <amount>` - Cash out")
    kbd = [[InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url=live_url))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def select(update, context):
    try:
        num = int(context.args[0])
        if not (1 <= num <= 100): raise ValueError
        user = await sync_to_async(get_user_db)(update.effective_user.id)
        success = await sync_to_async(update_card_db)(user, num)
        if success:
            await update.message.reply_text(f"✅ Card updated to #**{num}**!", parse_mode='Markdown')
        else:
            await update.message.reply_text(f"🚫 Card #{num} is ALREADY TAKEN!")
    except:
        await update.message.reply_text("Usage: /select 45")

async def deposit(update, context):
    try:
        amount = int(context.args[0])
        if amount < 20:
            await update.message.reply_text("⚠️ Minimum deposit is 20 ETB.")
            return
        user = await sync_to_async(get_user_db)(update.effective_user.id)
        res, ref = await sync_to_async(init_deposit)(user, amount)
        link = res['data']['checkout_url']
        await update.message.reply_text(f"💳 [Click here to pay {amount} ETB]({link})", parse_mode='Markdown')
    except:
        await update.message.reply_text("Usage: /deposit 100")

async def withdraw(update, context):
    try:
        amount = int(context.args[0])
        user = await sync_to_async(get_user_db)(update.effective_user.id)
        if user.operational_credit >= amount:
            new_bal = await sync_to_async(create_withdrawal_db)(user, amount)
            await update.message.reply_text(f"✅ Request sent! {amount} ETB deducted.\nNew Balance: {new_bal} ETB")
        else:
            await update.message.reply_text("❌ Insufficient balance.")
    except:
        await update.message.reply_text("Usage: /withdraw 500")

async def post_init(app):
    await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("select", select))
    app.add_handler(CommandHandler("deposit", deposit))
    app.add_handler(CommandHandler("withdraw", withdraw))
    print("🤖 Bot breathing and online...")
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ Oxygen Fix applied! All names synced."
