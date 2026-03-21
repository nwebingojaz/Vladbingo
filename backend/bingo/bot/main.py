import os, django, asyncio
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()
from bingo.models import User

async def start(update: Update, context):
    uid = update.effective_user.id
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    
    # This is the "Magic" button that opens the Mini App
    live_url = "https://vlad-bingo-web.onrender.com/api/live/"
    
    kbd = [
        [InlineKeyboardButton("🎮 Join Live Hall", web_app=WebAppInfo(url=live_url))],
        [InlineKeyboardButton("💰 Wallet", callback_data="wallet")]
    ]
    
    await update.message.reply_text(
        f"Welcome to VladBingo!\n\nClick below to open the Live Hall and hear the caller.", 
        reply_markup=InlineKeyboardMarkup(kbd)
    )

def run():
    TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    print("🤖 VladBingo Mini-App Bot is LIVE...")
    app.run_polling()

if __name__ == "__main__": run()
