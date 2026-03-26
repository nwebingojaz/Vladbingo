#!/bin/bash
# VLAD BINGO - FINAL PROFESSIONAL ENGINE (20% CUT)

# 1. DIRECTORIES
mkdir -p backend/bingo/bot backend/bingo/services backend/bingo/management/commands backend/bingo/templates backend/vlad_bingo

# 2. FULL MODELS
cat <<'EOF' > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_cards = models.JSONField(default=list)
    bot_state = models.CharField(max_length=30, default="IDLE")
    real_name = models.CharField(max_length=100, blank=True)
    phone_number = models.CharField(max_length=20, blank=True)

class PermanentCard(models.Model):
    card_number = models.PositiveSmallIntegerField(unique=True)
    board = models.JSONField()

class GameRound(models.Model):
    created_at = models.DateTimeField(default=timezone.now)
    called_numbers = models.JSONField(default=list)
    players = models.JSONField(default=dict) # {"tg_id": card_num}
    bet_amount = models.DecimalField(max_digits=10, decimal_places=2, default=20)
    status = models.CharField(max_length=20, default="LOBBY")

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    type = models.CharField(max_length=20, default="DEPOSIT")
    note = models.TextField(default="")
EOF

# 3. VIEWS (20% Cut Calculation)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo Business is LIVE</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_game_info(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status__in=["LOBBY", "STARTING", "ACTIVE"]).last()
        total_pool = (len(game.players) * game.bet_amount) if game else 0
        prize = float(total_pool) * 0.80 # THE 20% CUT: Winner gets 80%
        card_num = user.selected_cards[-1] if user.selected_cards else 1
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board, 'prize': round(prize, 2), 'status': game.status if game else 'OFFLINE', 'called_numbers': game.called_numbers if game else []})
    except: return JsonResponse({'error': 'Error'})

def check_win(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(status="ACTIVE")
        if "WON" in game.status: return JsonResponse({'status': 'ALREADY_WON'})
        card = PermanentCard.objects.get(card_number=user.selected_cards[-1])
        called_set = set(game.called_numbers)
        won = any(all(c == "FREE" or c in called_set for c in row) for row in card.board)
        if won:
            prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
            user.operational_credit += prize; user.save()
            game.status = f"WON_BY_{card.card_number}"; game.save()
            Transaction.objects.create(agent=user, amount=prize, type="WIN", note=f"Game #{game.id}")
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        return JsonResponse({'status': 'NOT_YET'})
    except: return JsonResponse({'status': 'ERROR'})

from rest_framework.views import APIView
from rest_framework.response import Response
class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request):
        data = request.data
        if data.get('status') == 'success':
            ref = data.get('tx_ref') # dep_USERID_unique
            user_id = ref.split('_')[1]
            amount = Decimal(data.get('amount'))
            user = User.objects.get(id=user_id)
            user.operational_credit += amount; user.save()
            return Response(status=200)
        return Response(status=400)
EOF

# 4. BOT MAIN (5-Min Timer + Multiple Cards)
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo, KeyboardButton, ReplyKeyboardMarkup, ReplyKeyboardRemove
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from channels.layers import get_channel_layer
from decimal import Decimal

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR)); os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings"); django.setup()
from bingo.models import User, GameRound
from bingo.services.chapa import init_deposit

def db_op(uid, action, val=None):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    if action == "state": user.bot_state = val
    elif action == "add": user.selected_cards.append(val)
    elif action == "rem": user.selected_cards.remove(val)
    user.save(); return user

async def start(update: Update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    if not user.real_name:
        await sync_to_async(db_op)(user.id, "state", "REG_NAME")
        await update.message.reply_text("👋 Welcome! Please enter your Full Name:")
        return
    txt = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "None"
    msg = f"🎰 **VLAD BINGO** 🎰\n💰 Balance: {user.operational_credit} ETB\n🎫 Cards: {txt}"
    kbd = [[InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))],
           [InlineKeyboardButton("💵 20 ETB", callback_data="bet_20"), InlineKeyboardButton("💵 50 ETB", callback_data="bet_50")],
           [InlineKeyboardButton("➕ Add Card", callback_data="add"), InlineKeyboardButton("➖ Remove", callback_data="rem")]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def game_loop(game_id):
    await asyncio.sleep(300) # 5 Minute Timer
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
    if q.data.startswith("bet_"):
        amt = int(q.data.split("_")[1])
        if user.operational_credit < amt: await q.edit_message_text("❌ Low Balance!"); return
        game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY")
        game.players[str(uid)] = user.selected_cards[-1] if user.selected_cards else 1
        game.bet_amount = Decimal(amt); await sync_to_async(game.save)()
        user.operational_credit -= Decimal(amt); await sync_to_async(user.save)()
        if len(game.players) == 3:
            game.status = "STARTING"; await sync_to_async(game.save)()
            asyncio.create_task(game_loop(game.id))
            await q.edit_message_text("🔥 **LOBBY FULL!** Game starts in 5 minutes.")
        else: await q.edit_message_text(f"✅ Joined! Lobby: {len(game.players)}/3")
    elif q.data == "add": await sync_to_async(db_op)(uid, "state", "SELECTING"); await q.edit_message_text("🔢 Type Card #:")

async def text_handler(update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    if user.bot_state == "REG_NAME":
        user.real_name = update.message.text; user.bot_state = "IDLE"; await sync_to_async(user.save)()
        await update.message.reply_text(f"✅ Registered as {user.real_name}!"); await start(update, context)
    elif update.message.text.isdigit() and user.bot_state == "SELECTING":
        await sync_to_async(db_op)(user.id, "add", int(update.message.text))
        await update.message.reply_text("✅ Card Added!"); await start(update, context)

async def post_init(app): await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(btn_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()
if __name__ == "__main__": run()
EOF

# 3. BUILD SCRIPT
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
echo "🚀 MASTER SCRIPT READY FOR PUSH!"
