import os, sys, django, asyncio
from pathlib import Path
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler
from bingo.models import User
from bingo.services.chapa import get_deposit_link

async def start(update: Update, context):
    uid = update.effective_user.id
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={user.selected_card}"
    msg = (f"🎰 **VLAD BINGO** 🎰\n\n"
           f"🎫 Card: #{user.selected_card}\n"
           f"💰 Balance: {user.operational_credit} ETB\n\n"
           f"Commands:\n/select <1-100>\n/deposit <amount> (Min 20 ETB)\n/withdraw <amount>")
    kbd = [[InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url=live_url))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def deposit(update, context):
    try:
        amount = int(context.args[0])
        # THE 20 BIRR SECURITY CHECK
        if amount < 20:
            await update.message.reply_text("⚠️ **Minimum deposit is 20 Birr.**")
            return
            
        user = User.objects.get(username=f"tg_{update.effective_user.id}")
        res = get_deposit_link(user, amount)
        link = res['data']['checkout_url']
        
        kbd = [[InlineKeyboardButton(f"💳 Pay {amount} ETB Now", url=link)]]
        await update.message.reply_text(f"To add {amount} ETB, click the button below:", 
                                      reply_markup=InlineKeyboardMarkup(kbd))
    except:
        await update.message.reply_text("Usage: /deposit 100")

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("deposit", deposit))
    print("🤖 Banker Bot is Online...")
    app.run_polling()

if __name__ == "__main__": run()
