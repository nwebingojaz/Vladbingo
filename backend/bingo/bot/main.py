import os, sys, django
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, KeyboardButton, ReplyKeyboardMarkup, ReplyKeyboardRemove, WebAppInfo
from telegram.ext import Application, CommandHandler, MessageHandler, CallbackQueryHandler, filters

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()
from bingo.models import User

def db_op(uid, action, val=None):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    if action == "name": 
        user.real_name = val
        user.bot_state = "IDLE"
    elif action == "phone": 
        user.phone_number = val
        user.bot_state = "IDLE"
    elif action == "state": 
        user.bot_state = val
    user.save()
    return user

async def send_main_menu(update: Update, user):
    photo_url = "https://images.unsplash.com/photo-1518133910546-b6c2fb7d79e3?q=80&w=1000&auto=format&fit=crop"
    caption = f"🎰 **VLAD BINGO PRO** 🎰\n\nWelcome back, **{user.real_name}**!\n💰 **Balance:** {user.operational_credit} ETB\n\nChoose an option below:"
    web_app_url = "https://vlad-bingo-web.onrender.com/api/live/"
    
    keyboard = [
        [InlineKeyboardButton("Play Games 🎮", web_app=WebAppInfo(url=web_app_url))],
        [InlineKeyboardButton("Deposit 💰", callback_data="deposit"), InlineKeyboardButton("Withdraw 💸", callback_data="withdraw")],
        [InlineKeyboardButton("Transfer ↔️", callback_data="transfer"), InlineKeyboardButton("My Profile 👤", callback_data="profile")],
        [InlineKeyboardButton("Transactions 📜", callback_data="history"), InlineKeyboardButton("Balance ⚖️", callback_data="balance")],
        [InlineKeyboardButton("Join Group ↗️", url="https://t.me/+t8ito3eKejo4OGU0"), InlineKeyboardButton("Contact Us 🎧", callback_data="contact")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)

    if update.message:
        await update.message.reply_photo(photo=photo_url, caption=caption, reply_markup=reply_markup, parse_mode='Markdown')

async def start(update: Update, context):
    tg_id = update.effective_user.id
    user = await sync_to_async(db_op)(tg_id, "get")
    
    if not user.real_name:
        await sync_to_async(db_op)(tg_id, "state", "REG_NAME")
        return await update.message.reply_text("👋 Welcome to VLAD BINGO PRO!\n\nPlease enter your **Full Name** to register:")
        
    if not user.phone_number:
        btn = [[KeyboardButton("📲 Share Phone", request_contact=True)]]
        return await update.message.reply_text("Tap the button below to verify your phone number:", reply_markup=ReplyKeyboardMarkup(btn, one_time_keyboard=True, resize_keyboard=True))
    
    await send_main_menu(update, user)

async def handle_text(update, context):
    tg_id = update.effective_user.id
    user = await sync_to_async(db_op)(tg_id, "get")
    if user.bot_state == "REG_NAME":
        await sync_to_async(db_op)(tg_id, "name", update.message.text)
        await start(update, context)

async def handle_contact(update, context):
    tg_id = update.effective_user.id
    await sync_to_async(db_op)(tg_id, "phone", update.message.contact.phone_number)
    await update.message.reply_text("✅ Phone Verified Successfully!", reply_markup=ReplyKeyboardRemove())
    await start(update, context)

async def handle_buttons(update: Update, context):
    query = update.callback_query
    user = await sync_to_async(db_op)(query.from_user.id, "get")
    
    if query.data == "balance":
        await query.answer(f"💰 Your Balance is {user.operational_credit} ETB", show_alert=True)
    elif query.data == "profile":
        await query.answer(f"👤 Name: {user.real_name}\n📱 Phone: {user.phone_number}", show_alert=True)
    elif query.data in ["deposit", "withdraw", "transfer", "history", "contact"]:
        await query.answer("⏳ This feature is coming soon!", show_alert=True)
    else:
        await query.answer()

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(lambda a: a.bot.delete_webhook(drop_pending_updates=True)).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    app.add_handler(MessageHandler(filters.CONTACT, handle_contact))
    app.add_handler(CallbackQueryHandler(handle_buttons))
    app.run_polling()

if __name__ == "__main__": 
    run()
