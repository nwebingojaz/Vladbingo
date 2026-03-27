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
        await update.message.reply_text("👋 Welcome! Please enter your **Full Name** to register:")
        return

    # Check for active games joined by user
    active_games = await sync_to_async(lambda: list(GameRound.objects.filter(status__in=["LOBBY","STARTING","ACTIVE"])))()
    user_games = [g for g in active_games if str(update.effective_user.id) in g.players]
    
    kbd = []
    for g in user_games:
        url = f"https://vlad-bingo-web.onrender.com/api/live/?game_id={g.id}"
        kbd.append([InlineKeyboardButton(f"🎮 ENTER {int(g.bet_amount)} ETB HALL (Room #{g.id})", web_app=WebAppInfo(url=url))])

    kbd.append([InlineKeyboardButton("💵 Join 20 ETB", callback_data="join_20"), InlineKeyboardButton("💵 Join 50 ETB", callback_data="join_50")])
    kbd.append([InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🏧 Withdraw", callback_data="wd")])
    
    msg = f"🎰 **VLAD BINGO** 🎰\n💰 Balance: {user.operational_credit} ETB\n\nPick a room to join or enter your active hall:"
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def btn_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    user = await sync_to_async(db_get_user)(uid)
    if q.data.startswith("join_"):
        amt = int(q.data.split("_")[1])
        if user.operational_credit < amt: await q.edit_message_text("❌ Low Balance!"); return
        game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
        user.current_room_context = game.id; user.bot_state = "ROOM_LOBBY"; await sync_to_async(user.save)()
        
        # Room Sub-Menu
        sub_kbd = [[InlineKeyboardButton("➕ Add Card", callback_data="sub_add"), InlineKeyboardButton("➖ Remove Card", callback_data="sub_rem")],
                   [InlineKeyboardButton("⬅️ Back to Menu", callback_data="sub_back")]]
        await q.edit_message_text(f"🎟 **{amt} ETB Room.** Lobby: {len(game.players)}/3\nPick an action:", reply_markup=InlineKeyboardMarkup(sub_kbd))

    elif q.data == "sub_add":
        user.bot_state = "ADD_CARD"; await sync_to_async(user.save)()
        await q.edit_message_text("🔢 Type Card # (1-100) to **ADD** to this room:")
    elif q.data == "sub_rem":
        user.bot_state = "REM_CARD"; await sync_to_async(user.save)()
        await q.edit_message_text("🔢 Type Card # to **REMOVE** from this room:")
    elif q.data == "sub_back": await start(update.callback_query, context)

async def text_handler(update, context):
    uid = update.effective_user.id; user = await sync_to_async(db_get_user)(uid)
    text = update.message.text
    if user.bot_state == "REG_NAME":
        user.real_name = text; user.bot_state = "IDLE"; await sync_to_async(user.save)()
        await update.message.reply_text(f"✅ Hello {text}!"); await start(update, context)
    elif text.isdigit():
        val = int(text); game = await sync_to_async(GameRound.objects.get)(id=user.current_room_context)
        if user.bot_state == "ADD_CARD":
            if val in game.players.values(): await update.message.reply_text("🚫 Taken!"); return
            # Multi-card logic
            current_cards = game.players.get(str(uid), [])
            if not isinstance(current_cards, list): current_cards = [current_cards]
            current_cards.append(val); game.players[str(uid)] = current_cards
            user.operational_credit -= game.bet_amount; await sync_to_async(user.save)(); await sync_to_async(game.save)()
            await update.message.reply_text(f"✅ Card #{val} added! Type another or /start."); return
        elif user.bot_state == "REM_CARD":
             # Remove logic here
             await update.message.reply_text("🗑 Removed!"); await start(update, context)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start)); app.add_handler(CallbackQueryHandler(btn_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler)); app.run_polling()
if __name__ == "__main__": run()
