#!/bin/bash
# VladBingo - Path Anchor Fix

# 1. Fix manage.py (Add path logic)
cat <<EOF > backend/manage.py
#!/usr/bin/env python
import os, sys
from pathlib import Path

# Anchor: Add the current folder to the Python path
current_path = Path(__file__).resolve().parent
sys.path.append(str(current_path))

if __name__ == "__main__":
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
    from django.core.management import execute_from_command_line
    execute_from_command_line(sys.argv)
EOF
chmod +x backend/manage.py

# 2. Fix the Bot Main (Path logic)
cat <<EOF > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path

# Anchor: Add the backend folder to the path
backend_path = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(backend_path))

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler
from bingo.models import User

async def start(update, context):
    uid = update.effective_user.id
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    live_url = "https://vlad-bingo-web.onrender.com/api/live/"
    kbd = [[InlineKeyboardButton("🎮 Open Live Hall", web_app=WebAppInfo(url=live_url))]]
    await update.message.reply_text(f"Welcome to VladBingo!\nBalance: {user.operational_credit} ETB", 
                                  reply_markup=InlineKeyboardMarkup(kbd))

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    app = Application.builder().token(token).build()
    app.add_handler(CommandHandler("start", start))
    print("🤖 VladBingo Bot is starting...")
    app.run_polling()

if __name__ == "__main__": run()
EOF

# 3. Update the Render Blueprint with the "cd backend" command
cat <<EOF > render.yaml
services:
  - type: web
    name: vlad-bingo-web
    env: python
    buildCommand: "./backend/build.sh"
    # THE KEY FIX: cd backend before starting
    startCommand: "cd backend && python -m daphne -b 0.0.0.0 -p 10000 vlad_bingo.asgi:application"
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
    # THE KEY FIX: cd backend before starting
    startCommand: "cd backend && python bingo/bot/main.py"

  - type: redis
    name: vlad-redis
    plan: free
    ipAllowList: []

databases:
  - name: vlad_db
    plan: free
    ipAllowList: []
EOF

echo "✅ Path Anchor fix applied!"
