#!/bin/bash
# VladBingo - Final Synchronized Business Delivery

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
    status = models.CharField(max_length=20, default="LOBBY") # LOBBY, STARTING, ACTIVE, ENDED

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    type = models.CharField(max_length=20, default="DEPOSIT")
    note = models.TextField(default="")
EOF

# 2. FULL VIEWS (Synced names: home, live_view, get_game_info, check_win)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo Business is LIVE</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_game_info(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status__in=["LOBBY", "STARTING", "ACTIVE"]).last()
        total_pool = (len(game.players) * game.bet_amount) if game else 0
        prize = float(total_pool) * 0.80 # 20% Cut for you
        card_num = game.players.get(str(tg_id), 1) if game else 1
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({
            'card_number': card.card_number, 'board': card.board,
            'prize': round(prize, 2), 'status': game.status if game else 'OFFLINE',
            'called_numbers': game.called_numbers if game else []
        })
    except: return JsonResponse({'error': 'Sync Error'})

def check_win(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(status="ACTIVE")
        if "WON" in game.status: return JsonResponse({'status': 'ALREADY_WON'})
        card_num = game.players.get(str(tg_id))
        card = PermanentCard.objects.get(card_number=card_num)
        called_set = set(game.called_numbers)
        won = any(all(c == "FREE" or c in called_set for c in row) for row in card.board)
        if won:
            prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
            user.operational_credit += prize; user.save()
            game.status = f"WON_BY_{card.card_number}"; game.save()
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        return JsonResponse({'status': 'NOT_YET'})
    except: return JsonResponse({'status': 'ERROR'})

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request): return Response({"status": "ok"})
EOF

# 3. FULL URLS
cat <<'EOF' > backend/bingo/urls.py
from django.urls import path
from .views import live_view, get_game_info, check_win, ChapaWebhookView
urlpatterns = [
    path('live/', live_view, name='live_view'),
    path('game-info/<int:tg_id>/', get_game_info),
    path('check-win/<int:tg_id>/', check_win),
    path('chapa-webhook/', ChapaWebhookView.as_view()),
]
EOF

# 4. FULL BOT MAIN (Room -> Card -> 5 Min Timer)
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from channels.layers import get_channel_layer
from decimal import Decimal

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR)); os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings"); django.setup()
from bingo.models import User, GameRound

async def game_dealer(game_id):
    await asyncio.sleep(300) # 5 Minute Lobby Timer
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

async def start(update: Update, context):
    user, _ = await sync_to_async(User.objects.get_or_create)(username=f"tg_{update.effective_user.id}")
    user.bot_state = "IDLE"; await sync_to_async(user.save)()
    msg = f"🎰 **VLAD BINGO** 🎰\n💰 Balance: {user.operational_credit} ETB\n\nPick a Room:"
    kbd = [[InlineKeyboardButton("💵 20 ETB", callback_data="r_20"), InlineKeyboardButton("💵 50 ETB", callback_data="r_50")],
           [InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def room_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    amt = int(q.data.split("_")[1])
    user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    if user.operational_credit < amt: await q.edit_message_text("❌ Low Balance!"); return
    game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
    user.current_joining_room = game.id; user.bot_state = "PICKING"; await sync_to_async(user.save)()
    await q.edit_message_text(f"🎟 **{amt} ETB Room.**\nType your lucky Card Number (1-100):")

async def text_handler(update, context):
    uid = update.effective_user.id
    user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    if user.bot_state != "PICKING" or not update.message.text.isdigit(): return
    val = int(update.message.text)
    game = await sync_to_async(GameRound.objects.get)(id=user.current_joining_room)
    if val in game.players.values(): await update.message.reply_text("🚫 Taken!"); return
    user.operational_credit -= game.bet_amount; user.bot_state = "IDLE"; await sync_to_async(user.save)()
    game.players[str(uid)] = val; await sync_to_async(game.save)()
    if len(game.players) == 3:
        game.status = "STARTING"; await sync_to_async(game.save)()
        asyncio.create_task(game_dealer(game.id))
        await update.message.reply_text("🔥 **LOBBY FULL!** Game starts in 5 minutes.")
    else: await update.message.reply_text(f"✅ Joined! Lobby: {len(game.players)}/3")

async def post_init(app): await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(room_handler, pattern="^r_"))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()
if __name__ == "__main__": run()
EOF

echo "✅ Final Delivery Applied!"
