import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo, KeyboardButton, ReplyKeyboardMarkup, ReplyKeyboardRemove
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
    elif action == "add": user.selected_cards.append(val)
    elif action == "rem": user.selected_cards.remove(val)
    user.save(); return user

async def start(update: Update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    if not user.real_name:
        await sync_to_async(db_op)(user.id, "state", "REG_NAME")
        await update.message.reply_text("👋 Welcome! Please enter your Full Name:")
        return
    txt = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "None"
    msg = f"🎰 **VLAD BINGO** 🎰\n💰 Balance: {user.operational_credit} ETB\n🎫 Cards: {txt}"
    kbd = [[InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))],
           [InlineKeyboardButton("💵 20 ETB", callback_data="bet_20"), InlineKeyboardButton("💵 50 ETB", callback_data="bet_50")],
           [InlineKeyboardButton("➕ Add Card", callback_data="add"), InlineKeyboardButton("➖ Remove", callback_data="rem")]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def game_loop(game_id):
    await asyncio.sleep(300) # 5 Minute Timer
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
    user = await sync_to_async(db_op)(uid, "get")
    if q.data.startswith("bet_"):
        amt = int(q.data.split("_")[1])
        if user.operational_credit < amt: await q.edit_message_text("❌ Low Balance!"); return
        game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY")
        game.players[str(uid)] = user.selected_cards[-1] if user.selected_cards else 1
        game.bet_amount = Decimal(amt); await sync_to_async(game.save)()
        user.operational_credit -= Decimal(amt); await sync_to_async(user.save)()
        if len(game.players) == 3:
            game.status = "STARTING"; await sync_to_async(game.save)()
            asyncio.create_task(game_loop(game.id))
            await q.edit_message_text("🔥 **LOBBY FULL!** Game starts in 5 minutes.")
        else: await q.edit_message_text(f"✅ Joined! Lobby: {len(game.players)}/3")
    elif q.data == "add": await sync_to_async(db_op)(uid, "state", "SELECTING"); await q.edit_message_text("🔢 Type Card #:")

async def text_handler(update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    if user.bot_state == "REG_NAME":
        user.real_name = update.message.text; user.bot_state = "IDLE"; await sync_to_async(user.save)()
        await update.message.reply_text(f"✅ Registered as {user.real_name}!"); await start(update, context)
    elif update.message.text.isdigit() and user.bot_state == "SELECTING":
        await sync_to_async(db_op)(user.id, "add", int(update.message.text))
        await update.message.reply_text("✅ Card Added!"); await start(update, context)

async def post_init(app): await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(btn_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()
if __name__ == "__main__": run()
