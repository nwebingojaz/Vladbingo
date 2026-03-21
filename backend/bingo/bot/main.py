import os, django, asyncio
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()
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
        f"Welcome to VladBingo!\n\nYour current balance is: {user.operational_credit} ETB\nClick below to watch the live game.",
        reply_markup=InlineKeyboardMarkup(kbd)
    )

def run():
    TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    print("🤖 Bot is responding...")
    app.run_polling()

if __name__ == "__main__": run()
