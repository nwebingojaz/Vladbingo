#!/bin/bash
# VladBingo - Fix Remover Logic & Sync

# 1. Update the Bot Main (Fixed state logic)
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters

# Setup Paths
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from bingo.models import User

def db_get_user(uid, name):
    return User.objects.get_or_create(username=f"tg_{uid}", defaults={'first_name': name})[0]

async def start(update: Update, context):
    user = await sync_to_async(db_get_user)(update.effective_user.id, update.effective_user.first_name)
    user.bot_state = "IDLE"
    await sync_to_async(user.save)()
    
    cards = user.selected_cards
    cards_text = ", ".join([f"#{c}" for c in cards]) if cards else "❌ None"
    
    msg = (f"🎰 **VLAD BINGO HALL** 🎰\n\n"
           f"🎫 **Your Cards:** {cards_text}\n"
           f"💰 **Balance:** {user.operational_credit} ETB\n\n"
           f"Choose an action below:")
    
    live_url = "https://vlad-bingo-web.onrender.com/api/live/"
    kbd = [
        [InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url=live_url))],
        [InlineKeyboardButton("➕ Add Card", callback_data="add"), 
         InlineKeyboardButton("➖ Remove Card", callback_data="rem")],
        [InlineKeyboardButton("🗑 Clear All", callback_data="clear")]
    ]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def button_handler(update, context):
    q = update.callback_query
    user = await sync_to_async(db_get_user)(q.from_user.id, "")
    await q.answer()
    
    if q.data == "add":
        user.bot_state = "SELECTING"
        await q.edit_message_text("🔢 Type a card number (**1-100**) to **ADD**:")
    elif q.data == "rem":
        user.bot_state = "REMOVING"
        await q.edit_message_text("🔢 Type the card number you want to **REMOVE**:")
    elif q.data == "clear":
        user.selected_cards = []
        user.bot_state = "IDLE"
        await q.edit_message_text("🗑 All cards cleared! Use /start to pick new ones.")
    
    await sync_to_async(user.save)()

async def text_handler(update, context):
    user = await sync_to_async(db_get_user)(update.effective_user.id, "")
    text = update.message.text
    if not text.isdigit(): return
    val = int(text)

    if user.bot_state == "SELECTING":
        # Check if already taken
        is_taken = await sync_to_async(lambda: User.objects.filter(selected_cards__contains=val).exclude(id=user.id).exists())()
        if is_taken:
            await update.message.reply_text(f"🚫 Card #{val} is taken!")
        else:
            if val not in user.selected_cards:
                user.selected_cards.append(val)
                await sync_to_async(user.save)()
                await update.message.reply_text(f"✅ Card #{val} added! Use /start to play.")
            else:
                await update.message.reply_text("You already have this card.")

    elif user.bot_state == "REMOVING":
        if val in user.selected_cards:
            user.selected_cards.remove(val)
            user.bot_state = "IDLE" # Reset to idle after removing
            await sync_to_async(user.save)()
            await update.message.reply_text(f"🗑 Card #{val} removed! Type /start to see your list.")
        else:
            await update.message.reply_text(f"❌ You don't have Card #{val}.")

async def post_init(app):
    await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(button_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()

if __name__ == "__main__": run()
EOF

# 2. Update Views.py (Ensure it picks the LATEST card selected)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse
from .models import User, PermanentCard

def live_view(request):
    return render(request, 'live_view.html')

def get_user_card(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        # Always show the last card they added
        if user.selected_cards:
            card_to_show = user.selected_cards[-1]
            card = PermanentCard.objects.get(card_number=card_to_show)
            return JsonResponse({'card_number': card.card_number, 'board': card.board})
        return JsonResponse({'error': 'No cards selected'}, status=404)
    except:
        return JsonResponse({'error': 'Not found'}, status=404)
EOF

echo "✅ Remover Fix and View Sync applied!"
