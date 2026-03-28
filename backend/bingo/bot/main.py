import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, KeyboardButton, ReplyKeyboardMarkup, ReplyKeyboardRemove, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from channels.layers import get_channel_layer
from decimal import Decimal

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR)); os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings"); django.setup()
from bingo.models import User, GameRound

def db_op(uid, action, val=None):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    if action == "name": user.real_name = val; user.bot_state = "IDLE"
    elif action == "phone": user.phone_number = val; user.bot_state = "IDLE"
    user.save(); return user

async def start(update: Update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    if not user.real_name:
        await sync_to_async(db_op)(user.id, "state", "REG_NAME")
        return await update.message.reply_text("👋 Welcome! Please enter your **Full Name** to register:")
    if not user.phone_number:
        btn = [[KeyboardButton("📲 Share Phone", request_contact=True)]]
        return await update.message.reply_text("Tap below to verify phone:", reply_markup=ReplyKeyboardMarkup(btn, one_time_keyboard=True, resize_keyboard=True))

    live_url = "https://vlad-bingo-web.onrender.com/api/live/"
    kbd = [
        [InlineKeyboardButton("Play Games 🎮", web_app=WebAppInfo(url=live_url))],
        [InlineKeyboardButton("Deposit 💰", callback_data="dep"), InlineKeyboardButton("Withdraw 💰", callback_data="wd")],
        [InlineKeyboardButton("Transfer ↔️", callback_data="tr"), InlineKeyboardButton("My Profile 👤", callback_data="pr")],
        [InlineKeyboardButton("Transactions 📜", callback_data="hi"), InlineKeyboardButton("Balance 💰", callback_data="ba")],
        [InlineKeyboardButton("Join Group ↗️", url="https://t.me/+t8ito3eKejo4OGU0"), InlineKeyboardButton("Contact Us", callback_data="co")]
    ]
    msg = f"🎰 **VLAD BINGO PLATFORM** 🎰\n\n👤 **የመለያ መረጃዎ:**\n📛 **Username:** @{update.effective_user.username}\n💰 **Balance:** {user.operational_credit} ETB"
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(lambda a: a.bot.delete_webhook(drop_pending_updates=True)).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, lambda u,c: None))
    app.add_handler(MessageHandler(filters.CONTACT, lambda u,c: None))
    app.run_polling()
if __name__ == "__main__": run()
