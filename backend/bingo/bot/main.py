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

def db_op(uid, action, val=None):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    if action == "name": user.real_name = val; user.bot_state = "IDLE"
    elif action == "phone": user.phone_number = val; user.bot_state = "IDLE"
    user.save(); return user

async def game_dealer(game_id):
    await asyncio.sleep(300)
    game = await sync_to_async(GameRound.objects.get)(id=game_id)
    game.status = "ACTIVE"; await sync_to_async(game.save)()
    nums = list(range(1, 76)); random.shuffle(nums)
    layer = get_channel_layer()
    for n in nums:
        game.refresh_from_db()
        if "WON" in game.status or game.status == "ENDED": break
        game.called_numbers.append(n); await sync_to_async(game.save)()
        await layer.group_send("bingo_live", {"type": "bingo_message", "message": {"action": "call_number", "number": n}})
        await asyncio.sleep(7)

async def start(update: Update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    if not user.real_name:
        await sync_to_async(db_op)(user.id, "state", "REG_NAME")
        return await update.message.reply_text("👋 Welcome! Please enter your **Full Name** to register:")
    if not user.phone_number:
        btn = [[KeyboardButton("📲 Share Phone Number", request_contact=True)]]
        return await update.message.reply_text("Tap below to verify your phone:", reply_markup=ReplyKeyboardMarkup(btn, one_time_keyboard=True, resize_keyboard=True))

    active_games = await sync_to_async(lambda: list(GameRound.objects.exclude(status="ENDED")))()
    user_games = [g for g in active_games if str(update.effective_user.id) in g.players]
    
    kbd = []
    for g in user_games:
        url = f"https://vlad-bingo-web.onrender.com/api/live/?game_id={g.id}"
        kbd.append([InlineKeyboardButton(f"🎮 ENTER {int(g.bet_amount)} ETB HALL", web_app=WebAppInfo(url=url))])
    
    kbd.append([InlineKeyboardButton("💵 Join 20", callback_data="r_20"), InlineKeyboardButton("💵 Join 30", callback_data="r_30"), InlineKeyboardButton("💵 Join 40", callback_data="r_40")])
    kbd.append([InlineKeyboardButton("💵 Join 50", callback_data="r_50"), InlineKeyboardButton("💵 Join 100", callback_data="r_100")])
    kbd.append([InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🗑 Clear/Refund", callback_data="clear")])
    msg = f"🎰 **VLAD BINGO HALL** 🎰\n👤 Player: {user.real_name}\n💰 Balance: {user.operational_credit} ETB"
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def btn_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    user = await sync_to_async(db_op)(uid, "get")
    if q.data.startswith("r_"):
        amt = int(q.data.split("_")[1])
        if user.operational_credit < amt: await q.edit_message_text("❌ Low Balance!"); return
        game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
        user.current_room_id = game.id; user.bot_state = "PICKING"; await sync_to_async(user.save)()
        await q.edit_message_text(f"🎟 **{amt} ETB Room.** Type lucky Card # (1-100):")
    elif q.data == "clear":
        games = await sync_to_async(lambda: list(GameRound.objects.filter(status="LOBBY")))()
        for g in games:
            if str(uid) in g.players:
                user.operational_credit += g.bet_amount
                del g.players[str(uid)]; await sync_to_async(g.save)()
        user.selected_cards = []; await sync_to_async(user.save)()
        await q.edit_message_text("🗑 Cards cleared and money refunded!")

async def text_handler(update, context):
    uid = update.effective_user.id; user = await sync_to_async(db_op)(uid, "get")
    if user.bot_state == "REG_NAME":
        await sync_to_async(db_op)(uid, "name", update.message.text); await start(update, context)
    elif update.message.text.isdigit() and user.bot_state == "PICKING":
        val = int(update.message.text); game = await sync_to_async(GameRound.objects.get)(id=user.current_room_id)
        if val in game.players.values(): await update.message.reply_text("🚫 Taken!"); return
        user.operational_credit -= game.bet_amount; user.selected_cards.append(val); user.bot_state = "IDLE"
        game.players[str(uid)] = [val]; await sync_to_async(user.save)(); await sync_to_async(game.save)()
        if len(game.players) == 3: asyncio.create_task(game_dealer(game.id))
        await update.message.reply_text(f"✅ Card #{val} Added!"); await start(update, context)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(lambda a: a.bot.delete_webhook(drop_pending_updates=True)).build()
    app.add_handler(CommandHandler("start", start)); app.add_handler(CallbackQueryHandler(btn_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler)); app.add_handler(MessageHandler(filters.CONTACT, lambda u,c: None))
    app.run_polling()
if __name__ == "__main__": run()
