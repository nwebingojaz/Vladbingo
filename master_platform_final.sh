#!/bin/bash
# VladBingo - Master Platform (Everything Merged)

# 1. MODELS (User current room + Multi-card)
cat <<EOF > backend/bingo/models.py
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
    players = models.JSONField(default=dict) # {"tg_id": card_num}
    bet_amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=20, default="LOBBY")

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    type = models.CharField(max_length=20)
EOF

# 2. WEBSOCKETS (Room-based logic)
cat <<EOF > backend/bingo/consumers.py
import json
from channels.generic.websocket import AsyncWebsocketConsumer
class BingoConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.game_id = self.scope['url_route']['kwargs']['game_id']
        self.room_group_name = f'game_{self.game_id}'
        await self.channel_layer.group_add(self.room_group_name, self.channel_name)
        await self.accept()
    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.room_group_name, self.channel_name)
    async def bingo_message(self, event):
        await self.send(text_data=json.dumps(event["message"]))
EOF

cat <<EOF > backend/bingo/routing.py
from django.urls import re_path
from . import consumers
websocket_urlpatterns = [re_path(r"ws/game/(?P<game_id>\d+)/$", consumers.BingoConsumer.as_asgi())]
EOF

# 3. VIEWS (Dynamic Info with 20% cut)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse
from .models import User, PermanentCard, GameRound

def live_view(request): return render(request, 'live_view.html')

def get_game_info(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        prize = float(len(game.players) * game.bet_amount) * 0.80 # 20% Cut
        # Find which card this user is using IN THIS GAME
        card_num = game.players.get(str(tg_id), 1)
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({
            'game_id': game.id, 'card_number': card.card_number, 
            'board': card.board, 'prize': round(prize, 2),
            'status': game.status, 'called_numbers': game.called_numbers
        })
    except: return JsonResponse({'error': 'Error'}, status=404)
EOF

# 4. BOT MAIN (Room -> Card Selection)
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

async def start(update, context):
    user, _ = await sync_to_async(User.objects.get_or_create)(username=f"tg_{update.effective_user.id}")
    msg = f"🎰 **VLAD BINGO** 🎰\n💰 Balance: {user.operational_credit} ETB\n\nPick a room:"
    kbd = [[InlineKeyboardButton("💵 20 ETB", callback_data="r_20"), InlineKeyboardButton("💵 50 ETB", callback_data="r_50")]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def room_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    amt = int(q.data.split("_")[1])
    user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    if user.operational_credit < amt:
        await q.edit_message_text("❌ Insufficient Balance!"); return
    game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
    user.current_joining_room = game.id; user.bot_state = "PICKING"; await sync_to_async(user.save)()
    await q.edit_message_text(f"🎟 **Room {amt} ETB.**\nType your lucky Card Number (1-100):")

async def text_handler(update, context):
    uid = update.effective_user.id
    user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    if user.bot_state != "PICKING" or not update.message.text.isdigit(): return
    card_num = int(update.message.text)
    game = await sync_to_async(GameRound.objects.get)(id=user.current_joining_room)
    if card_num in game.players.values():
        await update.message.reply_text(f"🚫 Card #{card_num} taken in this room! Pick another:")
        return
    user.operational_credit -= game.bet_amount; user.bot_state = "IDLE"; await sync_to_async(user.save)()
    game.players[str(uid)] = card_num; await sync_to_async(game.save)()
    url = f"https://vlad-bingo-web.onrender.com/api/live/?game_id={game.id}"
    await update.message.reply_text(f"✅ **JOINED!** You are in the {game.bet_amount} ETB room.", 
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url=url))]]), parse_mode='Markdown')

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(room_handler, pattern="^r_"))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()
if __name__ == "__main__": run()
EOF

echo "✅ MASTER PLATFORM REBUILT!"
