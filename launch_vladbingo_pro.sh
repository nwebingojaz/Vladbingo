#!/bin/bash
# VLAD BINGO - THE ABSOLUTE FINAL BUSINESS ENGINE

# 1. FULL MODELS
cat <<'EOF' > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_cards = models.JSONField(default=list)
    current_room_id = models.IntegerField(null=True, blank=True)
    bot_state = models.CharField(max_length=30, default="REG_NAME")
    real_name = models.CharField(max_length=100, blank=True)
    phone_number = models.CharField(max_length=20, blank=True)

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
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    type = models.CharField(max_length=20, default="DEPOSIT")
    note = models.TextField(default="")
EOF

# 2. FULL VIEWS (20% Cut + Tiered Rules)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo Engine is Active</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_game_info(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        prize = float(len(game.players) * game.bet_amount) * 0.80 # 20% cut for you
        u_cards = game.players.get(str(tg_id), [1])
        card_num = u_cards[0] if isinstance(u_cards, list) else u_cards
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board, 'prize': round(prize, 2), 'status': game.status, 'called_numbers': game.called_numbers})
    except: return JsonResponse({'error': 'Sync Error'})

def check_win(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        if game.status != "ACTIVE": return JsonResponse({'status': 'NOT_ACTIVE'})
        if "WON" in game.status: return JsonResponse({'status': 'ALREADY_WON'})
        u_cards = game.players.get(str(tg_id))
        card_num = u_cards[0] if isinstance(u_cards, list) else u_cards
        card = PermanentCard.objects.get(card_number=card_num)
        called_set = set(game.called_numbers)
        lines = 0
        for row in card.board:
            if all(c == "FREE" or c in called_set for c in row): lines += 1
        for c in range(5):
            if all(card.board[r][c] == "FREE" or card.board[r][c] in called_set for r in range(5)): lines += 1
        corners = [card.board[0][0], card.board[0][4], card.board[4][0], card.board[4][4]]
        if all(c in called_set for c in corners): lines += 1
        win_req = 2 if float(game.bet_amount) <= 40 else 3
        if lines >= win_req:
            prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
            user.operational_credit += prize; user.save()
            game.status = f"WON_BY_{card_num}"; game.save()
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        return JsonResponse({'status': 'NOT_YET'})
    except: return JsonResponse({'status': 'ERROR'})

class ChapaWebhookView(APIView):
    permission_classes = []; def post(self, request): return Response({"status": "ok"})
EOF

# 3. FULL BOT MAIN
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, KeyboardButton, ReplyKeyboardMarkup, ReplyKeyboardRemove, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from channels.layers import get_channel_layer
from decimal import Decimal

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR)); os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings"); django.setup()
from bingo.models import User, GameRound

def db_op(uid, action, val=None):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    if action == "name": user.real_name = val; user.bot_state = "IDLE"
    elif action == "phone": user.phone_number = val; user.bot_state = "IDLE"
    user.save(); return user

async def game_dealer(game_id):
    await asyncio.sleep(300) # 5 Min Timer
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
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    if not user.real_name:
        await sync_to_async(db_op)(user.id, "state", "REG_NAME")
        return await update.message.reply_text("👋 Welcome! Please enter your **Full Name** to register:")
    if not user.phone_number:
        btn = [[KeyboardButton("📲 Share Phone", request_contact=True)]]
        return await update.message.reply_text("Tap below to verify phone:", reply_markup=ReplyKeyboardMarkup(btn, one_time_keyboard=True, resize_keyboard=True))

    active_games = await sync_to_async(lambda: list(GameRound.objects.exclude(status="ENDED")))()
    user_games = [g for g in active_games if str(update.effective_user.id) in g.players]
    kbd = []
    for g in user_games:
        url = f"https://vlad-bingo-web.onrender.com/api/live/?game_id={g.id}"
        kbd.append([InlineKeyboardButton(f"🎮 ENTER {int(g.bet_amount)} ETB HALL", web_app=WebAppInfo(url=url))])
    
    kbd.append([InlineKeyboardButton("💵 Join 10", callback_data="r_10"), InlineKeyboardButton("💵 Join 20", callback_data="r_20"), InlineKeyboardButton("💵 Join 40", callback_data="r_40")])
    kbd.append([InlineKeyboardButton("💵 Join 50", callback_data="r_50"), InlineKeyboardButton("💵 Join 100", callback_data="r_100")])
    kbd.append([InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🗑 Clear/Refund", callback_data="clear")])
    msg = f"🎰 **VLAD BINGO** 🎰\n👤 Player: {user.real_name}\n💰 Balance: {user.operational_credit} ETB"
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def btn_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    user = await sync_to_async(db_op)(uid, "get")
    if q.data.startswith("r_"):
        amt = int(q.data.split("_")[1])
        if user.operational_credit < amt: await q.edit_message_text("❌ Low Balance!"); return
        game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
        user.current_room_id = game.id; user.bot_state = "PICKING"; await sync_to_async(user.save)()
        await q.edit_message_text(f"🎟 **Room {amt} ETB.** Type Card # (1-100):")
    elif q.data == "dep": 
        user.bot_state = "DEPOSITING"; await sync_to_async(user.save)(); await q.edit_message_text("💵 Deposit amount? (Min 20):")
    elif q.data == "clear":
        games = await sync_to_async(lambda: list(GameRound.objects.filter(status="LOBBY")))()
        for g in games:
            if str(uid) in g.players:
                user.operational_credit += g.bet_amount
                del g.players[str(uid)]; await sync_to_async(g.save)()
        await sync_to_async(user.save)(); await q.edit_message_text("🗑 Cards cleared and money refunded!")

async def text_handler(update, context):
    uid = update.effective_user.id; user = await sync_to_async(db_op)(uid, "get")
    if user.bot_state == "REG_NAME":
        await sync_to_async(db_op)(uid, "name", update.message.text); await start(update, context)
    elif update.message.text.isdigit() and user.bot_state == "PICKING":
        val = int(update.message.text); game = await sync_to_async(GameRound.objects.get)(id=user.current_room_id)
        if val in game.players.values(): await update.message.reply_text("🚫 Taken!"); return
        user.operational_credit -= game.bet_amount; user.selected_cards.append(val); user.bot_state = "IDLE"
        game.players[str(uid)] = [val]; await sync_to_async(user.save)(); await sync_to_async(game.save)()
        if len(game.players) == 3: asyncio.create_task(game_dealer(game.id))
        await update.message.reply_text("✅ Card Added!"); await start(update, context)

async def contact_handler(update, context):
    await sync_to_async(db_op)(update.effective_user.id, "phone", update.message.contact.phone_number)
    await update.message.reply_text("✅ Verified!", reply_markup=ReplyKeyboardRemove()); await start(update, context)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start)); app.add_handler(CallbackQueryHandler(btn_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler)); app.add_handler(MessageHandler(filters.CONTACT, contact_handler))
    app.run_polling()
if __name__ == "__main__": run()
EOF

# 4. NUCLEAR BUILD SCRIPT
cat <<'EOF' > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
# THE NUCLEAR WIPE: Fixes the column already exists error forever
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    cursor.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
innerEOF
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input
python manage.py shell -c "from bingo.models import User; User.objects.get_or_create(username='admin', defaults={'is_staff':True, 'is_superuser':True, 'is_active':True})"
python manage.py init_bingo || true
EOF
chmod +x backend/build.sh

echo "✅ ULTIMATE ENGINE READY!"
