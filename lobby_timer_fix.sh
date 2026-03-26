#!/bin/bash
# VladBingo - 5 Minute Auto-Timer & DB Fix

# 1. Full Models Fix (Adding 'note' to Transaction)
cat <<'EOF' > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_cards = models.JSONField(default=list)
    bot_state = models.CharField(max_length=20, default="IDLE")

class PermanentCard(models.Model):
    card_number = models.PositiveSmallIntegerField(unique=True)
    board = models.JSONField()

class GameRound(models.Model):
    created_at = models.DateTimeField(default=timezone.now)
    called_numbers = models.JSONField(default=list)
    players = models.JSONField(default=dict) 
    bet_amount = models.DecimalField(max_digits=10, decimal_places=2, default=20)
    status = models.CharField(max_length=20, default="LOBBY") # LOBBY, STARTING, ACTIVE, ENDED

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    type = models.CharField(max_length=20, default="DEPOSIT")
    note = models.TextField(default="") # Fixed missing column
EOF

# 2. Bot Logic with 5-Minute Timer
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from channels.layers import get_channel_layer
from django.conf import settings
from decimal import Decimal

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR)); os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings"); django.setup()
from bingo.models import User, GameRound

async def start(update: Update, context):
    user, _ = await sync_to_async(User.objects.get_or_create)(username=f"tg_{update.effective_user.id}")
    msg = f"🎰 **VLAD BINGO** 🎰\n💰 Balance: {user.operational_credit} ETB\nPick Buy-in:"
    kbd = [[InlineKeyboardButton("💵 20 ETB", callback_data="bet_20"), InlineKeyboardButton("💵 50 ETB", callback_data="bet_50")],
           [InlineKeyboardButton("🎮 LIVE HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def run_game_loop(game_id):
    """The Automated Dealer called after 5 mins"""
    await asyncio.sleep(300) # Wait 5 minutes (300 seconds)
    game = await sync_to_async(GameRound.objects.get)(id=game_id)
    game.status = "ACTIVE"; await sync_to_async(game.save)()
    
    nums = list(range(1, 76)); random.shuffle(nums)
    layer = get_channel_layer()
    for n in nums:
        game.refresh_from_db()
        if "WON" in game.status: break
        game.called_numbers.append(n); await sync_to_async(game.save)()
        await layer.group_send("bingo_live", {"type": "bingo_message", "message": {"action": "call_number", "number": n}})
        await asyncio.sleep(7)

async def bet_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    amt = int(q.data.split("_")[1])
    
    if user.operational_credit < amt:
        await q.edit_message_text("❌ Insufficient Balance!"); return

    game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY")
    game.players[str(uid)] = user.selected_cards[-1] if user.selected_cards else 1
    game.bet_amount = Decimal(amt)
    await sync_to_async(game.save)()
    
    user.operational_credit -= Decimal(amt); await sync_to_async(user.save)()
    
    player_count = len(game.players)
    if player_count == 3:
        game.status = "STARTING"; await sync_to_async(game.save)()
        await q.edit_message_text("🔥 **LOBBY FULL!** Game starts in 5 minutes.")
        asyncio.create_task(run_game_loop(game.id)) # Start the 5 min countdown
    else:
        await q.edit_message_text(f"✅ Joined! Lobby: {player_count}/3. Waiting...")

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(bet_handler, pattern="^bet_"))
    app.run_polling()

if __name__ == "__main__": run()
EOF

# 3. Update Build Script with SQL Hammer for 'note' column
cat <<'EOF' > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input

# THE DB HAMMER: Ensure 'note' column exists
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    try:
        cursor.execute("ALTER TABLE bingo_transaction ADD COLUMN note text DEFAULT '';")
        print("✅ Added missing note column")
    except:
        print("ℹ️ note column already exists")
innerEOF

python manage.py init_bingo || true
EOF

echo "✅ Lobby timer and DB fix applied!"
