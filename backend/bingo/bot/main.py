import os, sys, django, asyncio
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, MessageHandler, filters
from bingo.models import User, Transaction
from bingo.services.chapa import get_deposit_link

async def start(update: Update, context):
    uid = update.effective_user.id
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={user.selected_card}"
    
    msg = (f"🎰 **VLAD BINGO LIVE** 🎰\n\n"
           f"👤 Player: {update.effective_user.first_name}\n"
           f"🎫 Active Card: #**{user.selected_card}**\n"
           f"💰 Balance: {user.operational_credit} ETB\n\n"
           f"Commands:\n/select <1-100> - Pick a card\n/deposit <amount> - Add ETB\n/withdraw <amount> - Cash out")
    
    kbd = [[InlineKeyboardButton("🎮 OPEN LIVE HALL", web_app=WebAppInfo(url=live_url))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def select(update, context):
    try:
        num = int(context.args[0])
        if not (1 <= num <= 100): raise ValueError
        uid = update.effective_user.id
        # Unique check
        if User.objects.filter(selected_card=num).exclude(username=f"tg_{uid}").exists():
            await update.message.reply_text(f"🚫 Card #{num} is already taken!")
            return
        user = User.objects.get(username=f"tg_{uid}")
        user.selected_card = num
        user.save()
        await update.message.reply_text(f"✅ You now own Card #{num}!")
    except:
        await update.message.reply_text("Usage: /select 45")

async def deposit(update, context):
    try:
        amount = int(context.args[0])
        user = User.objects.get(username=f"tg_{update.effective_user.id}")
        res = get_deposit_link(user, amount)
        link = res['data']['checkout_url']
        await update.message.reply_text(f"💳 [Click here to pay {amount} ETB]({link})", parse_mode='Markdown')
    except:
        await update.message.reply_text("Usage: /deposit 100")

async def withdraw(update, context):
    try:
        amt = int(context.args[0])
        user = User.objects.get(username=f"tg_{update.effective_user.id}")
        if user.operational_credit >= amt:
            Transaction.objects.create(agent=user, amount=-amt, type="WITHDRAWAL")
            await update.message.reply_text(f"✅ Withdrawal request for {amt} ETB sent to admin!")
        else:
            await update.message.reply_text("❌ Insufficient balance.")
    except:
        await update.message.reply_text("Usage: /withdraw 500")

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("select", select))
    app.add_handler(CommandHandler("deposit", deposit))
    app.add_handler(CommandHandler("withdraw", withdraw))
    print("🤖 Bot Fully Armed and Online...")
    app.run_polling()

if __name__ == "__main__": run()
