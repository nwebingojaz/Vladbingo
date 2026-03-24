import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from channels.layers import get_channel_layer

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from bingo.models import User, GameRound
from bingo.services.chapa import init_deposit

def db_get_user(uid, name):
    return User.objects.get_or_create(username=f"tg_{uid}", defaults={'first_name': name})[0]

async def start(update: Update, context):
    user = await sync_to_async(db_get_user)(update.effective_user.id, update.effective_user.first_name)
    user.bot_state = "IDLE"
    await sync_to_async(user.save)()
    cards_text = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "None"
    msg = (f"🎰 **VLAD BINGO** 🎰\n\n🎫 **Your Cards:** {cards_text}\n💰 **Balance:** {user.operational_credit} ETB\n\nPick an action:")
    kbd = [[InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))],
           [InlineKeyboardButton("➕ Add Card", callback_data="add"), InlineKeyboardButton("➖ Remove", callback_data="rem")],
           [InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🏧 Withdraw", callback_data="wd")]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def button_handler(update, context):
    q = update.callback_query
    user = await sync_to_async(db_get_user)(q.from_user.id, "")
    await q.answer()
    if q.data == "add": 
        user.bot_state = "SELECTING"
        await q.edit_message_text("🔢 Type a card number (1-100) to **ADD**:")
    elif q.data == "rem":
        user.bot_state = "REMOVING"
        await q.edit_message_text("🔢 Type the card number to **REMOVE**:")
    elif q.data == "dep":
        user.bot_state = "DEPOSITING"
        await q.edit_message_text("💵 Amount to deposit? (Min 20):")
    await sync_to_async(user.save)()

async def text_handler(update, context):
    user = await sync_to_async(db_get_user)(update.effective_user.id, "")
    text = update.message.text
    if not text.isdigit(): return
    val = int(text)
    if user.bot_state == "SELECTING":
        is_taken = await sync_to_async(lambda: User.objects.filter(selected_cards__contains=val).exists())()
        if is_taken: await update.message.reply_text(f"🚫 Card #{val} is taken!")
        else:
            user.selected_cards.append(val)
            await sync_to_async(user.save)()
            await update.message.reply_text(f"✅ Added Card #{val}! Type /start to play.")
    elif user.bot_state == "DEPOSITING" and val >= 20:
        res, ref = await sync_to_async(init_deposit)(user, val)
        await update.message.reply_text(f"💳 [Pay {val} ETB Now]({res['data']['checkout_url']})", parse_mode='Markdown')

async def new_game(update, context):
    if update.effective_user.username != "nwebingojaz": return
    game = await sync_to_async(GameRound.objects.create)(status="ACTIVE")
    await update.message.reply_text(f"🚀 Game #{game.id} Started!")
    nums = list(range(1, 76))
    random.shuffle(nums)
    layer = get_channel_layer()
    for n in nums:
        game.called_numbers.append(n); await sync_to_async(game.save)()
        await layer.group_send("bingo_live", {"type": "bingo_message", "message": {"action": "call_number", "number": n}})
        await asyncio.sleep(7)

async def post_init(app): await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("newgame", new_game))
    app.add_handler(CallbackQueryHandler(button_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()

if __name__ == "__main__": run()
