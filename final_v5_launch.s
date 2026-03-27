#!/bin/bash
# VLAD BINGO - FINAL V5 (CASINO PRO + IDENTITY + TIERED WINS)

# 1. FULL MODELS
cat <<'EOF' > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_cards = models.JSONField(default=list)
    current_room_context = models.IntegerField(null=True, blank=True)
    bot_state = models.CharField(max_length=30, default="REG_NAME")
    real_name = models.CharField(max_length=100, blank=True)
    phone_number = models.CharField(max_length=20, blank=True)

class PermanentCard(models.Model):
    card_number = models.PositiveSmallIntegerField(unique=True)
    board = models.JSONField()

class GameRound(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    called_numbers = models.JSONField(default=list)
    players = models.JSONField(default=dict) # {"tg_id": card_num}
    bet_amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=20, default="LOBBY")

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    type = models.CharField(max_length=20, default="DEPOSIT")
    note = models.TextField(default="")
EOF

# 2. FULL VIEWS (Synced with all rules)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard, GameRound
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo Engine: Online</h1>")
def live_view(request): return render(request, 'live_view.html')

def lobby_info(request, tg_id):
    user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
    active_game = GameRound.objects.exclude(status="ENDED").last()
    has_joined = active_game.id if (active_game and str(tg_id) in active_game.players) else None
    return JsonResponse({'balance': float(user.operational_credit), 'active_game': has_joined})

def get_game_info(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        prize = float(len(game.players) * game.bet_amount) * 0.80 # 20% cut
        card_num = game.players.get(str(tg_id), 1)
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board, 'prize': round(prize, 2), 'status': game.status, 'called_numbers': game.called_numbers})
    except: return JsonResponse({'error': 'Error'}, status=404)

def check_win(request, tg_id):
    user = User.objects.get(username=f"tg_{tg_id}")
    game = GameRound.objects.filter(status="ACTIVE").last()
    if not game: return JsonResponse({'status': 'NO_GAME'})
    card_num = game.players.get(str(tg_id))
    card = PermanentCard.objects.get(card_number=card_num)
    called_set = set(game.called_numbers); lines = 0
    for row in card.board:
        if all(c == "FREE" or c in called_set for c in row): lines += 1
    for c in range(5):
        if all(card.board[r][c] == "FREE" or card.board[r][c] in called_set for r in range(5)): lines += 1
    corners = [card.board[0][0], card.board[0][4], card.board[4][0], card.board[4][4]]
    if all(c in called_set for c in corners): lines += 1
    
    threshold = 2 if float(game.bet_amount) <= 40 else 3
    if lines >= threshold:
        prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
        user.operational_credit += prize; user.save()
        game.status = "ENDED"; game.save()
        return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
    return JsonResponse({'status': 'NOT_YET'})

class ChapaWebhookView(APIView):
    permission_classes = []; def post(self, request): return Response({"status": "ok"})
EOF

# 3. FULL BOT (Registration + Open Hall)
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, KeyboardButton, ReplyKeyboardMarkup, ReplyKeyboardRemove, WebAppInfo
from telegram.ext import Application, CommandHandler, MessageHandler, filters

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR)); os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings"); django.setup()
from bingo.models import User

def db_op(uid, action, val=None):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    if action == "name": user.real_name = val; user.bot_state = "IDLE"
    elif action == "phone": user.phone_number = val; user.bot_state = "IDLE"
    user.save(); return user

async def start(update: Update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    if not user.real_name:
        await sync_to_async(db_op)(user.id, "state", "REG_NAME")
        return await update.message.reply_text("👋 Welcome! Please enter your **Full Name**:")
    if not user.phone_number:
        btn = [[KeyboardButton("📲 Share Phone Number", request_contact=True)]]
        return await update.message.reply_text("Tap to verify your phone:", reply_markup=ReplyKeyboardMarkup(btn, one_time_keyboard=True, resize_keyboard=True))
    
    msg = f"🎰 **VLAD BINGO PRO** 🎰\n💰 Balance: {user.operational_credit} ETB\n\nClick below to open the Lobby!"
    kbd = [[InlineKeyboardButton("🎮 OPEN CASINO LOBBY", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def handle_text(update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    if user.bot_state == "REG_NAME":
        await sync_to_async(db_op)(user.id, "name", update.message.text)
        await start(update, context)

async def handle_contact(update, context):
    await sync_to_async(db_op)(update.effective_user.id, "phone", update.message.contact.phone_number)
    await update.message.reply_text("✅ Verified!", reply_markup=ReplyKeyboardRemove()); await start(update, context)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    app.add_handler(MessageHandler(filters.CONTACT, handle_contact))
    app.run_polling()
if __name__ == "__main__": run()
EOF

# 4. FINAL BUILD SCRIPT
cat <<'EOF' > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input
python manage.py shell -c "from bingo.models import User; User.objects.get_or_create(username='admin', defaults={'is_staff':True, 'is_superuser':True, 'is_active':True})"
python manage.py init_bingo || true
EOF
chmod +x backend/build.sh
echo "✅ ABSOLUTE FINAL BUSINESS SYSTEM READY!"
