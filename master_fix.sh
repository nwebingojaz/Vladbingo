#!/bin/bash
# VladBingo - Final Master Fix

# 1. Create Templates Folder
mkdir -p backend/bingo/templates

# 2. Create the Live View Page (The Mini App Face)
cat <<EOF > backend/bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VladBingo Live</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #0f172a; color: white; }
        .grid-cell { background-color: #1e293b; height: 50px; display: flex; align-items: center; justify-content: center; font-weight: bold; border-radius: 4px; }
        .called { background-color: #eab308; color: black; box-shadow: 0 0 10px #eab308; }
    </style>
</head>
<body class="p-4 text-center">
    <h1 class="text-2xl font-bold mb-4 text-yellow-500">VladBingo Live Hall</h1>
    <div id="status" class="mb-4 text-sm text-gray-400">Connecting...</div>
    <div class="grid grid-cols-5 gap-2 mb-6" id="grid"></div>
    <div class="bg-slate-800 p-4 rounded-lg mb-4">
        <div class="text-xs text-gray-400 uppercase">Latest Number</div>
        <div id="latest" class="text-5xl font-black">--</div>
    </div>
    <button id="audio-btn" class="w-full py-3 bg-green-600 rounded-lg font-bold">Join with Amharic Audio 🔊</button>

    <script>
        const grid = document.getElementById('grid');
        for (let i = 1; i <= 75; i++) {
            grid.innerHTML += '<div id="n-'+i+'" class="grid-cell">'+i+'</div>';
        }
        document.getElementById('audio-btn').onclick = function() {
            this.style.display = 'none';
            document.getElementById('status').innerText = "Audio Enabled. Waiting for calls...";
        };
    </script>
</body>
</html>
EOF

# 3. Update Django Views (The logic for the page)
cat <<EOF > backend/bingo/views.py
from django.shortcuts import render
from rest_framework.views import APIView
from rest_framework.response import Response

def live_view(request):
    return render(request, 'live_view.html')

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request):
        return Response({"status": "ok"})
EOF

# 4. Update Django URLs
cat <<EOF > backend/bingo/urls.py
from django.urls import path
from .views import ChapaWebhookView, live_view
urlpatterns = [
    path('chapa-webhook/', ChapaWebhookView.as_view()),
    path('live/', live_view, name='live_view'),
]
EOF

# 5. Update the Bot Logic (The brain that replies)
cat <<EOF > backend/bingo/bot/main.py
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
EOF

echo "✅ Master logic applied!"
