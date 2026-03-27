#!/bin/bash
# VladBingo - Multi-Room Navigation & Switching Logic

# 1. Update Bot Main (Multi-Button Detection)
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo, KeyboardButton, ReplyKeyboardMarkup, ReplyKeyboardRemove
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from django.db.models import Q
from decimal import Decimal

# Setup Paths
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from bingo.models import User, GameRound

def db_get_user(uid):
    return User.objects.get_or_create(username=f"tg_{uid}")[0]

async def start(update: Update, context):
    uid = update.effective_user.id
    user = await sync_to_async(db_get_user)(uid)
    
    # 1. Registration Check
    if not user.real_name:
        user.bot_state = "REG_NAME"; await sync_to_async(user.save)()
        await update.message.reply_text("👋 **Welcome!** Please enter your Full Name:")
        return

    # 2. Find ALL Games the user has joined that are not finished
    active_games = await sync_to_async(lambda: list(GameRound.objects.filter(
        status__in=["LOBBY", "STARTING", "ACTIVE"]
    )))()
    
    # Filter games where the user is a player
    user_games = [g for g in active_games if str(uid) in g.players]
    
    # 3. Build Buttons
    kbd = []
    
    # ADD A BUTTON FOR EVERY ACTIVE GAME
    for game in user_games:
        status_icon = "⏳" if game.status != "ACTIVE" else "🔥"
        url = f"https://vlad-bingo-web.onrender.com/api/live/?game_id={game.id}"
        kbd.append([InlineKeyboardButton(f"{status_icon} ENTER {int(game.bet_amount)} ETB HALL (Game #{game.id})", web_app=WebAppInfo(url=url))])
    
    # Standard Menu Buttons
    kbd.append([InlineKeyboardButton("💵 20 ETB", callback_data="r_20"), InlineKeyboardButton("💵 50 ETB", callback_data="r_50")])
    kbd.append([InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🏧 Withdraw", callback_data="wd")])
    
    msg = (f"🎰 **VLAD BINGO PLATFORM** 🎰\n"
           f"👤 **Player:** {user.real_name}\n"
           f"💰 **Balance:** {user.operational_credit} ETB\n\n"
           f"You are currently in **{len(user_games)}** games.\n"
           f"Pick a room to join another or click a Hall to play:")
    
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def btn_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    user = await sync_to_async(db_get_user)(uid)
    
    if q.data.startswith("r_"):
        amt = int(q.data.split("_")[1])
        if user.operational_credit < amt: await q.edit_message_text("❌ Low Balance!"); return
        
        # Check if user is already in a lobby for this amount
        existing = await sync_to_async(lambda: GameRound.objects.filter(status="LOBBY", bet_amount=amt).first())()
        if existing and str(uid) in existing.players:
            await q.edit_message_text(f"⚠️ You are already in the {amt} ETB Lobby!")
            return

        user.current_joining_room = amt # Temporary storage
        user.bot_state = "PICKING"; await sync_to_async(user.save)()
        await q.edit_message_text(f"🎟 **Room {amt} ETB.**\nType your lucky Card Number (1-100):")

async def text_handler(update, context):
    uid = update.effective_user.id
    user = await sync_to_async(db_get_user)(uid)
    text = update.message.text
    
    if user.bot_state == "REG_NAME":
        user.real_name = text; user.bot_state = "IDLE"; await sync_to_async(user.save)()
        await update.message.reply_text(f"✅ Welcome {text}!"); await start(update, context)
        
    elif user.bot_state == "PICKING" and text.isdigit():
        val = int(text)
        amt = user.current_joining_room
        game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
        
        if val in game.players.values():
            await update.message.reply_text(f"🚫 Card #{val} is taken in this room! Pick another:")
            return
            
        user.operational_credit -= Decimal(amt); user.bot_state = "IDLE"; await sync_to_async(user.save)()
        game.players[str(uid)] = val; await sync_to_async(game.save)()
        
        await update.message.reply_text(f"✅ **Joined!** Card #{val} confirmed for {amt} ETB Room.\nType /start to see your Hall buttons.")

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(btn_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ Multi-Room Management Applied!"
