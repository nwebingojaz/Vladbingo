#!/bin/bash
# VLAD BINGO - THE MASTER SOURCE OF TRUTH

# 1. FIX MODELS
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
    players = models.JSONField(default=dict) 
    bet_amount = models.DecimalField(max_digits=10, decimal_places=2, default=20)
    status = models.CharField(max_length=20, default="LOBBY")

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    type = models.CharField(max_length=20)
EOF

# 2. FIX VIEWS (Win logic + 15% Cut + Dynamic Sync)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo is LIVE</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_game_info(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status__in=["LOBBY", "ACTIVE"]).last()
        total_pool = (len(game.players) * game.bet_amount) if game else 0
        prize = float(total_pool) * 0.85 # 15% Admin cut
        card_num = user.selected_cards[-1] if user.selected_cards else 1
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
        card = PermanentCard.objects.get(card_number=user.selected_cards[-1])
        called_set = set(game.called_numbers)
        won = any(all(c == "FREE" or c in called_set for c in row) for row in card.board)
        if won:
            prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.85")
            user.operational_credit += prize; user.save()
            game.status = f"WON_BY_{card.card_number}"; game.save()
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        return JsonResponse({'status': 'NOT_YET'})
    except: return JsonResponse({'status': 'ERROR'})
EOF

# 3. FIX BOT (Selector + Lobby + Dealer)
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio, random
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters
from channels.layers import get_channel_layer
from django.conf import settings

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()
from bingo.models import User, GameRound

async def start(update: Update, context):
    user, _ = await sync_to_async(User.objects.get_or_create)(username=f"tg_{update.effective_user.id}")
    user.bot_state = "IDLE"; await sync_to_async(user.save)()
    cards = ", ".join([f"#{c}" for c in user.selected_cards]) if user.selected_cards else "None"
    msg = f"🎰 **VLAD BINGO** 🎰\n💰 Balance: {user.operational_credit} ETB\n🎫 Cards: {cards}"
    kbd = [[InlineKeyboardButton("🎮 ENTER HALL", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))],
           [InlineKeyboardButton("➕ Add Card", callback_data="add"), InlineKeyboardButton("➖ Remove", callback_data="rem")],
           [InlineKeyboardButton("💳 Deposit", callback_data="dep"), InlineKeyboardButton("🏧 Withdraw", callback_data="wd")]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

async def btn_handler(update, context):
    q = update.callback_query; await q.answer(); uid = q.from_user.id
    user = await sync_to_async(User.objects.get)(username=f"tg_{uid}")
    if q.data == "add": user.bot_state="SELECTING"; await q.edit_message_text("Type Card # (1-100):")
    elif q.data == "rem": user.bot_state="REMOVING"; await q.edit_message_text("Type Card # to Remove:")
    elif q.data == "dep": user.bot_state="DEPOSITING"; await q.edit_message_text("Amount to Deposit (Min 20):")
    await sync_to_async(user.save)()

async def text_handler(update, context):
    user = await sync_to_async(User.objects.get)(username=f"tg_{update.effective_user.id}")
    if not update.message.text.isdigit(): return
    val = int(update.message.text)
    if user.bot_state == "SELECTING":
        user.selected_cards.append(val); await sync_to_async(user.save)()
        await update.message.reply_text(f"✅ Added Card #{val}!")
    elif user.bot_state == "REMOVING" and val in user.selected_cards:
        user.selected_cards.remove(val); await sync_to_async(user.save)()
        await update.message.reply_text(f"🗑 Removed Card #{val}!")
    elif user.bot_state == "DEPOSITING" and val >= 20:
        from bingo.services.chapa import init_deposit
        res, ref = await sync_to_async(init_deposit)(user, val)
        await update.message.reply_text(f"💳 [Pay {val} ETB Now]({res['data']['checkout_url']})", parse_mode='Markdown')

async def new_game(update, context):
    if update.effective_user.username != "nwebingojaz": return
    game = await sync_to_async(GameRound.objects.create)(status="ACTIVE")
    await update.message.reply_text(f"🚀 Game Started!")
    nums = list(range(1, 76)); random.shuffle(nums)
    layer = get_channel_layer()
    for n in nums:
        game.called_numbers.append(n); await sync_to_async(game.save)()
        await layer.group_send("bingo_live", {"type": "bingo_message", "message": {"action": "call_number", "number": n}})
        await asyncio.sleep(7)

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start)); app.add_handler(CommandHandler("newgame", new_game))
    app.add_handler(CallbackQueryHandler(btn_handler)); app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()
if __name__ == "__main__": run()
EOF

# 4. FIX MINI APP HTML (75-Grid + Interactive Card)
cat <<'EOF' > backend/bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
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
    <div id="tracker" class="grid grid-cols-1 gap-1 mb-4 p-2 bg-slate-900 rounded-lg"></div>
    <div class="flex justify-between mb-2 px-2 text-xs font-bold text-gray-400">
        <div>PRIZE: <span id="prize" class="text-emerald-400">0.00</span> ETB</div>
        <div>CARD #<span id="card-num">--</span></div>
    </div>
    <div id="user-card" class="grid grid-cols-5 gap-1 bg-slate-800 p-2 rounded-xl border-2 border-slate-700 shadow-2xl"></div>
    <button id="bingo-btn" class="mt-6 w-full py-4 bg-yellow-500 text-black font-black text-xl rounded-lg shadow-lg">BINGO! 📢</button>
    <script>
        const tg = window.Telegram.WebApp; const uid = tg.initDataUnsafe.user ? tg.initDataUnsafe.user.id : 0;
        const tracker = document.getElementById('tracker');
        ['B','I','N','G','O'].forEach((l, idx) => {
            let h = '<div class="flex gap-1 items-center"><div class="text-yellow-500 font-bold w-4 text-[10px]">'+l+'</div>';
            for(let i=(idx*15)+1; i<=(idx*15)+15; i++) h += '<div id="t-'+i+'" class="num-dot">'+i+'</div>';
            tracker.innerHTML += h + '</div>';
        });
        fetch('/api/game-info/' + uid + '/').then(r=>r.json()).then(data=>{
            document.getElementById('card-num').innerText = data.card_number;
            document.getElementById('prize').innerText = data.prize;
            data.board.forEach(row => row.forEach(val => {
                const cell = document.createElement('div'); cell.className = 'card-cell';
                cell.innerText = val === 'FREE' ? '★' : val;
                if(val === 'FREE') cell.classList.add('marked');
                cell.onclick = () => cell.classList.toggle('marked');
                document.getElementById('user-card').appendChild(cell);
            }));
            data.called_numbers.forEach(n => { document.getElementById('t-'+n).classList.add('called'); });
        });
        const socket = new WebSocket('wss://' + window.location.host + '/ws/game/live/');
        socket.onmessage = (e) => {
            const m = JSON.parse(e.data);
            if(m.action === 'call_number') {
                const dot = document.getElementById('t-' + m.number);
                if(dot) dot.classList.add('called');
            }
        };
        document.getElementById('bingo-btn').onclick = () => {
            fetch('/api/check-win/' + uid + '/').then(r=>r.json()).then(d => {
                if(d.status === 'WINNER') alert("🏆 BINGO! You won " + d.prize + " ETB!");
                else alert("❌ Not a Bingo yet!");
            });
        };
    </script>
</body>
</html>
EOF

# 5. FIX BUILD SCRIPT
cat <<'EOF' > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input
python manage.py init_bingo || true
EOF

echo "✅ MASTER RESTORATION SCRIPT READY!"
