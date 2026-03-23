import os, sys, django, asyncio
from pathlib import Path

# Fix paths
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update
from telegram.ext import Application, CommandHandler
from bingo.models import User

async def start(update: Update, context):
    uid = update.effective_user.id
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    await update.message.reply_text(f"✅ VladBingo is LIVE!\nBalance: {user.operational_credit} ETB")

async def post_init(app):
    # This clears any old connections immediately
    await app.bot.delete_webhook(drop_pending_updates=True)
    print("🚀 Fresh bot session started.")

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not token:
        print("Error: No Token")
        return
    app = Application.builder().token(token).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    run()
