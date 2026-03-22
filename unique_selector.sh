#!/bin/bash
# VladBingo - Unique Card Selector Logic

cat <<EOF > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, MessageHandler, filters

# Setup Paths
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from bingo.models import User

async def start(update: Update, context):
    uid = update.effective_user.id
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    
    live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={user.selected_card}"
    
    msg = (f"🎮 **VLAD BINGO SESSION** 🎮\n\n"
           f"👤 **Player:** {update.effective_user.first_name}\n"
           f"🎫 **Your Active Card:** #{user.selected_card}\n"
           f"💰 **Balance:** {user.operational_credit} ETB\n\n"
           f"🛠 **Commands:**\n"
           f"Type **/select <number>** to pick a new lucky card.\n"
           f"Example: \`/select 7\`")
    
    kbd = [
        [InlineKeyboardButton("🏆 ENTER LIVE HALL", web_app=WebAppInfo(url=live_url))],
        [InlineKeyboardButton("🎲 Change My Card", callback_data="hint")]
    ]
    
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def select_card(update: Update, context):
    uid = update.effective_user.id
    user = User.objects.get(username=f"tg_{uid}")

    if not context.args:
        await update.message.reply_text("❌ Please provide a number. Example: \`/select 25\`", parse_mode='Markdown')
        return

    try:
        requested_num = int(context.args[0])
        
        if not (1 <= requested_num <= 100):
            await update.message.reply_text("❌ Pick a number between 1 and 100.")
            return

        # THE UNIQUE CHECK: Is anyone else using this card?
        # We exclude the current user from the check
        is_taken = User.objects.filter(selected_card=requested_num).exclude(id=user.id).exists()

        if is_taken:
            await update.message.reply_text(f"🚫 **Card #{requested_num} is ALREADY TAKEN!**\nPlease pick another lucky number.", parse_mode='Markdown')
        else:
            user.selected_card = requested_num
            user.save()
            
            live_url = f"https://vlad-bingo-web.onrender.com/api/live/?card={requested_num}"
            kbd = [[InlineKeyboardButton("🎮 JOIN WITH CARD #"+str(requested_num), web_app=WebAppInfo(url=live_url))]]
            
            await update.message.reply_text(
                f"✅ **Success!** You now own **Card #{requested_num}** for the next round.",
                reply_markup=InlineKeyboardMarkup(kbd),
                parse_mode='Markdown'
            )

    except ValueError:
        await update.message.reply_text("❌ Invalid input. Please use a number.")

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).build()
    
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("select", select_card))
    
    print("🤖 Bot is Online with Unique Selector...")
    app.run_polling()

if __name__ == "__main__":
    run()
EOF

echo "✅ Unique Selector Logic Applied!"
