import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from channels.layers import get_channel_layer
from decimal import Decimal

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR)); os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings"); django.setup()
from bingo.models import User, GameRound

async def game_dealer(game_id):
    await asyncio.sleep(300) # 5 MINUTE TIMER
    game = await sync_to_async(GameRound.objects.get)(id=game_id)
    game.status = "ACTIVE"; await sync_to_async(game.save)()
    nums = list(range(1, 76)); random.shuffle(nums)
    layer = get_channel_layer()
    for n in nums:
        game.refresh_from_db()
        if "WON" in game.status: break
        game.called_numbers.append(n); await sync_to_async(game.save)()
        await layer.group_send(f"game_{game_id}", {"type": "bingo_message", "message": {"action": "call_number", "number": n}})
        await asyncio.sleep(7)

async def start(update: Update, context):
    user, _ = await sync_to_async(User.objects.get_or_create)(username=f"tg_{update.effective_user.id}")
    user.bot_state = "IDLE"; await sync_to_async(user.save)()
    msg = f"🎰 **VLAD BINGO PLATFORM** 🎰\n💰 Balance: {user.operational_credit} ETB\n\nPick a room to join:"
    kbd = [[InlineKeyboardButton("💵 20 ETB", callback_data="room_20"), InlineKeyboardButton("💵 40 ETB", callback_data="room_40")],
           [InlineKeyboardButton("💵 50 ETB", callback_data="room_50"), InlineKeyboardButton("💵 100 ETB", callback_data="room_100")]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def room_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    amt = int(q.data.split("_")[1]); user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    if user.operational_credit < amt: await q.edit_message_text("❌ Insufficient Balance!"); return
    game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
    user.current_joining_room = game.id; user.bot_state = "PICKING"; await sync_to_async(user.save)()
    await q.edit_message_text(f"🎟 **Room {amt} ETB.**\nType your Card Number (1-100):")

async def text_handler(update, context):
    uid = update.effective_user.id; user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    if user.bot_state != "PICKING" or not update.message.text.isdigit(): return
    val = int(update.message.text)
    game = await sync_to_async(GameRound.objects.get)(id=user.current_joining_room)
    if val in game.players.values(): await update.message.reply_text("🚫 Taken!"); return
    user.operational_credit -= game.bet_amount; user.bot_state = "IDLE"; await sync_to_async(user.save)()
    game.players[str(uid)] = val; await sync_to_async(game.save)()
    url = f"https://vlad-bingo-web.onrender.com/api/live/?game_id={game.id}"
    if len(game.players) == 3:
        game.status = "STARTING"; await sync_to_async(game.save)()
        asyncio.create_task(game_dealer(game.id))
        await update.message.reply_text(f"✅ **LOBBY FULL!** {game.bet_amount} ETB Game starts in 5 minutes.", 
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url=url))]]))
    else:
        await update.message.reply_text(f"✅ Joined! Lobby: {len(game.players)}/3.", 
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url=url))]]))

async def post_init(app): await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(room_handler, pattern="^room_"))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()
if __name__ == "__main__": run()
