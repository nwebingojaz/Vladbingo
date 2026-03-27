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

def db_get_user(uid): return User.objects.get_or_create(username=f"tg_{uid}")[0]

async def start(update: Update, context):
    user = await sync_to_async(db_get_user)(update.effective_user.id)
    if not user.real_name:
        user.bot_state = "REG_NAME"; await sync_to_async(user.save)()
        await update.message.reply_text("👋 Welcome! Enter your **Full Name** to register:")
        return

    active_games = await sync_to_async(lambda: list(GameRound.objects.filter(status__in=["LOBBY","STARTING","ACTIVE"])))()
    user_games = [g for g in active_games if str(update.effective_user.id) in g.players]
    
    kbd = []
    for g in user_games:
        url = f"https://vlad-bingo-web.onrender.com/api/live/?game_id={g.id}"
        icon = "🔥" if g.status == "ACTIVE" else "⏳"
        kbd.append([InlineKeyboardButton(f"{icon} OPEN {int(g.bet_amount)} ETB HALL (Game #{g.id})", web_app=WebAppInfo(url=url))])

    kbd.append([InlineKeyboardButton("💵 20", callback_data="r_20"), InlineKeyboardButton("💵 30", callback_data="r_30"), InlineKeyboardButton("💵 40", callback_data="r_40")])
    kbd.append([InlineKeyboardButton("💵 50", callback_data="r_50"), InlineKeyboardButton("💵 100", callback_data="r_100")])
    kbd.append([InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🏧 Withdraw", callback_data="wd")])
    
    msg = f"🎰 **VLAD BINGO PLATFORM** 🎰\n👤 Player: {user.real_name}\n💰 Balance: {user.operational_credit} ETB\n\nPick a room or Enter Hall:"
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def game_dealer(game_id):
    await asyncio.sleep(300) # 5 Min Timer
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
    user = await sync_to_async(db_get_user)(uid)
    if q.data.startswith("r_"):
        amt = int(q.data.split("_")[1])
        if user.operational_credit < amt: await q.edit_message_text("❌ Low Balance!"); return
        game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
        user.current_joining_room = game.id; user.bot_state = "PICKING"; await sync_to_async(user.save)()
        await q.edit_message_text(f"🎟 **Room {amt} ETB.** Type lucky Card # (1-100):")

async def text_handler(update, context):
    uid = update.effective_user.id; user = await sync_to_async(db_get_user)(uid)
    text = update.message.text
    if user.bot_state == "REG_NAME":
        user.real_name = text; user.bot_state = "IDLE"; await sync_to_async(user.save)()
        await update.message.reply_text(f"✅ Registered! Type /start."); return
    if text.isdigit() and user.bot_state == "PICKING":
        val = int(text); game = await sync_to_async(GameRound.objects.get)(id=user.current_joining_room)
        if val in game.players.values(): await update.message.reply_text("🚫 Taken!"); return
        user.operational_credit -= game.bet_amount; user.bot_state = "IDLE"; await sync_to_async(user.save)()
        game.players[str(uid)] = val; await sync_to_async(game.save)()
        if len(game.players) == 3:
            game.status = "STARTING"; await sync_to_async(game.save)()
            asyncio.create_task(game_dealer(game.id))
            await update.message.reply_text("🔥 **LOBBY FULL!** 5 mins until start.")
        else: await update.message.reply_text(f"✅ Joined! Lobby {len(game.players)}/3. Type /start to see button.")

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(btn_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()
if __name__ == "__main__": run()
