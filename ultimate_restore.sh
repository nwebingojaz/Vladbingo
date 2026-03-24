#!/bin/bash
# VLAD BINGO - ULTIMATE RESTORATION SCRIPT

# 1. Folders
mkdir -p backend/bingo/bot backend/bingo/services backend/bingo/management/commands backend/bingo/templates backend/vlad_bingo

# 2. FULL MODELS
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

# 3. CHAPA SERVICE
cat <<'EOF' > backend/bingo/services/chapa.py
import os, requests, uuid
def init_deposit(user, amount):
    CHAPA_KEY = os.environ.get("CHAPA_SECRET_KEY")
    WEBHOOK = os.environ.get("WEBHOOK_URL")
    ref = f"dep-{uuid.uuid4().hex[:6]}"
    payload = {
        "amount": str(amount), "currency": "ETB", "tx_ref": ref,
        "email": f"user_{user.id}@vladbingo.com", "callback_url": WEBHOOK
    }
    headers = {"Authorization": f"Bearer {CHAPA_KEY}"}
    res = requests.post("https://api.chapa.co/v1/transaction/initialize", json=payload, headers=headers)
    return res.json(), ref
EOF

# 4. COMPRESSED INTERACTIVE MINI APP (HTML)
cat <<'EOF' > backend/bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>VladBingo Live</title>
    <script src="https://telegram.org/js/telegram-web-app.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #0f172a; color: white; font-family: sans-serif; }
        .num-dot { width: 18px; height: 18px; display: flex; align-items: center; justify-content: center; font-size: 0.6rem; border-radius: 50%; background: #1e293b; border: 1px solid #334155; }
        .called { background: #fbbf24 !important; color: black !important; box-shadow: 0 0 8px #fbbf24; }
        .card-cell { background: #1e293b; aspect-ratio: 1/1; display: flex; align-items: center; justify-content: center; font-weight: bold; border: 1px solid #334155; border-radius: 6px; }
        .marked { background: #10b981 !important; color: white !important; }
    </style>
</head>
<body class="p-3">
    <div id="tracker" class="grid grid-cols-1 gap-1 mb-4 p-2 bg-slate-900 rounded-lg border border-slate-800"></div>
    <h2 class="text-emerald-400 font-bold mb-2 text-center text-sm uppercase tracking-widest">Your Card #<span id="card-num">--</span></h2>
    <div id="user-card" class="grid grid-cols-5 gap-1 bg-slate-800 p-2 rounded-xl border-2 border-slate-700 shadow-2xl"></div>
    <button id="audio-btn" class="mt-4 w-full py-3 bg-green-600 rounded-lg font-bold shadow-lg text-sm">ACTIVATE VOICE 🔊</button>
    <script>
        const tg = window.Telegram.WebApp;
        const uid = tg.initDataUnsafe.user ? tg.initDataUnsafe.user.id : 0;
        const tracker = document.getElementById('tracker');
        ['B','I','N','G','O'].forEach((l, idx) => {
            let h = '<div class="flex gap-1 items-center"><div class="text-yellow-500 font-bold w-4 text-[10px]">'+l+'</div>';
            for(let i=(idx*15)+1; i<=(idx*15)+15; i++) h += '<div id="t-'+i+'" class="num-dot">'+i+'</div>';
            tracker.innerHTML += h + '</div>';
        });
        fetch('/api/user-card-data/' + uid + '/').then(res => res.json()).then(data => {
            document.getElementById('card-num').innerText = data.card_number;
            data.board.forEach(row => row.forEach(val => {
                const cell = document.createElement('div');
                cell.className = 'card-cell';
                cell.innerText = val === 'FREE' ? '★' : val;
                if(val === 'FREE') cell.classList.add('marked');
                cell.onclick = () => cell.classList.toggle('marked');
                document.getElementById('user-card').appendChild(cell);
            }));
        });
        const socket = new WebSocket('wss://' + window.location.host + '/ws/game/live/');
        socket.onmessage = (e) => {
            const m = JSON.parse(e.data);
            if(m.action === 'call_number') {
                const dot = document.getElementById('t-' + m.number);
                if(dot) dot.classList.add('called');
            }
        };
    </script>
</body>
</html>
EOF

# 5. BOT MAIN (Selector + Dealer)
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
    user.bot_state = "IDLE"
    await sync_to_async(user.save)()
    cards_text = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "None"
    msg = (f"🎰 **VLAD BINGO** 🎰\n\n🎫 **Your Cards:** {cards_text}\n💰 **Balance:** {user.operational_credit} ETB\n\nPick an action:")
    kbd = [[InlineKeyboardButton("🎮 ENTER LIVE HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))],
           [InlineKeyboardButton("➕ Add Card", callback_data="add"), InlineKeyboardButton("➖ Remove", callback_data="rem")],
           [InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🏧 Withdraw", callback_data="wd")]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def button_handler(update, context):
    q = update.callback_query
    user = await sync_to_async(db_get_user)(q.from_user.id, "")
    await q.answer()
    if q.data == "add": 
        user.bot_state = "SELECTING"
        await q.edit_message_text("🔢 Type a card number (1-100) to **ADD**:")
    elif q.data == "rem":
        user.bot_state = "REMOVING"
        await q.edit_message_text("🔢 Type the card number to **REMOVE**:")
    elif q.data == "dep":
        user.bot_state = "DEPOSITING"
        await q.edit_message_text("💵 Amount to deposit? (Min 20):")
    await sync_to_async(user.save)()

async def text_handler(update, context):
    user = await sync_to_async(db_get_user)(update.effective_user.id, "")
    text = update.message.text
    if not text.isdigit(): return
    val = int(text)
    if user.bot_state == "SELECTING":
        is_taken = await sync_to_async(lambda: User.objects.filter(selected_cards__contains=val).exists())()
        if is_taken: await update.message.reply_text(f"🚫 Card #{val} is taken!")
        else:
            user.selected_cards.append(val)
            await sync_to_async(user.save)()
            await update.message.reply_text(f"✅ Added Card #{val}! Type /start to play.")
    elif user.bot_state == "DEPOSITING" and val >= 20:
        res, ref = await sync_to_async(init_deposit)(user, val)
        await update.message.reply_text(f"💳 [Pay {val} ETB Now]({res['data']['checkout_url']})", parse_mode='Markdown')

async def new_game(update, context):
    if update.effective_user.username != "nwebingojaz": return
    game = await sync_to_async(GameRound.objects.create)(status="ACTIVE")
    await update.message.reply_text(f"🚀 Game #{game.id} Started!")
    nums = list(range(1, 76))
    random.shuffle(nums)
    layer = get_channel_layer()
    for n in nums:
        game.called_numbers.append(n); await sync_to_async(game.save)()
        await layer.group_send("bingo_live", {"type": "bingo_message", "message": {"action": "call_number", "number": n}})
        await asyncio.sleep(7)

async def post_init(app): await app.bot.delete_webhook(drop_pending_updates=True)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("newgame", new_game))
    app.add_handler(CallbackQueryHandler(button_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()

if __name__ == "__main__": run()
EOF

# 6. VIEWS & URLS SYNC
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import HttpResponse, JsonResponse
from .models import User, PermanentCard
def home(request): return HttpResponse("<h1>VladBingo Online</h1>")
def live_view(request): return render(request, 'live_view.html')
def get_user_card(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        card = PermanentCard.objects.get(card_number=user.selected_cards[0])
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
    except:
        card = PermanentCard.objects.first()
        return JsonResponse({'card_number': 1, 'board': card.board if card else []})
EOF

cat <<'EOF' > backend/bingo/urls.py
from django.urls import path
from .views import live_view, get_user_card
urlpatterns = [
    path('live/', live_view, name='live_view'),
    path('user-card-data/<int:tg_id>/', get_user_card),
]
EOF

echo "✅ ULTIMATE RESTORATION COMPLETE!"
