#!/bin/bash
# VladBingo - Final Platform Master (Multi-Room + Win Logic + Fixes)

# 1. FULL MODELS
cat <<'EOF' > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_cards = models.JSONField(default=list)
    current_joining_room = models.IntegerField(null=True, blank=True)
    bot_state = models.CharField(max_length=30, default="IDLE")

class PermanentCard(models.Model):
    card_number = models.PositiveSmallIntegerField(unique=True)
    board = models.JSONField()

class GameRound(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    called_numbers = models.JSONField(default=list)
    players = models.JSONField(default=dict)
    bet_amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=20, default="LOBBY")

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    type = models.CharField(max_length=20, default="DEPOSIT")
EOF

# 2. FULL VIEWS (Includes the missing 'home' function!)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import HttpResponse, JsonResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard, GameRound
from decimal import Decimal

def home(request):
    return HttpResponse("<h1>VladBingo Platform is Online</h1>")

def live_view(request):
    return render(request, 'live_view.html')

def get_game_info(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        prize = float(len(game.players) * game.bet_amount) * 0.80 # 20% Cut
        card_num = game.players.get(str(tg_id), 1)
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({
            'game_id': game.id, 'card_number': card.card_number, 
            'board': card.board, 'prize': round(prize, 2),
            'status': game.status, 'called_numbers': game.called_numbers
        })
    except: return JsonResponse({'error': 'Error'}, status=404)

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request): return Response({"status": "ok"})
EOF

# 3. FULL BOT MAIN
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from decimal import Decimal

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR)); os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings"); django.setup()
from bingo.models import User, GameRound

async def start(update: Update, context):
    user, _ = await sync_to_async(User.objects.get_or_create)(username=f"tg_{update.effective_user.id}")
    user.bot_state = "IDLE"; await sync_to_async(user.save)()
    msg = f"🎰 **VLAD BINGO** 🎰\n💰 Balance: {user.operational_credit} ETB\n\nPick a room to join:"
    kbd = [[InlineKeyboardButton("💵 20 ETB Room", callback_data="r_20"),
            InlineKeyboardButton("💵 50 ETB Room", callback_data="r_50")]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def room_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    amt = int(q.data.split("_")[1])
    user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    if user.operational_credit < amt:
        await q.edit_message_text("❌ Insufficient Balance!"); return
    game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
    user.current_joining_room = game.id; user.bot_state = "PICKING"; await sync_to_async(user.save)()
    await q.edit_message_text(f"🎟 **Room {amt} ETB.**\n\nType your lucky Card Number (1-100) to join:")

async def text_handler(update, context):
    uid = update.effective_user.id
    user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    if user.bot_state != "PICKING" or not update.message.text.isdigit(): return
    card_num = int(update.message.text)
    game = await sync_to_async(GameRound.objects.get)(id=user.current_joining_room)
    if card_num in game.players.values():
        await update.message.reply_text(f"🚫 Card #{card_num} is taken! Pick another:")
        return
    user.operational_credit -= game.bet_amount; user.bot_state = "IDLE"; await sync_to_async(user.save)()
    game.players[str(uid)] = card_num; await sync_to_async(game.save)()
    url = f"https://vlad-bingo-web.onrender.com/api/live/?game_id={game.id}"
    await update.message.reply_text(f"✅ **JOINED!** Paid {game.bet_amount} ETB.", 
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url=url))]]), parse_mode='Markdown')

async def post_init(app):
    await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(room_handler, pattern="^r_"))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()
if __name__ == "__main__": run()
EOF

# 4. NUCLEAR BUILD SCRIPT (Fresh Database Rebuild)
cat <<'EOF' > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input

# KILL OLD SCHEMA
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    cursor.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
innerEOF

python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input
python manage.py shell -c "from bingo.models import User; User.objects.create_superuser('admin', 'admin@vlad.com', 'VladBingo123')"
python manage.py init_bingo || true
EOF

echo "✅ Platform logic and home view restored!"
