#!/bin/bash
# VLAD BINGO - LUDO PRO EDITION (200 CARDS + LIVE SELECTION)

# 1. MODELS (Support 200 cards and Player States)
cat <<'EOF' > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_cards = models.JSONField(default=list)
    bot_state = models.CharField(max_length=30, default="IDLE")

class PermanentCard(models.Model):
    card_number = models.PositiveSmallIntegerField(unique=True)
    board = models.JSONField()

class GameRound(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    called_numbers = models.JSONField(default=list)
    # players = {"tg_id": {"card": 12, "paid": True}}
    players = models.JSONField(default=dict) 
    bet_amount = models.DecimalField(max_digits=10, decimal_places=2, default=20)
    status = models.CharField(max_length=20, default="LOBBY") # LOBBY, ACTIVE, ENDED
EOF

# 2. MINI APP UI (Lobby -> Selector -> Hall)
cat <<'EOF' > backend/bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>Next Bingo Pro</title>
    <script src="https://telegram.org/js/telegram-web-app.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #0b1220; color: white; font-family: sans-serif; overflow-x: hidden; }
        .tier-btn { background: #1e293b; border: 1px solid #334155; padding: 20px; border-radius: 15px; display: flex; justify-content: space-between; align-items: center; width: 100%; margin-bottom: 10px; }
        .tier-active { background: linear-gradient(135deg, #065f46, #059669); border-color: #10b981; }
        .card-btn { background: #1e293b; border: 1px solid #334155; border-radius: 5px; height: 35px; font-size: 0.8rem; font-weight: bold; }
        .card-taken { background: #000; color: #4b5563; border-color: #111; }
        .card-mine { background: #10b981 !important; color: white; border-color: #34d399; }
        .num-dot { width: 16px; height: 16px; border-radius: 50%; background: #1e293b; font-size: 0.5rem; display: flex; align-items: center; justify-content: center; border: 1px solid #334155; }
        .called { background: #fbbf24 !important; color: black !important; }
        .hidden { display: none; }
        .modal { position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%); background: #1e293b; padding: 20px; border-radius: 15px; border: 2px solid #ef4444; z-index: 100; text-align: center; width: 80%; }
    </style>
</head>
<body class="p-3">
    <!-- BAL BAR -->
    <div class="flex justify-between items-center mb-4 bg-slate-800/50 p-3 rounded-xl border border-slate-700">
        <div class="flex items-center gap-2">💰 <span id="bal">0.00</span> ETB</div>
        <button onclick="location.reload()" class="text-[10px] bg-slate-700 p-2 rounded">REFRESH 🔄</button>
    </div>

    <!-- ERROR MODAL -->
    <div id="err-modal" class="modal hidden">
        <h2 class="text-red-500 font-bold mb-2">Error</h2>
        <p id="err-msg" class="text-sm mb-4">Insufficient Balance</p>
        <button onclick="hideErr()" class="bg-slate-700 px-6 py-2 rounded">OK</button>
    </div>

    <!-- VIEW 1: LOBBY -->
    <div id="v-lobby">
        <div class="space-y-3" id="room-list"></div>
    </div>

    <!-- VIEW 2: SELECTOR (200 CARDS) -->
    <div id="v-selector" class="hidden">
        <div class="grid grid-cols-5 gap-2 h-96 overflow-y-auto mb-4 p-2 bg-slate-900 rounded-xl" id="card-grid"></div>
        <div class="flex gap-2">
            <button onclick="showLobby()" class="flex-1 py-4 bg-slate-800 rounded-xl font-bold">CANCEL</button>
            <button id="start-btn" class="flex-1 py-4 bg-emerald-600 rounded-xl font-bold italic">START! ▶</button>
        </div>
    </div>

    <!-- VIEW 3: LIVE HALL -->
    <div id="v-hall" class="hidden">
        <div class="flex justify-between mb-4 text-xs font-bold text-yellow-500">
            <div>PRIZE: <span id="h-prize" class="text-white text-lg">--</span> ETB</div>
            <div class="text-right">ROOM: <span id="h-bet" class="text-white text-lg">--</span> ETB</div>
        </div>
        <div id="tracker" class="grid grid-cols-1 gap-1 mb-4 p-2 bg-slate-950 rounded-lg"></div>
        <div id="user-card" class="grid grid-cols-5 gap-1 bg-slate-800 p-2 rounded-xl border-2 border-slate-700 shadow-2xl mb-4"></div>
        <button id="bingo-btn" class="w-full py-5 bg-yellow-500 text-black font-black text-xl rounded-xl">BINGO! 📢</button>
    </div>

    <script>
        const tg = window.Telegram.WebApp; const uid = tg.initDataUnsafe.user ? tg.initDataUnsafe.user.id : 0;
        let balance = 0; let activeBet = 0; let myCard = null;

        function hideErr() { document.getElementById('err-modal').classList.add('hidden'); }
        function showLobby() { document.getElementById('v-lobby').classList.remove('hidden'); document.getElementById('v-selector').classList.add('hidden'); }
        function showSelector(amt) { activeBet = amt; document.getElementById('v-lobby').classList.add('hidden'); document.getElementById('v-selector').classList.remove('hidden'); renderCards(); }
        function showHall() { document.getElementById('v-selector').classList.add('hidden'); document.getElementById('v-hall').classList.remove('hidden'); }

        function renderCards() {
            const g = document.getElementById('card-grid'); g.innerHTML = '';
            for(let i=1; i<=200; i++) {
                let b = document.createElement('button'); b.className = "card-btn"; b.innerText = i;
                b.onclick = () => { myCard = i; Array.from(g.children).forEach(c=>c.classList.remove('card-mine')); b.classList.add('card-mine'); };
                g.appendChild(b);
            }
        }

        function init() {
            fetch('/api/lobby-info/' + uid + '/').then(r=>r.json()).then(d => {
                balance = d.balance; document.getElementById('bal').innerText = d.balance;
                const list = document.getElementById('room-list');
                [10, 20, 40, 50, 100].forEach(amt => {
                    let active = balance >= amt ? 'tier-active' : '';
                    list.innerHTML += `<div onclick="showSelector(${amt})" class="tier-btn ${active}"><div class="font-black text-xl">BINGO ${amt}</div><div class="text-right text-xs opacity-80 font-bold">WIN: ${amt*4} ETB</div></div>`;
                });
                if(d.active_game) { showHall(); loadHall(d.active_game); }
            });
        }

        document.getElementById('start-btn').onclick = () => {
            if(!myCard) return alert("Select a card first!");
            fetch(`/api/join-room/${uid}/${activeBet}/${myCard}/`).then(r=>r.json()).then(d => {
                if(d.status === 'ok') location.reload();
                else { document.getElementById('err-modal').classList.remove('hidden'); document.getElementById('err-msg').innerText = d.error; }
            });
        };

        function loadHall(gid) {
            const tr = document.getElementById('tracker');
            ['B','I','N','G','O'].forEach((l, idx) => {
                let h = `<div class="flex gap-1 items-center"><div class="text-yellow-500 font-bold w-4 text-[8px]">${l}</div>`;
                for(let i=(idx*15)+1; i<=(idx*15)+15; i++) h += `<div id="t-${i}" class="num-dot">${i}</div>`;
                tr.innerHTML += h + '</div>';
            });
            fetch(`/api/game-info/${gid}/${uid}/`).then(r=>r.json()).then(d => {
                document.getElementById('h-prize').innerText = d.prize;
                document.getElementById('h-bet').innerText = d.bet;
                d.board.forEach(row => row.forEach(val => {
                    const c = document.createElement('div'); c.className = 'card-cell'; c.innerText = val === 'FREE' ? '★' : val;
                    if(val === 'FREE') c.classList.add('marked'); c.onclick = () => c.classList.toggle('marked');
                    document.getElementById('user-card').appendChild(c);
                }));
            });
            const ws = new WebSocket('wss://' + window.location.host + '/ws/game/' + gid + '/');
            ws.onmessage = (e) => {
                const m = JSON.parse(e.data);
                if(m.action === 'call_number') document.getElementById('t-' + m.number).classList.add('called');
            };
        }

        init();
    </script>
</body>
</html>
EOF

# 3. API LOGIC (VIEWS.PY)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse
from .models import User, GameRound, PermanentCard
from decimal import Decimal

def live_view(request): return render(request, 'live_view.html')

def lobby_info(request, tg_id):
    user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
    active_game = GameRound.objects.filter(status="ACTIVE").last()
    has_joined = active_game.id if (active_game and str(tg_id) in active_game.players) else None
    return JsonResponse({'balance': float(user.operational_credit), 'active_game': has_joined})

def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    if user.operational_credit < bet: return JsonResponse({'status': 'error', 'error': 'Insufficient Balance'})
    game, _ = GameRound.objects.get_or_create(status="LOBBY", bet_amount=bet)
    user.operational_credit -= Decimal(bet); user.save()
    game.players[str(tg_id)] = card_num; game.save()
    return JsonResponse({'status': 'ok'})

def get_game_info(request, game_id, tg_id):
    game = GameRound.objects.get(id=game_id)
    user = User.objects.get(username=f"tg_{tg_id}")
    card_num = game.players.get(str(tg_id), 1)
    card = PermanentCard.objects.get(card_number=card_num)
    prize = float(len(game.players) * game.bet_amount) * 0.80
    return JsonResponse({'board': card.board, 'prize': round(prize, 2), 'bet': float(game.bet_amount), 'called_numbers': game.called_numbers})

def check_win(request, tg_id):
    return JsonResponse({'status': 'NOT_YET'})
EOF

# 4. BOT CENTER (Simple Entrance)
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR)); os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings"); django.setup()

async def start(update, context):
    msg = f"🎰 **VLAD BINGO PRO** 🎰\nEnter the Lobby to play:"
    kbd = [[InlineKeyboardButton("🎮 OPEN LOBBY", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.run_polling()
if __name__ == "__main__": run()
EOF

echo "✅ NEXT-LUDO CLONE ENGINE APPLIED!"
