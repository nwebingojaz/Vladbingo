import os, django, asyncio
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, CallbackQueryHandler

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()
from bingo.models import User

async def start(update, context):
    uid = update.effective_user.id
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    kbd = [[InlineKeyboardButton("🎮 Join Game", callback_data="join"), 
            InlineKeyboardButton("💰 Wallet", callback_data="wallet")]]
    await update.message.reply_text(f"Welcome to VladBingo!\nBalance: {user.operational_credit} ETB", 
        reply_markup=InlineKeyboardMarkup(kbd))

def run():
    TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    print("🤖 VladBingo Bot is LIVE...")
    app.run_polling()

if __name__ == "__main__": run()
