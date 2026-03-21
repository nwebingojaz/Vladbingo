#!/bin/bash
# VladBingo - Final Synchronized Code Sync

# 1. Update bingo/views.py (Includes home, live_view, and card data)
cat <<EOF > backend/bingo/views.py
from django.shortcuts import render
from django.http import HttpResponse, JsonResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import PermanentCard, User

def home(request):
    return HttpResponse("<h1>VladBingo Server is Online</h1><p>The system is running perfectly.</p>")

def live_view(request):
    return render(request, 'live_view.html')

def get_card_data(request, card_num):
    try:
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
    except:
        return JsonResponse({'error': 'Card not found'}, status=404)

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request):
        return Response({"status": "ok"})
EOF

# 2. Update the Bot Main (Ensures it points to the right path)
cat <<EOF > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path

# Important: Add parent folder to path for imports
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
    
    # We default to showing Card #1 for now. 
    # In a real game, you would pass the card the user bought.
    live_url = "https://vlad-bingo-web.onrender.com/api/live/?card=1"
    
    kbd = [
        [InlineKeyboardButton("🎮 Join Live Hall", web_app=WebAppInfo(url=live_url))],
        [InlineKeyboardButton("💰 Wallet Balance", callback_data="wallet")]
    ]
    
    await update.message.reply_text(
        f"Welcome to VladBingo!\n\nUser: {update.effective_user.first_name}\nBalance: {user.operational_credit} ETB",
        reply_markup=InlineKeyboardMarkup(kbd)
    )

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).build()
    app.add_handler(CommandHandler("start", start))
    print("🤖 Bot is starting successfully...")
    app.run_polling()

if __name__ == "__main__":
    run()
EOF

echo "✅ Everything is now in sync!"
