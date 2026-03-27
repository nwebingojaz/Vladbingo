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
from bingo.services.chapa import init_deposit

def db_op(uid, action, val=None):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    if action == "state": user.bot_state = val
    elif action == "clear": user.selected_cards = []
    user.save(); return user

async def start(update: Update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    if not user.real_name:
        await sync_to_async(db_op)(user.id, "state", "REG_NAME")
        return await update.message.reply_text("👋 Welcome! Enter your **Full Name** to register:")
    if not user.phone_number:
        btn = [[KeyboardButton("📲 Share Phone", request_contact=True)]]
        return await update.message.reply_text("Tap to verify phone:", reply_markup=ReplyKeyboardMarkup(btn, one_time_keyboard=True, resize_keyboard=True))

    active_games = await sync_to_async(lambda: list(GameRound.objects.filter(status__in=["LOBBY","STARTING","ACTIVE"])))()
    user_games = [g for g in active_games if str(update.effective_user.id) in g.players]
    kbd = []
    for g in user_games:
        url = f"https://vlad-bingo-web.onrender.com/api/live/?game_id={g.id}"
        kbd.append([InlineKeyboardButton(f"🎮 ENTER {int(g.bet_amount)} ETB HALL (Room #{g.id})", web_app=WebAppInfo(url=url))])
    
    kbd.append([InlineKeyboardButton("💵 Join 20", callback_data="r_20"), InlineKeyboardButton("💵 Join 50", callback_data="r_50")])
    kbd.append([InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🗑 Clear", callback_data="clear")])
    msg = f"🎰 **VLAD BINGO** 🎰\n👤 Player: {user.real_name}\n💰 Balance: {user.operational_credit} ETB"
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def btn_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    user = await sync_to_async(db_op)(uid, "get")
    if q.data.startswith("r_"):
        amt = int(q.data.split("_")[1])
        if user.operational_credit < amt: await q.edit_message_text("❌ Low Balance!"); return
        game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
        user.current_joining_room = game.id; user.bot_state = "PICKING"; await sync_to_async(user.save)()
        await q.edit_message_text(f"🎟 **{amt} ETB Room.** Type Card # (1-100):")
    elif q.data == "dep": 
        await sync_to_async(db_op)(uid, "state", "DEPOSITING")
        await q.edit_message_text("💵 Enter deposit amount (Min 20):")
    elif q.data == "clear":
        await sync_to_async(db_op)(uid, "clear")
        await q.edit_message_text("🗑 Cards cleared!")

async def text_handler(update, context):
    uid = update.effective_user.id; user = await sync_to_async(db_op)(uid, "get")
    text = update.message.text
    if user.bot_state == "REG_NAME":
        user.real_name = text; user.bot_state = "IDLE"; await sync_to_async(user.save)()
        await update.message.reply_text(f"✅ Hello {text}!"); await start(update, context)
    elif text.isdigit():
        val = int(text)
        if user.bot_state == "PICKING":
            game = await sync_to_async(GameRound.objects.get)(id=user.current_joining_room)
            if val in game.players.values(): await update.message.reply_text("🚫 Taken!"); return
            user.operational_credit -= game.bet_amount; user.selected_cards.append(val); user.bot_state = "IDLE"; await sync_to_async(user.save)()
            game.players[str(uid)] = val; await sync_to_async(game.save)()
            await update.message.reply_text(f"✅ Joined! Type /start for the button.")
        elif user.bot_state == "DEPOSITING" and val >= 20:
            res, ref = await sync_to_async(init_deposit)(user, val)
            await update.message.reply_text(f"💳 [Click to pay {val} ETB]({res['data']['checkout_url']})", parse_mode='Markdown')

async def contact_handler(update: Update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    user.phone_number = update.message.contact.phone_number; user.bot_state = "IDLE"; await sync_to_async(user.save)()
    await update.message.reply_text("🎉 Verified!", reply_markup=ReplyKeyboardRemove()); await start(update, context)

async def post_init(app): await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(btn_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.add_handler(MessageHandler(filters.CONTACT, contact_handler))
    app.run_polling()
if __name__ == "__main__": run()
