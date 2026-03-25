import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from channels.layers import get_channel_layer
from django.conf import settings

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()
from bingo.models import User, GameRound

async def start(update: Update, context):
    user, _ = await sync_to_async(User.objects.get_or_create)(username=f"tg_{update.effective_user.id}")
    user.bot_state = "IDLE"; await sync_to_async(user.save)()
    cards = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "None"
    msg = f"🎰 **VLAD BINGO** 🎰\n💰 Balance: {user.operational_credit} ETB\n🎫 Cards: {cards}"
    kbd = [[InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))],
           [InlineKeyboardButton("➕ Add Card", callback_data="add"), InlineKeyboardButton("➖ Remove", callback_data="rem")],
           [InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🏧 Withdraw", callback_data="wd")]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def btn_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    if q.data == "add": user.bot_state="SELECTING"; await q.edit_message_text("Type Card # (1-100):")
    elif q.data == "rem": user.bot_state="REMOVING"; await q.edit_message_text("Type Card # to Remove:")
    elif q.data == "dep": user.bot_state="DEPOSITING"; await q.edit_message_text("Amount to Deposit (Min 20):")
    await sync_to_async(user.save)()

async def text_handler(update, context):
    user = await sync_to_async(User.objects.get)(username=f"tg_{update.effective_user.id}")
    if not update.message.text.isdigit(): return
    val = int(update.message.text)
    if user.bot_state == "SELECTING":
        user.selected_cards.append(val); await sync_to_async(user.save)()
        await update.message.reply_text(f"✅ Added Card #{val}!")
    elif user.bot_state == "REMOVING" and val in user.selected_cards:
        user.selected_cards.remove(val); await sync_to_async(user.save)()
        await update.message.reply_text(f"🗑 Removed Card #{val}!")
    elif user.bot_state == "DEPOSITING" and val >= 20:
        from bingo.services.chapa import init_deposit
        res, ref = await sync_to_async(init_deposit)(user, val)
        await update.message.reply_text(f"💳 [Pay {val} ETB Now]({res['data']['checkout_url']})", parse_mode='Markdown')

async def new_game(update, context):
    if update.effective_user.username != "nwebingojaz": return
    game = await sync_to_async(GameRound.objects.create)(status="ACTIVE")
    await update.message.reply_text(f"🚀 Game Started!")
    nums = list(range(1, 76)); random.shuffle(nums)
    layer = get_channel_layer()
    for n in nums:
        game.called_numbers.append(n); await sync_to_async(game.save)()
        await layer.group_send("bingo_live", {"type": "bingo_message", "message": {"action": "call_number", "number": n}})
        await asyncio.sleep(7)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start)); app.add_handler(CommandHandler("newgame", new_game))
    app.add_handler(CallbackQueryHandler(btn_handler)); app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()
if __name__ == "__main__": run()
