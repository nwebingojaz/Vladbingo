#!/bin/bash
# VladBingo - Full Menu Restoration & Smart State Logic

cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters

# Path Setup
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from bingo.models import User, GameRound
from bingo.services.chapa import init_deposit

# --- Database Operations (Sync to Async) ---
def db_get_user(uid, name):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}", defaults={'first_name': name})
    return user

async def start(update: Update, context):
    user = await sync_to_async(db_get_user)(update.effective_user.id, update.effective_user.first_name)
    user.bot_state = "IDLE"; await sync_to_async(user.save)()
    
    cards_txt = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "❌ None"
    msg = (f"🎰 **VLAD BINGO MAIN MENU** 🎰\n\n"
           f"🎫 **Your Cards:** {cards_txt}\n"
           f"💰 **Balance:** {user.operational_credit} ETB\n\n"
           f"Select an action:")
    
    # Professional 6-Button Grid
    kbd = [
        [InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))],
        [InlineKeyboardButton("➕ Add Card", callback_data="btn_add"), 
         InlineKeyboardButton("➖ Remove Card", callback_data="btn_rem")],
        [InlineKeyboardButton("💳 Deposit", callback_data="btn_dep"), 
         InlineKeyboardButton("🏧 Withdraw", callback_data="btn_wd")],
        [InlineKeyboardButton("💰 Check Balance", callback_data="btn_bal"),
         InlineKeyboardButton("🗑 Clear All", callback_data="btn_clear")]
    ]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def button_handler(update: Update, context):
    q = update.callback_query; await q.answer()
    uid = q.from_user.id
    user = await sync_to_async(db_get_user)(uid, "")

    if q.data == "btn_add":
        user.bot_state = "SELECTING"; await q.edit_message_text("🔢 Type Card # (**1-100**) to **ADD**:")
    elif q.data == "btn_rem":
        user.bot_state = "REMOVING"; await q.edit_message_text("🔢 Type Card # to **REMOVE**:")
    elif q.data == "btn_dep":
        user.bot_state = "DEPOSITING"; await q.edit_message_text("💵 How much to **DEPOSIT**? (Min 20):")
    elif q.data == "btn_wd":
        user.bot_state = "WITHDRAWING"; await q.edit_message_text("🏧 How much to **WITHDRAW**?")
    elif q.data == "btn_bal":
        await q.edit_message_text(f"💰 **Balance:** {user.operational_credit} ETB\n\nType /start for menu.")
    elif q.data == "btn_clear":
        user.selected_cards = []; await q.edit_message_text("🗑 Cards cleared! Use /start to pick new ones.")
    
    await sync_to_async(user.save)()

async def text_handler(update: Update, context):
    uid = update.effective_user.id
    user = await sync_to_async(db_get_user)(uid, "")
    text = update.message.text
    if not text.isdigit(): return
    val = int(text)

    if user.bot_state == "SELECTING":
        is_taken = await sync_to_async(lambda: User.objects.filter(selected_cards__contains=val).exclude(id=user.id).exists())()
        if is_taken:
            await update.message.reply_text(f"🚫 Card #{val} is taken!")
        else:
            if val not in user.selected_cards:
                user.selected_cards.append(val); await sync_to_async(user.save)()
                await update.message.reply_text(f"✅ Card #{val} added! Type another or /start.")
            else:
                await update.message.reply_text("You already have this card.")

    elif user.bot_state == "REMOVING":
        if val in user.selected_cards:
            user.selected_cards.remove(val); await sync_to_async(user.save)()
            await update.message.reply_text(f"🗑 Card #{val} removed!")
        else:
            await update.message.reply_text(f"❌ You don't own Card #{val}")

    elif user.bot_state == "DEPOSITING" and val >= 20:
        res, ref = await sync_to_async(init_deposit)(user, val)
        await update.message.reply_text(f"💳 [Click to pay {val} ETB]({res['data']['checkout_url']})", parse_mode='Markdown')
        user.bot_state = "IDLE"; await sync_to_async(user.save)()

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(button_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    print("🤖 Bot Fully Restored and Ready...")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__": run()
EOF

echo "✅ Full Menu restored!"
