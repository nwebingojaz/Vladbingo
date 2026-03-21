import os, sys, django, asyncio
from pathlib import Path

# Fix: Tell Python to look in the parent folder for 'bingo' and 'vlad_bingo'
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler
from bingo.models import User

async def start(update: Update, context):
    uid = update.effective_user.id
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    live_url = "https://vlad-bingo-web.onrender.com/api/live/"
    
    kbd = [
        [InlineKeyboardButton("🎮 Open Live Hall", web_app=WebAppInfo(url=live_url))],
        [InlineKeyboardButton("💰 Wallet Balance", callback_data="wallet")]
    ]
    await update.message.reply_text(
        f"Welcome to VladBingo!\n\nUser ID: {uid}\nBalance: {user.operational_credit} ETB",
        reply_markup=InlineKeyboardMarkup(kbd)
    )

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not token:
        print("ERROR: TELEGRAM_BOT_TOKEN not found in environment!")
        return
    
    app = Application.builder().token(token).build()
    app.add_handler(CommandHandler("start", start))
    print("🤖 VladBingo Bot is starting successfully...")
    app.run_polling()

if __name__ == "__main__":
    run()
