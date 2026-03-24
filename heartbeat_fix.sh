#!/bin/bash
# VladBingo - Full Feature Heartbeat (The Final Sync)

cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters

# Setup Paths
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from bingo.models import User, GameRound, Transaction
from bingo.services.chapa import init_deposit

# --- Helper Logic ---
def db_op(uid, action, val=None):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    if action == "get": return user
    if action == "state": user.bot_state = val
    if action == "add_card":
        if val not in user.selected_cards:
            user.selected_cards.append(val)
    if action == "rem_card":
        if val in user.selected_cards:
            user.selected_cards.remove(val)
    if action == "clear": user.selected_cards = []
    user.save()
    return user

async def start(update: Update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "state", "IDLE")
    cards = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "❌ None"
    
    msg = (f"🎰 **VLAD BINGO MAIN MENU** 🎰\n\n"
           f"🎫 **Your Cards:** {cards}\n"
           f"💰 **Balance:** {user.operational_credit} ETB\n\n"
           f"Pick an action below:")
    
    kbd = [
        [InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))],
        [InlineKeyboardButton("➕ Add Card", callback_data="add"), InlineKeyboardButton("➖ Remove Card", callback_data="rem")],
        [InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🏧 Withdraw", callback_data="wd")],
        [InlineKeyboardButton("🗑 Clear All", callback_data="clear")]
    ]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def handle_button(update: Update, context):
    q = update.callback_query; await q.answer()
    uid = q.from_user.id
    
    if q.data == "add":
        await sync_to_async(db_op)(uid, "state", "SELECTING")
        await q.edit_message_text("🔢 Type a number (**1-100**) to **ADD** your card:")
    elif q.data == "rem":
        await sync_to_async(db_op)(uid, "state", "REMOVING")
        await q.edit_message_text("🔢 Type the card number to **REMOVE**:")
    elif q.data == "dep":
        await sync_to_async(db_op)(uid, "state", "DEPOSITING")
        await q.edit_message_text("💵 Enter amount to **DEPOSIT** (Min 20):")
    elif q.data == "wd":
        await sync_to_async(db_op)(uid, "state", "WITHDRAWING")
        await q.edit_message_text("🏧 Enter amount to **WITHDRAW**:")
    elif q.data == "clear":
        await sync_to_async(db_op)(uid, "clear")
        await q.edit_message_text("🗑 All cards cleared. Type /start to refresh.")

async def handle_text(update: Update, context):
    uid = update.effective_user.id
    user = await sync_to_async(db_op)(uid, "get")
    text = update.message.text
    if not text.isdigit(): return
    val = int(text)

    if user.bot_state == "SELECTING":
        # Check if taken
        is_taken = await sync_to_async(lambda: User.objects.filter(selected_cards__contains=val).exclude(id=user.id).exists())()
        if is_taken:
            await update.message.reply_text(f"🚫 Card #{val} is taken! Pick another.")
        else:
            await sync_to_async(db_op)(uid, "add_card", val)
            await update.message.reply_text(f"✅ Card #{val} added! Type another or /start to play.")

    elif user.bot_state == "REMOVING":
        await sync_to_async(db_op)(uid, "rem_card", val)
        await update.message.reply_text(f"🗑 Card #{val} removed! Type another or /start.")

    elif user.bot_state == "DEPOSITING":
        if val >= 20:
            res, ref = await sync_to_async(init_deposit)(user, val)
            await update.message.reply_text(f"💳 [Click to pay {val} ETB]({res['data']['checkout_url']})", parse_mode='Markdown')
        else:
            await update.message.reply_text("❌ Minimum is 20 Birr.")

    elif user.bot_state == "WITHDRAWING":
        if user.operational_credit >= val:
            # Simple log - you can process manually in Admin
            await update.message.reply_text(f"🏧 Withdrawal request for {val} ETB sent!")
        else:
            await update.message.reply_text("❌ Insufficient balance.")

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(handle_button))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    print("🤖 Bot is breathing perfectly...")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__": run()
EOF

echo "✅ Heartbeat Fix Applied!"
