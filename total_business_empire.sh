#!/bin/bash
# VLAD BINGO - THE TOTAL BUSINESS EMPIRE (5 ROOMS + 20% CUT + AUTO-TIMER)

# 1. CORE DIRECTORIES
mkdir -p backend/bingo/bot backend/bingo/services backend/bingo/management/commands backend/bingo/templates backend/vlad_bingo

# 2. FULL MODELS (Everything included)
cat <<'EOF' > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_cards = models.JSONField(default=list)
    current_joining_room = models.IntegerField(null=True, blank=True)
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
    status = models.CharField(max_length=20, default="LOBBY") # LOBBY, STARTING, ACTIVE, WON_BY_X

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    type = models.CharField(max_length=20, default="DEPOSIT")
    note = models.TextField(default="")
EOF

# 3. FULL VIEWS (20% Cut + Tiered Win Rules)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo Engine: Professional Tier</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_game_info(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        prize = float(len(game.players) * game.bet_amount) * 0.80 # 20% cut for you
        card_num = game.players.get(str(tg_id), 1)
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({
            'card_number': card.card_number, 'board': card.board,
            'prize': round(prize, 2), 'status': game.status, 'called_numbers': game.called_numbers
        })
    except: return JsonResponse({'error': 'Sync Error'})

def check_win(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        if game.status != "ACTIVE": return JsonResponse({'status': 'NOT_ACTIVE'})
        if "WON" in game.status: return JsonResponse({'status': 'ALREADY_WON'})
        card_num = game.players.get(str(tg_id))
        card = PermanentCard.objects.get(card_number=card_num)
        called_set = set(game.called_numbers); board = card.board; lines = 0
        for row in board:
            if all(c == "FREE" or c in called_set for c in row): lines += 1
        for c in range(5):
            if all(board[r][c] == "FREE" or board[r][c] in called_set for r in range(5)): lines += 1
        corners = [board[0][0], board[0][4], board[4][0], board[4][4]]
        if all(c in called_set for c in corners): lines += 1
        
        # RULES: 20-40 needs 2 lines, 50-100 needs 3 lines
        won = (float(game.bet_amount) <= 40 and lines >= 2) or (float(game.bet_amount) >= 50 and lines >= 3)
        if won:
            prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
            user.operational_credit += prize; user.save()
            game.status = f"WON_BY_{card.card_number}"; game.save()
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        return JsonResponse({'status': 'NOT_YET'})
    except: return JsonResponse({'status': 'ERROR'})

class ChapaWebhookView(APIView):
    permission_classes = []; def post(self, request): return Response({"status": "ok"})
EOF

# 4. FULL BOT MAIN (5 Rooms + Timer + Registration)
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

def db_op(uid, action, val=None, name=None):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    if action == "state": user.bot_state = val
    elif action == "name": user.real_name = val; user.bot_state = "IDLE"
    elif action == "phone": user.phone_number = val; user.bot_state = "IDLE"
    user.save(); return user

async def start(update: Update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    if not user.real_name:
        await sync_to_async(db_op)(user.id, "state", "REG_NAME")
        await update.message.reply_text("👋 **Welcome!** Please enter your Full Name to register:")
        return
    if not user.phone_number:
        btn = [[KeyboardButton("📲 Share Phone Number", request_contact=True)]]
        await update.message.reply_text("One more step! Tap below to verify your phone:", reply_markup=ReplyKeyboardMarkup(btn, one_time_keyboard=True, resize_keyboard=True))
        return

    msg = f"🎰 **VLAD BINGO** 🎰\n👤 Player: {user.real_name}\n💰 Balance: {user.operational_credit} ETB\n\nPick a Room to Join:"
    kbd = [[InlineKeyboardButton("💵 20", callback_data="r_20"), InlineKeyboardButton("💵 30", callback_data="r_30"), InlineKeyboardButton("💵 40", callback_data="r_40")],
           [InlineKeyboardButton("💵 50", callback_data="r_50"), InlineKeyboardButton("💵 100", callback_data="r_100")],
           [InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

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

async def btn_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    user = await sync_to_async(db_op)(uid, "get")
    if q.data.startswith("r_"):
        amt = int(q.data.split("_")[1])
        if user.operational_credit < amt: await q.edit_message_text("❌ Low Balance!"); return
        game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
        user.current_joining_room = game.id; user.bot_state = "PICKING"; await sync_to_async(user.save)()
        await q.edit_message_text(f"🎟 **Room {amt} ETB.** Type lucky Card # (1-100):")

async def text_handler(update, context):
    uid = update.effective_user.id; user = await sync_to_async(db_op)(uid, "get")
    text = update.message.text
    if user.bot_state == "REG_NAME":
        await sync_to_async(db_op)(uid, "name", text); await update.message.reply_text(f"✅ Hello {text}!"); await start(update, context)
    elif text.isdigit() and user.bot_state == "PICKING":
        val = int(text); game = await sync_to_async(GameRound.objects.get)(id=user.current_joining_room)
        if val in game.players.values(): await update.message.reply_text("🚫 Taken!"); return
        user.operational_credit -= game.bet_amount; user.selected_cards.append(val); user.bot_state = "IDLE"; await sync_to_async(user.save)()
        game.players[str(uid)] = val; await sync_to_async(game.save)()
        if len(game.players) == 3:
            game.status = "STARTING"; await sync_to_async(game.save)()
            asyncio.create_task(game_dealer(game.id)); await update.message.reply_text("🔥 **LOBBY FULL!** 5 mins to start.")
        else: await update.message.reply_text(f"✅ Joined! Lobby {len(game.players)}/3")

async def post_init(app): await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start)); app.add_handler(CallbackQueryHandler(btn_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler)); app.run_polling()
if __name__ == "__main__": run()
EOF

# 5. ADMIN & SYNC
cat <<'EOF' > backend/bingo/admin.py
from django.contrib import admin
from .models import User, PermanentCard, GameRound, Transaction
admin.site.register(PermanentCard)
admin.site.register(GameRound)
admin.site.register(Transaction)
EOF

# 6. BUILD SCRIPT
cat <<'EOF' > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    cursor.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
innerEOF
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input
python manage.py shell -c "from bingo.models import User; User.objects.create_superuser('admin', 'admin@vlad.com', 'VladBingoPassword123')"
python manage.py init_bingo || true
EOF

chmod +x backend/build.sh
echo "✅ TOTAL BUSINESS EMPIRE READY!"
