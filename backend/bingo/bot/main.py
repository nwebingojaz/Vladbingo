import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from decimal import Decimal

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR)); os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings"); django.setup()
from bingo.models import User, GameRound

async def start(update, context):
    user, _ = await sync_to_async(User.objects.get_or_create)(username=f"tg_{update.effective_user.id}")
    msg = f"🎰 **VLAD BINGO** 🎰\n💰 Balance: {user.operational_credit} ETB\n\nPick a room:"
    kbd = [[InlineKeyboardButton("💵 20 ETB", callback_data="r_20"), InlineKeyboardButton("💵 50 ETB", callback_data="r_50")]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def room_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    amt = int(q.data.split("_")[1])
    user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    if user.operational_credit < amt:
        await q.edit_message_text("❌ Insufficient Balance!"); return
    game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
    user.current_joining_room = game.id; user.bot_state = "PICKING"; await sync_to_async(user.save)()
    await q.edit_message_text(f"🎟 **Room {amt} ETB.**\nType your lucky Card Number (1-100):")

async def text_handler(update, context):
    uid = update.effective_user.id
    user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    if user.bot_state != "PICKING" or not update.message.text.isdigit(): return
    card_num = int(update.message.text)
    game = await sync_to_async(GameRound.objects.get)(id=user.current_joining_room)
    if card_num in game.players.values():
        await update.message.reply_text(f"🚫 Card #{card_num} taken in this room! Pick another:")
        return
    user.operational_credit -= game.bet_amount; user.bot_state = "IDLE"; await sync_to_async(user.save)()
    game.players[str(uid)] = card_num; await sync_to_async(game.save)()
    url = f"https://vlad-bingo-web.onrender.com/api/live/?game_id={game.id}"
    await update.message.reply_text(f"✅ **JOINED!** You are in the {game.bet_amount} ETB room.", 
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url=url))]]), parse_mode='Markdown')

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(room_handler, pattern="^r_"))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()
if __name__ == "__main__": run()
