import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler
from channels.layers import get_channel_layer
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
    user = await sync_to_async(db_get_user)(update.effective_user.id)
    cards_txt = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "None"
    msg = f"🎰 **VLAD BINGO** 🎰\n💰 Balance: {user.operational_credit} ETB\n🎫 Cards: {cards_txt}\n\nPick Buy-in:"
    kbd = [[InlineKeyboardButton("💵 20", callback_data="bet_20"), InlineKeyboardButton("💵 40", callback_data="bet_40")],
           [InlineKeyboardButton("🎮 LIVE HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def new_game(update: Update, context):
    if update.effective_user.username != "nwebingojaz": return
    game = await sync_to_async(GameRound.objects.filter(status="LOBBY").first)()
    if not game or len(game.players) < 3:
        await update.message.reply_text("❌ Need 3 players to start.")
        return

    game.status = "ACTIVE"; await sync_to_async(game.save)()
    await update.message.reply_text(f"🚀 **GAME STARTED!**\nCards playing: {list(game.players.values())}")

    nums = list(range(1, 76)); random.shuffle(nums)
    layer = get_channel_layer()
    
    winner_found = False
    for n in nums:
        game.refresh_from_db()
        if "WON_BY" in game.status:
            winner_card = game.status.split("_")[-1]
            await update.message.reply_text(f"🏆 **BINGO!**\nWinner Card: **#{winner_card}**\nGame Over.")
            winner_found = True
            break
        
        game.called_numbers.append(n); await sync_to_async(game.save)()
        await layer.group_send("bingo_live", {"type": "bingo_message", "message": {"action": "call_number", "number": n}})
        await asyncio.sleep(7)
    
    if not winner_found:
        await update.message.reply_text("🏁 Game ended with no winner.")

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start)); app.add_handler(CommandHandler("newgame", new_game))
    app.run_polling()

if __name__ == "__main__": run()
