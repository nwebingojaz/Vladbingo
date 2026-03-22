import os, sys, django, asyncio
from pathlib import Path
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, MessageHandler, filters
from bingo.models import User

async def start(update: Update, context):
    uid = update.effective_user.id
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    
    msg = (f"🎰 **VLAD BINGO LIVE** 🎰\n\n"
           f"Your Lucky Card: #**{user.selected_card}**\n"
           f"Balance: {user.operational_credit} ETB\n\n"
           f"To change your card, just **type a number between 1 and 100**.")
    
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={user.selected_card}"
    kbd = [[InlineKeyboardButton("🎮 Join Live Hall", web_app=WebAppInfo(url=live_url))]]
    
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def handle_card_selection(update: Update, context):
    uid = update.effective_user.id
    text = update.message.text
    
    if text.isdigit():
        num = int(text)
        if 1 <= num <= 100:
            user = User.objects.get(username=f"tg_{uid}")
            user.selected_card = num
            user.save()
            
            live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={num}"
            kbd = [[InlineKeyboardButton("🎮 Join Hall with Card #"+str(num), web_app=WebAppInfo(url=live_url))]]
            
            await update.message.reply_text(f"✅ Card updated to **#{num}**!", 
                                          reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')
        else:
            await update.message.reply_text("❌ Please pick a number between 1 and 100.")

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_card_selection))
    app.run_polling()

if __name__ == "__main__": run()
