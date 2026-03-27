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

def db_get_user(uid):
    return User.objects.get_or_create(username=f"tg_{uid}")[0]

async def start(update: Update, context):
    user = await sync_to_async(db_get_user)(update.effective_user.id)
    if not user.real_name:
        user.bot_state = "REG_NAME"; await sync_to_async(user.save)()
        await update.message.reply_text("👋 **Welcome!**\nPlease enter your **Full Name** to register:")
        return
    if not user.phone_number:
        btn = [[KeyboardButton("📲 Share Phone Number", request_contact=True)]]
        await update.message.reply_text("Tap below to verify your phone number:", 
            reply_markup=ReplyKeyboardMarkup(btn, one_time_keyboard=True, resize_keyboard=True))
        return
    msg = f"🎰 **VLAD BINGO** 🎰\n👤 Player: {user.real_name}\n💰 Balance: {user.operational_credit} ETB\n\nPick a Room:"
    kbd = [[InlineKeyboardButton("💵 20", callback_data="r_20"), InlineKeyboardButton("💵 40", callback_data="r_40")],
           [InlineKeyboardButton("💵 100", callback_data="r_100")],
           [InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))],
           [InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🗑 Clear", callback_data="clear")]]
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
    elif q.data == "dep": 
        user.bot_state = "DEPOSITING"; await sync_to_async(user.save)()
        await q.edit_message_text("💵 Amount to deposit? (Min 20):")

async def text_handler(update, context):
    uid = update.effective_user.id; user = await sync_to_async(db_get_user)(uid)
    if user.bot_state == "REG_NAME":
        user.real_name = update.message.text; user.bot_state = "IDLE"; await sync_to_async(user.save)()
        await update.message.reply_text(f"✅ Hello {user.real_name}!"); await start(update, context)
    elif update.message.text.isdigit():
        val = int(update.message.text)
        if user.bot_state == "PICKING":
            game = await sync_to_async(GameRound.objects.get)(id=user.current_joining_room)
            if val in game.players.values(): await update.message.reply_text("🚫 Taken!"); return
            user.operational_credit -= game.bet_amount; user.selected_cards.append(val); user.bot_state = "IDLE"; await sync_to_async(user.save)()
            game.players[str(uid)] = val; await sync_to_async(game.save)()
            if len(game.players) == 3:
                game.status = "STARTING"; await sync_to_async(game.save)()
                asyncio.create_task(game_dealer(game.id)); await update.message.reply_text("🔥 **LOBBY FULL!** 5 mins to start.")
            else: await update.message.reply_text(f"✅ Joined! Lobby {len(game.players)}/3")
        elif user.bot_state == "DEPOSITING" and val >= 20:
            from bingo.services.chapa import init_deposit
            res, ref = await sync_to_async(init_deposit)(user, val)
            await update.message.reply_text(f"💳 [Pay {val} ETB Now]({res['data']['checkout_url']})", parse_mode='Markdown')

async def contact_handler(update: Update, context):
    user = await sync_to_async(db_get_user)(update.effective_user.id)
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
