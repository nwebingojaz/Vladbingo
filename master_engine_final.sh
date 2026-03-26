#!/bin/bash
# VladBingo - Full Master Engine (Registration + Menu + Dealer)

cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, KeyboardButton, ReplyKeyboardMarkup, ReplyKeyboardRemove, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from django.conf import settings

# Path Setup
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from bingo.models import User, GameRound, Transaction
from bingo.services.chapa import init_deposit

# --- DB HELPERS ---
def db_op(uid, action, val=None, name=None):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    if action == "state": user.bot_state = val
    elif action == "name": user.real_name = val; user.bot_state = "REG_PHONE"
    elif action == "phone": user.phone_number = val; user.bot_state = "IDLE"
    elif action == "add": 
        if val not in user.selected_cards: user.selected_cards.append(val)
    elif action == "rem":
        if val in user.selected_cards: user.selected_cards.remove(val)
    elif action == "clear": user.selected_cards = []
    user.save()
    return user

# --- HANDLERS ---
async def start(update: Update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    
    if not user.real_name:
        await sync_to_async(db_op)(user.id, "state", "REG_NAME")
        await update.message.reply_text("👋 **Welcome to Vlad Bingo!**\n\nPlease enter your **Full Name** to register:", parse_mode='Markdown')
        return

    if not user.phone_number:
        btn = [[KeyboardButton("📲 Share Phone Number", request_contact=True)]]
        await update.message.reply_text("One more step! Tap the button to verify your phone:", 
            reply_markup=ReplyKeyboardMarkup(btn, one_time_keyboard=True, resize_keyboard=True))
        return

    cards_txt = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "❌ None"
    msg = (f"🎰 **VLAD BINGO MAIN MENU** 🎰\n\n"
           f"👤 **Player:** {user.real_name}\n"
           f"🎫 **Cards:** {cards_txt}\n"
           f"💰 **Balance:** {user.operational_credit} ETB\n\n"
           f"Select an action:")
    
    kbd = [
        [InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))],
        [InlineKeyboardButton("➕ Add Card", callback_data="add"), InlineKeyboardButton("➖ Remove", callback_data="rem")],
        [InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🏧 Withdraw", callback_data="wd")],
        [InlineKeyboardButton("🗑 Clear All", callback_data="clear")]
    ]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def handle_button(update: Update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    if q.data == "add":
        await sync_to_async(db_op)(uid, "state", "SELECTING")
        await q.edit_message_text("🔢 Type a card number (**1-100**) to **ADD**:", parse_mode='Markdown')
    elif q.data == "rem":
        await sync_to_async(db_op)(uid, "state", "REMOVING")
        await q.edit_message_text("🔢 Type a card number to **REMOVE**:", parse_mode='Markdown')
    elif q.data == "dep":
        await sync_to_async(db_op)(uid, "state", "DEPOSITING")
        await q.edit_message_text("💵 How much to **DEPOSIT**? (Min 20 ETB):", parse_mode='Markdown')
    elif q.data == "clear":
        await sync_to_async(db_op)(uid, "clear")
        await q.edit_message_text("🗑 Cards cleared! Use /start to refresh.")

async def handle_text(update: Update, context):
    uid = update.effective_user.id
    user = await sync_to_async(db_op)(uid, "get")
    text = update.message.text

    if user.bot_state == "REG_NAME":
        await sync_to_async(db_op)(uid, "name", text)
        btn = [[KeyboardButton("📲 Share Phone Number", request_contact=True)]]
        await update.message.reply_text(f"Nice to meet you, {text}!\nTap below to finish:", 
            reply_markup=ReplyKeyboardMarkup(btn, one_time_keyboard=True, resize_keyboard=True))
    
    elif text.isdigit():
        val = int(text)
        if user.bot_state == "SELECTING":
            await sync_to_async(db_op)(uid, "add", val)
            await update.message.reply_text(f"✅ Card #{val} added! Type another or /start.")
        elif user.bot_state == "REMOVING":
            await sync_to_async(db_op)(uid, "rem", val)
            await update.message.reply_text(f"🗑 Card #{val} removed!")
        elif user.bot_state == "DEPOSITING" and val >= 20:
            res, ref = await sync_to_async(init_deposit)(user, val)
            await update.message.reply_text(f"💳 [Click to Pay {val} ETB]({res['data']['checkout_url']})", parse_mode='Markdown')

async def handle_contact(update: Update, context):
    if update.message.contact:
        phone = update.message.contact.phone_number
        await sync_to_async(db_op)(update.effective_user.id, "phone", phone)
        await update.message.reply_text("🎉 **Registration Complete!**", reply_markup=ReplyKeyboardRemove(), parse_mode='Markdown')
        await start(update, context)

async def post_init(app):
    await app.bot.delete_webhook(drop_pending_updates=True)
    print("🤖 MASTER ENGINE ONLINE...")

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(handle_button))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    app.add_handler(MessageHandler(filters.CONTACT, handle_contact))
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ Master Engine Restored!"
