#!/bin/bash
# VladBingo - Full Command Restoration & Auto-Dealer

# 1. Update the Bot Main (The Professional Menu)
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from channels.layers import get_channel_layer
from decimal import Decimal

# Setup Paths
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from bingo.models import User, GameRound
from bingo.services.chapa import init_deposit

def db_op(uid, action, val=None):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    if action == "state": user.bot_state = val
    elif action == "add": 
        if val not in user.selected_cards: user.selected_cards.append(val)
    elif action == "rem":
        if val in user.selected_cards: user.selected_cards.remove(val)
    elif action == "clear": user.selected_cards = []
    user.save()
    return user

async def start(update: Update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    user.bot_state = "IDLE"; await sync_to_async(user.save)()
    
    cards_txt = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "❌ None"
    msg = (f"🎰 **VLAD BINGO MAIN MENU** 🎰\n\n"
           f"👤 **Player:** {update.effective_user.first_name}\n"
           f"🎫 **Your Cards:** {cards_txt}\n"
           f"💰 **Balance:** {user.operational_credit} ETB\n\n"
           f"Pick an action below:")
    
    kbd = [
        [InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))],
        [InlineKeyboardButton("➕ Add Card", callback_data="add"), InlineKeyboardButton("➖ Remove", callback_data="rem")],
        [InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🏧 Withdraw", callback_data="wd")],
        [InlineKeyboardButton("🗑 Clear All", callback_data="clear")]
    ]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def game_dealer(game_id, context):
    """Wait 5 minutes then start calling numbers"""
    await asyncio.sleep(300) # 5 Minute Countdown
    game = await sync_to_async(GameRound.objects.get)(id=game_id)
    game.status = "ACTIVE"; await sync_to_async(game.save)()
    
    nums = list(range(1, 76)); random.shuffle(nums)
    layer = get_channel_layer()
    for n in nums:
        game.refresh_from_db()
        if "WON" in game.status: break
        game.called_numbers.append(n); await sync_to_async(game.save)()
        await layer.group_send("bingo_live", {"type": "bingo_message", "message": {"action": "call_number", "number": n}})
        await asyncio.sleep(7)

async def btn_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    if q.data == "add":
        await sync_to_async(db_op)(uid, "state", "SELECTING")
        await q.edit_message_text("🔢 Type Card # (**1-100**) to **ADD**:")
    elif q.data == "rem":
        await sync_to_async(db_op)(uid, "state", "REMOVING")
        await q.edit_message_text("🔢 Type Card # to **REMOVE**:")
    elif q.data == "dep":
        await sync_to_async(db_op)(uid, "state", "DEPOSITING")
        await q.edit_message_text("💵 Enter deposit amount (Min 20):")
    elif q.data == "wd":
        await sync_to_async(db_op)(uid, "state", "WITHDRAWING")
        await q.edit_message_text("🏧 Enter withdrawal amount:")
    elif q.data == "clear":
        await sync_to_async(db_op)(uid, "clear")
        await q.edit_message_text("🗑 All cards cleared! Type /start.")

async def text_handler(update, context):
    uid = update.effective_user.id
    user = await sync_to_async(db_op)(uid, "get")
    if not update.message.text.isdigit(): return
    val = int(update.message.text)

    if user.bot_state == "SELECTING":
        is_taken = await sync_to_async(lambda: User.objects.filter(selected_cards__contains=val).exclude(id=user.id).exists())()
        if is_taken: await update.message.reply_text(f"🚫 Card #{val} is taken!")
        else:
            await sync_to_async(db_op)(uid, "add", val)
            user = await sync_to_async(db_op)(uid, "get")
            if len(user.selected_cards) >= 1: # Logic: Pay for the card instantly
                game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY")
                game.players[str(uid)] = val; await sync_to_async(game.save)()
                if len(game.players) == 3:
                    asyncio.create_task(game_dealer(game.id, context))
                    await update.message.reply_text("🔥 **LOBBY FULL!** Game starts in 5 minutes.")
            await update.message.reply_text(f"✅ Card #{val} added!")

    elif user.bot_state == "REMOVING":
        await sync_to_async(db_op)(uid, "rem", val)
        await update.message.reply_text(f"🗑 Card #{val} removed!")

    elif user.bot_state == "DEPOSITING" and val >= 20:
        res, ref = await sync_to_async(init_deposit)(user, val)
        await update.message.reply_text(f"💳 [Pay {val} ETB Now]({res['data']['checkout_url']})", parse_mode='Markdown')

async def post_init(app):
    await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(btn_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ Full Commands & Timer Restored!"
