#!/bin/bash
# VladBingo - Automated Dealer & Multi-Card Warning

# 1. Update the Bot Main with the Automated Caller
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from channels.layers import get_channel_layer

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from bingo.models import User, GameRound

def get_user_db(uid, name):
    return User.objects.get_or_create(username=f"tg_{uid}", defaults={'first_name': name})[0]

async def start(update: Update, context):
    user = await sync_to_async(get_user_db)(update.effective_user.id, update.effective_user.first_name)
    
    # Logic for Multi-Card Warning
    cards = user.selected_cards
    main_card = cards[0] if cards else 0
    cards_text = ", ".join([f"#{c}" for c in cards]) if cards else "None"
    
    warning = ""
    if len(cards) > 1:
        warning = f"\n\n⚠️ **Note:** Only Card #{main_card} is visible in the App. Please use physical boards for your other cards: {', '.join([f'#{c}' for c in cards[1:]])}"

    msg = (f"🎰 **VLAD BINGO HALL** 🎰\n\n"
           f"🎫 **Your Cards:** {cards_text}\n"
           f"💰 **Balance:** {user.operational_credit} ETB"
           f"{warning}\n\n"
           f"Select an action:")
    
    # URL points to the hall (JS will fetch their card automatically)
    live_url = "https://vlad-bingo-web.onrender.com/api/live/"
    kbd = [[InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url=live_url))],
           [InlineKeyboardButton("➕ Add Card", callback_data="btn_add"), InlineKeyboardButton("🗑 Clear", callback_data="btn_clear")]]
    
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def new_game(update: Update, context):
    """Admin only: Starts the automated number calling"""
    if update.effective_user.username != "nwebingojaz": # Secure to your username
        await update.message.reply_text("❌ Only the Owner can start a game.")
        return

    # 1. Create a new game record
    game = await sync_to_async(GameRound.objects.create)(status="ACTIVE")
    await update.message.reply_text(f"🚀 **BINGO GAME #{game.id} STARTED!**\nNumbers are being called every 7 seconds.", parse_mode='Markdown')

    # 2. Start the calling loop
    all_nums = list(range(1, 76))
    random.shuffle(all_nums)
    channel_layer = get_channel_layer()

    for num in all_nums:
        # Save to DB
        game.called_numbers.append(num)
        await sync_to_async(game.save)()
        
        # Send to all Mini Apps via WebSocket
        await channel_layer.group_send("bingo_live", {
            "type": "bingo_message",
            "message": {"action": "call_number", "number": num}
        })
        
        await asyncio.sleep(7) # 7 seconds between calls

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("newgame", new_game))
    app.run_polling()

if __name__ == "__main__": run()
EOF

echo "✅ Game Engine & Dealer Loop Applied!"
