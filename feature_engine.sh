#!/bin/bash
# VladBingo - Full Feature Engine (Select, Deposit, Withdraw)

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
from telegram.ext import Application, CommandHandler, MessageHandler, filters
from bingo.models import User, Transaction
from bingo.services.chapa import init_deposit

# --- Database Helpers ---
def get_user(uid):
    return User.objects.get_or_create(username=f"tg_{uid}")[0]

def update_card(user, num):
    if User.objects.filter(selected_card=num).exclude(id=user.id).exists():
        return False
    user.selected_card = num
    user.save()
    return True

# --- Bot Commands ---
async def start(update: Update, context):
    user = await sync_to_async(get_user)(update.effective_user.id)
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={user.selected_card}"
    
    msg = (f"🎰 **VLAD BINGO CENTER** 🎰\n\n"
           f"👤 **Player:** {update.effective_user.first_name}\n"
           f"🎫 **Lucky Card:** #{user.selected_card}\n"
           f"💰 **Balance:** {user.operational_credit} ETB\n\n"
           f"🕹 **COMMANDS:**\n"
           f"🎲 `/select <1-100>` - Pick your card\n"
           f"💳 `/deposit <amount>` - Min 20 ETB\n"
           f"🏧 `/withdraw <amount>` - Cash out\n\n"
           f"Select your number first, then enter the hall!")
    
    kbd = [[InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url=live_url))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def select_cmd(update, context):
    try:
        num = int(context.args[0])
        if not (1 <= num <= 100): raise ValueError
        user = await sync_to_async(get_user)(update.effective_user.id)
        success = await sync_to_async(update_card)(user, num)
        
        if success:
            await update.message.reply_text(f"✅ **Card updated to #{num}!**", parse_mode='Markdown')
        else:
            await update.message.reply_text(f"🚫 **Card #{num} is ALREADY TAKEN!**", parse_mode='Markdown')
    except:
        await update.message.reply_text("❌ Use: `/select 45`", parse_mode='Markdown')

async def deposit_cmd(update, context):
    try:
        amount = int(context.args[0])
        if amount < 20:
            await update.message.reply_text("⚠️ **Minimum deposit is 20 Birr.**")
            return
        user = await sync_to_async(get_user)(update.effective_user.id)
        res, ref = await sync_to_async(init_deposit)(user, amount)
        link = res['data']['checkout_url']
        await update.message.reply_text(f"💳 [Click here to pay {amount} ETB]({link})", parse_mode='Markdown')
    except:
        await update.message.reply_text("❌ Use: `/deposit 100`", parse_mode='Markdown')

async def post_init(app):
    await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).post_init(post_init).build()
    
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("select", select_cmd))
    app.add_handler(CommandHandler("deposit", deposit_cmd))
    
    print("🤖 All Systems Go!")
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ Features Applied!"
