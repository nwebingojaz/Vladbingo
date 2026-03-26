import os, sys, django, asyncio
from pathlib import Path
from asgiref.sync import sync_to_async

# Path Logic
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler

def db_get_user(uid):
    from bingo.models import User
    return User.objects.get_or_create(username=f"tg_{uid}")[0]

async def start(update: Update, context):
    user = await sync_to_async(db_get_user)(update.effective_user.id)
    msg = f"🎰 **VLAD BINGO ONLINE** 🎰\n\n👤 Player: {update.effective_user.first_name}\n💰 Balance: {user.operational_credit} ETB"
    kbd = [[InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def post_init(app):
    # THE BOT UNLOCKER: Kills all old connections immediately
    await app.bot.delete_webhook(drop_pending_updates=True)
    print("🚀 Bot process initialized and active.")

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    print("🤖 Bot is entering polling loop...")
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__": run()
