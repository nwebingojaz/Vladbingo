#!/bin/bash
# VladBingo - The "Super Fix" for Deployment

# 1. Update Bot Main with proper Path Logic
cat <<EOF > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path

# Fix: Tell Python to look in the parent folder for 'bingo' and 'vlad_bingo'
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
    live_url = "https://vlad-bingo-web.onrender.com/api/live/"
    
    kbd = [
        [InlineKeyboardButton("🎮 Open Live Hall", web_app=WebAppInfo(url=live_url))],
        [InlineKeyboardButton("💰 Wallet Balance", callback_data="wallet")]
    ]
    await update.message.reply_text(
        f"Welcome to VladBingo!\n\nUser ID: {uid}\nBalance: {user.operational_credit} ETB",
        reply_markup=InlineKeyboardMarkup(kbd)
    )

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not token:
        print("ERROR: TELEGRAM_BOT_TOKEN not found in environment!")
        return
    
    app = Application.builder().token(token).build()
    app.add_handler(CommandHandler("start", start))
    print("🤖 VladBingo Bot is starting successfully...")
    app.run_polling()

if __name__ == "__main__":
    run()
EOF

# 2. Add a Home View to avoid "Not Found" at the root URL
cat <<EOF > backend/bingo/views.py
from django.shortcuts import render
from django.http import HttpResponse
from rest_framework.views import APIView
from rest_framework.response import Response

def home(request):
    return HttpResponse("<h1>VladBingo Server is Online</h1><p>Visit /api/live/ for the Hall.</p>")

def live_view(request):
    return render(request, 'live_view.html')

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request):
        return Response({"status": "ok"})
EOF

# 3. Update main URLs to include Home
cat <<EOF > backend/vlad_bingo/urls.py
from django.contrib import admin
from django.urls import path, include
from bingo.views import home
urlpatterns = [
    path('', home),
    path('admin/', admin.site.urls),
    path('api/', include('bingo.urls')),
]
EOF

# 4. Fix render.yaml start commands (Removed the 'cd backend' to keep root context)
cat <<EOF > render.yaml
services:
  - type: web
    name: vlad-bingo-web
    env: python
    buildCommand: "./backend/build.sh"
    startCommand: "python backend/manage.py runserver 0.0.0.0:10000"
    envVars:
      - key: REDIS_URL
        fromService:
          type: redis
          name: vlad-redis
          property: connectionString
      - key: DATABASE_URL
        fromDatabase:
          name: vlad_db
          property: connectionString

  - type: worker
    name: vlad-bingo-bot
    env: python
    buildCommand: "./backend/build.sh"
    startCommand: "python backend/bingo/bot/main.py"

  - type: redis
    name: vlad-redis
    plan: free
    ipAllowList: []

databases:
  - name: vlad_db
    plan: free
    ipAllowList: []
EOF

echo "✅ Super fix applied!"
