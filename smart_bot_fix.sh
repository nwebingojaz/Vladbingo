#!/bin/bash
# VladBingo - Smart Command Handling Fix

cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path
from asgiref.sync import sync_to_async

# Path Setup
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, MessageHandler, filters
from bingo.models import User, Transaction
from bingo.services.chapa import init_deposit

# --- Helper Logic ---
def get_user_db(uid, name):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}", defaults={'first_name': name})
    return user

def update_card_db(user, num):
    if User.objects.filter(selected_card=num).exclude(id=user.id).exists():
        return False
    user.selected_card = num
    user.save()
    return True

# --- Command Handlers ---
async def start(update: Update, context):
    user = await sync_to_async(get_user_db)(update.effective_user.id, update.effective_user.first_name)
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={user.selected_card}"
    msg = (f"🎰 **VLAD BINGO** 🎰\n\n"
           f"🎫 Your Card: #**{user.selected_card}**\n"
           f"💰 Balance: {user.operational_credit} ETB\n\n"
           f"🕹 **USAGE:**\n"
           f"🎲 `/select 7` - Change card\n"
           f"💳 `/deposit 100` - Add money\n"
           f"🏧 `/withdraw 500` - Cash out")
    kbd = [[InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url=live_url))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def select(update: Update, context):
    if not context.args:
        await update.message.reply_text("❌ Please provide a number. Example: `/select 3`", parse_mode='Markdown')
        return
    try:
        num = int(context.args[0])
        if not (1 <= num <= 100): raise ValueError
        user = await sync_to_async(get_user_db)(update.effective_user.id, update.effective_user.first_name)
        success = await sync_to_async(update_card_db)(user, num)
        if success:
            await update.message.reply_text(f"✅ Card updated to **#{num}**!", parse_mode='Markdown')
        else:
            await update.message.reply_text(f"🚫 Card #{num} is already taken!")
    except:
        await update.message.reply_text("❌ Pick a number between 1 and 100.")

async def deposit(update: Update, context):
    if not context.args:
        await update.message.reply_text("❌ Please provide an amount. Example: `/deposit 100`", parse_mode='Markdown')
        return
    try:
        amount = int(context.args[0])
        if amount < 20:
            await update.message.reply_text("⚠️ Minimum deposit is 20 ETB.")
            return
        user = await sync_to_async(get_user_db)(update.effective_user.id, update.effective_user.first_name)
        res, ref = await sync_to_async(init_deposit)(user, amount)
        link = res['data']['checkout_url']
        await update.message.reply_text(f"💳 [Click to pay {amount} ETB]({link})", parse_mode='Markdown')
    except Exception as e:
        await update.message.reply_text(f"❌ Error connecting to Chapa.")

async def post_init(app):
    await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("select", select))
    app.add_handler(CommandHandler("deposit", deposit))
    print("🤖 Smart Bot is running...")
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ Smart Bot logic applied!"
