#!/bin/bash
# VLAD BINGO - THE COMPLETE MASTER SYSTEM

# 1. Ensure all packages are ready
touch backend/bingo/__init__.py backend/bingo/services/__init__.py backend/bingo/bot/__init__.py

# 2. FULL MODELS (With Balance, Multiple Cards, and Transaction Log)
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
    status = models.CharField(max_length=16, default="PENDING")
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    type = models.CharField(max_length=20, default="DEPOSIT")
    status = models.CharField(max_length=20, default="SUCCESS")
EOF

# 3. FULL VIEWS (Win logic + Dynamic Card Sync)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import HttpResponse, JsonResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo Engine is Live</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_user_card(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        card_num = user.selected_cards[-1] if user.selected_cards else 1
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
    except:
        card = PermanentCard.objects.first()
        return JsonResponse({'card_number': 1, 'board': card.board if card else []})

def check_win(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status="ACTIVE").last()
        card = PermanentCard.objects.get(card_number=user.selected_cards[-1])
        called_set = set(game.called_numbers)
        board = card.board
        won = any(all(c == "FREE" or c in called_set for c in row) for row in board) or \
              any(all(board[r][c] == "FREE" or board[r][c] in called_set for r in range(5)) for c in range(5))
        if won:
            prize = Decimal("100.00")
            user.operational_credit += prize
            user.save(); game.status = "ENDED"; game.save()
            Transaction.objects.create(agent=user, amount=prize, type="WIN", note=f"Game #{game.id}")
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        return JsonResponse({'status': 'NOT_YET'})
    except: return JsonResponse({'status': 'ERROR'})
EOF

# 4. FULL BOT MAIN (All Buttons Restored + Dealer)
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from channels.layers import get_channel_layer

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from bingo.models import User, GameRound
from bingo.services.chapa import init_deposit

def db_get_user(uid, name):
    return User.objects.get_or_create(username=f"tg_{uid}", defaults={'first_name': name})[0]

async def start(update: Update, context):
    user = await sync_to_async(db_get_user)(update.effective_user.id, update.effective_user.first_name)
    user.bot_state = "IDLE"; await sync_to_async(user.save)()
    cards = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "❌ None"
    msg = f"🎰 **VLAD BINGO CENTER** 🎰\n\n🎫 **Your Cards:** {cards}\n💰 **Balance:** {user.operational_credit} ETB\n\nChoose an action:"
    kbd = [[InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))],
           [InlineKeyboardButton("➕ Add Card", callback_data="add"), InlineKeyboardButton("➖ Remove", callback_data="rem")],
           [InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🏧 Withdraw", callback_data="wd")],
           [InlineKeyboardButton("🗑 Clear All", callback_data="clear")]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def button_handler(update, context):
    q = update.callback_query; await q.answer()
    user = await sync_to_async(db_get_user)(q.from_user.id, "")
    if q.data == "add": user.bot_state = "SELECTING"; await q.edit_message_text("🔢 Type Card # to **ADD**:")
    elif q.data == "rem": user.bot_state = "REMOVING"; await q.edit_message_text("🔢 Type Card # to **REMOVE**:")
    elif q.data == "dep": user.bot_state = "DEPOSITING"; await q.edit_message_text("💵 Amount to deposit (Min 20):")
    elif q.data == "wd": user.bot_state = "WITHDRAWING"; await q.edit_message_text("🏧 Amount to withdraw:")
    elif q.data == "clear": user.selected_cards = []; await sync_to_async(user.save)(); await q.edit_message_text("🗑 All cards cleared!")
    await sync_to_async(user.save)()

async def text_handler(update, context):
    user = await sync_to_async(db_get_user)(update.effective_user.id, "")
    if not update.message.text.isdigit(): return
    val = int(update.message.text)
    if user.bot_state == "SELECTING":
        user.selected_cards.append(val); await sync_to_async(user.save)()
        await update.message.reply_text(f"✅ Added Card #{val}! Type /start to play.")
    elif user.bot_state == "REMOVING" and val in user.selected_cards:
        user.selected_cards.remove(val); await sync_to_async(user.save)()
        await update.message.reply_text(f"🗑 Removed Card #{val}!")
    elif user.bot_state == "DEPOSITING" and val >= 20:
        res, ref = await sync_to_async(init_deposit)(user, val)
        await update.message.reply_text(f"💳 [Pay {val} ETB]({res['data']['checkout_url']})", parse_mode='Markdown')

async def new_game(update, context):
    if update.effective_user.username != "nwebingojaz": return
    game = await sync_to_async(GameRound.objects.create)(status="ACTIVE")
    await update.message.reply_text(f"🚀 **GAME #{game.id} STARTED!** Check the Hall.")
    nums = list(range(1, 76)); random.shuffle(nums)
    layer = get_channel_layer()
    for n in nums:
        game.called_numbers.append(n); await sync_to_async(game.save)()
        await layer.group_send("bingo_live", {"type": "bingo_message", "message": {"action": "call_number", "number": n}})
        await asyncio.sleep(6)

async def post_init(app): await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start)); app.add_handler(CommandHandler("newgame", new_game))
    app.add_handler(CallbackQueryHandler(button_handler)); app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()
if __name__ == "__main__": run()
EOF

echo "✅ ULTIMATE SYSTEM RESTORED!"
