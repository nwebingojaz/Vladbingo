#!/bin/bash
# VLAD BINGO - COMPLETE INTEGRATED BUSINESS ENGINE

# 1. MODELS (Clean, Professional, Fixed)
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

# 2. CHAPA SERVICE (Crucial: Passes User ID in tx_ref)
cat <<'EOF' > backend/bingo/services/chapa.py
import os, requests, uuid
def init_deposit(user, amount):
    # THE SECRET: We hide the user ID in the reference so the Webhook can find them
    ref = f"vlad_{user.id}_{uuid.uuid4().hex[:4]}"
    payload = {
        "amount": str(amount), "currency": "ETB", "tx_ref": ref,
        "email": "bababingo22@gmail.com", 
        "callback_url": "https://vlad-bingo-web.onrender.com/api/chapa-webhook/",
        "customization": {"title": "Bingo Deposit"}
    }
    headers = {"Authorization": f"Bearer {os.environ.get('CHAPA_SECRET_KEY')}"}
    res = requests.post("https://api.chapa.co/v1/transaction/initialize", json=payload, headers=headers)
    return res.json(), ref
EOF

# 3. VIEWS (The Banker + Win logic)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal
import os, requests

def home(request): return HttpResponse("<h1>VladBingo Engine: Online</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_game_info(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        prize = float(len(game.players) * game.bet_amount) * 0.80
        card_num = game.players.get(str(tg_id), 1)
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board, 'prize': round(prize, 2), 'status': game.status, 'called_numbers': game.called_numbers})
    except: return JsonResponse({'error': 'Error'})

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request):
        data = request.data
        if data.get('status') == 'success':
            ref = data.get('tx_ref') # Format: vlad_USERID_unique
            try:
                u_id = ref.split('_')[1]
                amount = Decimal(data.get('amount'))
                user = User.objects.get(id=u_id)
                user.operational_credit += amount
                user.save()
                # Notify User on Telegram
                bot_token = os.environ.get("TELEGRAM_BOT_TOKEN")
                tg_id = user.username.split('_')[1]
                msg = f"💰 **DEPOSIT SUCCESS!**\n\n{amount} ETB added.\nNew Balance: {user.operational_credit} ETB"
                requests.get(f"https://api.telegram.org/bot{bot_token}/sendMessage?chat_id={tg_id}&text={msg}&parse_mode=Markdown")
                return Response(status=200)
            except: pass
        return Response(status=200) # Always return 200 to Chapa
EOF

# 4. BOT MAIN (Fully Responsive Multi-Menu)
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
from bingo.services.chapa import init_deposit

def db_op(uid, action, val=None):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    if action == "state": user.bot_state = val
    elif action == "clear": user.selected_cards = []
    user.save(); return user

async def start(update: Update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    if not user.real_name:
        await sync_to_async(db_op)(user.id, "state", "REG_NAME")
        return await update.message.reply_text("👋 Welcome! Enter your **Full Name** to register:")
    if not user.phone_number:
        btn = [[KeyboardButton("📲 Share Phone", request_contact=True)]]
        return await update.message.reply_text("Tap to verify phone:", reply_markup=ReplyKeyboardMarkup(btn, one_time_keyboard=True, resize_keyboard=True))

    active_games = await sync_to_async(lambda: list(GameRound.objects.filter(status__in=["LOBBY","STARTING","ACTIVE"])))()
    user_games = [g for g in active_games if str(update.effective_user.id) in g.players]
    kbd = []
    for g in user_games:
        url = f"https://vlad-bingo-web.onrender.com/api/live/?game_id={g.id}"
        kbd.append([InlineKeyboardButton(f"🎮 ENTER {int(g.bet_amount)} ETB HALL (Room #{g.id})", web_app=WebAppInfo(url=url))])
    
    kbd.append([InlineKeyboardButton("💵 Join 20", callback_data="r_20"), InlineKeyboardButton("💵 Join 50", callback_data="r_50")])
    kbd.append([InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🗑 Clear", callback_data="clear")])
    msg = f"🎰 **VLAD BINGO** 🎰\n👤 Player: {user.real_name}\n💰 Balance: {user.operational_credit} ETB"
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def btn_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    user = await sync_to_async(db_op)(uid, "get")
    if q.data.startswith("r_"):
        amt = int(q.data.split("_")[1])
        if user.operational_credit < amt: await q.edit_message_text("❌ Low Balance!"); return
        game, _ = await sync_to_async(GameRound.objects.get_or_create)(status="LOBBY", bet_amount=amt)
        user.current_joining_room = game.id; user.bot_state = "PICKING"; await sync_to_async(user.save)()
        await q.edit_message_text(f"🎟 **{amt} ETB Room.** Type Card # (1-100):")
    elif q.data == "dep": 
        await sync_to_async(db_op)(uid, "state", "DEPOSITING")
        await q.edit_message_text("💵 Enter deposit amount (Min 20):")
    elif q.data == "clear":
        await sync_to_async(db_op)(uid, "clear")
        await q.edit_message_text("🗑 Cards cleared!")

async def text_handler(update, context):
    uid = update.effective_user.id; user = await sync_to_async(db_op)(uid, "get")
    text = update.message.text
    if user.bot_state == "REG_NAME":
        user.real_name = text; user.bot_state = "IDLE"; await sync_to_async(user.save)()
        await update.message.reply_text(f"✅ Hello {text}!"); await start(update, context)
    elif text.isdigit():
        val = int(text)
        if user.bot_state == "PICKING":
            game = await sync_to_async(GameRound.objects.get)(id=user.current_joining_room)
            if val in game.players.values(): await update.message.reply_text("🚫 Taken!"); return
            user.operational_credit -= game.bet_amount; user.selected_cards.append(val); user.bot_state = "IDLE"; await sync_to_async(user.save)()
            game.players[str(uid)] = val; await sync_to_async(game.save)()
            await update.message.reply_text(f"✅ Joined! Type /start for the button.")
        elif user.bot_state == "DEPOSITING" and val >= 20:
            res, ref = await sync_to_async(init_deposit)(user, val)
            await update.message.reply_text(f"💳 [Click to pay {val} ETB]({res['data']['checkout_url']})", parse_mode='Markdown')

async def contact_handler(update: Update, context):
    user = await sync_to_async(db_op)(update.effective_user.id, "get")
    user.phone_number = update.message.contact.phone_number; user.bot_state = "IDLE"; await sync_to_async(user.save)()
    await update.message.reply_text("🎉 Verified!", reply_markup=ReplyKeyboardRemove()); await start(update, context)

async def post_init(app): await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(btn_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.add_handler(MessageHandler(filters.CONTACT, contact_handler))
    app.run_polling()
if __name__ == "__main__": run()
EOF

# 4. BUILD SCRIPT (Nuclear Fix for Database & Admin)
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
echo "✅ ULTIMATE ENGINE READY!"
