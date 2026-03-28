#!/bin/bash
# VLAD BINGO - ABSOLUTE MASTER ENGINE (SYNCED & COMPLETE)

# 1. MODELS
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

# 2. VIEWS (Fixed Syntax + 20% Profit + Tiered Wins)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo Engine is Active</h1>")
def live_view(request): return render(request, 'live_view.html')

def lobby_info(request, tg_id):
    user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
    return JsonResponse({'balance': float(user.operational_credit)})

def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    if user.operational_credit < bet: return JsonResponse({'error': 'Low Balance'})
    game, _ = GameRound.objects.get_or_create(status="LOBBY", bet_amount=bet)
    if card_num in game.players.values(): return JsonResponse({'error': 'Taken'})
    user.operational_credit -= Decimal(bet); user.save()
    game.players[str(tg_id)] = card_num; game.save()
    return JsonResponse({'status': 'ok'})

def get_game_info(request, game_id, tg_id):
    try:
        game = GameRound.objects.get(id=game_id)
        user = User.objects.get(username=f"tg_{tg_id}")
        prize = float(len(game.players) * game.bet_amount) * 0.80 # 20% cut
        card_num = game.players.get(str(tg_id), 1)
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board, 'prize': round(prize, 2), 'status': game.status, 'called_numbers': game.called_numbers, 'bet': float(game.bet_amount)})
    except: return JsonResponse({'error': 'Not found'}, status=404)

def check_win(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        if game.status != "ACTIVE": return JsonResponse({'status': 'NOT_ACTIVE'})
        card_num = game.players.get(str(tg_id)); card = PermanentCard.objects.get(card_number=card_num)
        called_set = set(game.called_numbers); board = card.board; lines = 0
        for row in board:
            if all(c == "FREE" or c in called_set for c in row): lines += 1
        for c in range(5):
            if all(card.board[r][c] == "FREE" or card.board[r][c] in called_set for r in range(5)): lines += 1
        corners = [board[0][0], board[0][4], board[4][0], board[4][4]]
        if all(c in called_set for c in corners): lines += 1
        
        req = 2 if float(game.bet_amount) <= 40 else 3
        if lines >= req:
            prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
            user.operational_credit += prize; user.save(); game.status = "ENDED"; game.save()
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        return JsonResponse({'status': 'NOT_YET'})
    except: return JsonResponse({'status': 'ERROR'})

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request):
        return Response({"status": "ok"})
EOF

# 3. BOT MAIN (10-Button Next Ludo Menu + Auto-Timer)
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
        if "WON" in game.status or game.status == "ENDED": break
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

    live_url = "https://vlad-bingo-web.onrender.com/api/live/"
    kbd = [
        [InlineKeyboardButton("Play Games 🎮", web_app=WebAppInfo(url=live_url))],
        [InlineKeyboardButton("Deposit 💰", callback_data="dep"), InlineKeyboardButton("Withdraw 💰", callback_data="wd")],
        [InlineKeyboardButton("Transfer ↔️", callback_data="tr"), InlineKeyboardButton("My Profile 👤", callback_data="pr")],
        [InlineKeyboardButton("Transactions 📜", callback_data="hi"), InlineKeyboardButton("Balance 💰", callback_data="ba")],
        [InlineKeyboardButton("Join Group ↗️", url="https://t.me/+t8ito3eKejo4OGU0"), InlineKeyboardButton("Contact Us", callback_data="co")]
    ]
    msg = f"🎰 **VLAD BINGO PLATFORM** 🎰\n\n👤 **የመለያ መረጃዎ:**\n📛 **Username:** @{update.effective_user.username}\n📱 **Phone:** {user.phone_number}\n💰 **Balance:** {user.operational_credit} ETB"
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def btn_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    user = await sync_to_async(db_op)(uid, "get")
    if q.data == "ba": await q.edit_message_text(f"💰 Balance: {user.operational_credit} ETB. Type /start to return.")
    elif q.data == "dep": await sync_to_async(db_op)(uid, "state", "DEPOSITING"); await q.edit_message_text("💵 Amount to deposit? (Min 20):")

async def text_handler(update, context):
    uid = update.effective_user.id; user = await sync_to_async(db_op)(uid, "get")
    text = update.message.text
    if user.bot_state == "REG_NAME":
        await sync_to_async(db_op)(uid, "name", text); await start(update, context)
    elif text.isdigit() and user.bot_state == "DEPOSITING" and int(text) >= 20:
        from bingo.services.chapa import init_deposit
        res, ref = await sync_to_async(init_deposit)(user, int(text))
        await update.message.reply_text(f"💳 [Pay {text} ETB Now]({res['data']['checkout_url']})", parse_mode='Markdown')

async def contact_handler(update: Update, context):
    await sync_to_async(db_op)(update.effective_user.id, "phone", update.message.contact.phone_number)
    await update.message.reply_text("✅ Verified!", reply_markup=ReplyKeyboardRemove()); await start(update, context)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(lambda a: a.bot.delete_webhook(drop_pending_updates=True)).build()
    app.add_handler(CommandHandler("start", start)); app.add_handler(CallbackQueryHandler(btn_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler)); app.add_handler(MessageHandler(filters.CONTACT, contact_handler))
    app.run_polling()
if __name__ == "__main__": run()
EOF

# 4. SYNC URLS
cat <<'EOF' > backend/bingo/urls.py
from django.urls import path
from .views import home, live_view, get_game_info, check_win, lobby_info, join_room
urlpatterns = [
    path('', home, name='home'),
    path('live/', live_view, name='live_view'),
    path('lobby-info/<int:tg_id>/', lobby_info),
    path('join-room/<int:tg_id>/<int:bet>/<int:card_num>/', join_room),
    path('game-info/<int:game_id>/<int:tg_id>/', get_game_info),
    path('check-win/<int:game_id>/<int:tg_id>/', check_win),
]
EOF

echo "✅ ABSOLUTE MASTER ENGINE READY!"
