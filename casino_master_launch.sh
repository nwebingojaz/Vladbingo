#!/bin/bash
# VLAD BINGO - CASINO PRO (10 ETB ROOM + DYNAMIC COLOR LOGIC)

# 1. MODELS
cat <<'EOF' > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_cards = models.JSONField(default=list)
    current_room_context = models.IntegerField(null=True, blank=True)
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

# 2. MINI APP FACE (Lobby + Card Grid + Hall)
cat <<'EOF' > backend/bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>VladBingo Pro</title>
    <script src="https://telegram.org/js/telegram-web-app.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #0b1220; color: white; font-family: sans-serif; }
        .tier-card { border-radius: 12px; padding: 18px; display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; cursor: pointer; transition: 0.3s; }
        .tier-enabled { background: linear-gradient(135deg, #065f46, #059669); border: 2px solid #10b981; box-shadow: 0 4px 15px rgba(16, 185, 129, 0.2); }
        .tier-disabled { background: #111827; border: 2px solid #1f2937; color: #4b5563; opacity: 0.8; }
        .num-dot { width: 18px; height: 18px; border-radius: 50%; background: #1e293b; font-size: 0.6rem; display: flex; align-items: center; justify-content: center; border: 1px solid #334155; }
        .called { background: #fbbf24 !important; color: black !important; box-shadow: 0 0 10px #fbbf24; }
        .card-cell { background: #1e293b; aspect-ratio: 1/1; display: flex; align-items: center; justify-content: center; font-weight: bold; border-radius: 8px; border: 1px solid #334155; }
        .marked { background: #10b981 !important; border-color: #34d399; }
        .view-hidden { display: none; }
    </style>
</head>
<body class="p-4">
    <!-- TOP NAV -->
    <div class="flex justify-between items-center mb-6 bg-slate-800/40 p-3 rounded-2xl border border-slate-700">
        <div class="flex items-center gap-2">
            <span class="text-xl">💰</span>
            <div class="font-black text-emerald-400"><span id="header-balance">0.00</span> <span class="text-[10px] text-gray-400">ETB</span></div>
        </div>
        <button onclick="location.reload()" class="bg-slate-700 px-3 py-1.5 rounded-lg text-[10px] font-bold uppercase tracking-widest">Refresh 🔄</button>
    </div>

    <!-- VIEW 1: LOBBY -->
    <div id="view-lobby">
        <h2 class="text-[10px] font-bold text-gray-500 uppercase tracking-widest mb-4">Select a Room</h2>
        <div id="room-list" class="space-y-3"></div>
    </div>

    <!-- VIEW 2: CARD SELECTOR -->
    <div id="view-selector" class="view-hidden">
        <h2 class="text-center font-bold mb-4">Pick Your Lucky Card</h2>
        <div id="selector-grid" class="grid grid-cols-5 gap-2 h-96 overflow-y-auto bg-slate-900/50 p-3 rounded-2xl border border-slate-800"></div>
        <button onclick="showLobby()" class="w-full mt-4 py-3 text-gray-400 font-bold text-sm">⬅ Back to Lobby</button>
    </div>

    <!-- VIEW 3: GAME HALL -->
    <div id="view-hall" class="view-hidden">
        <div class="bg-slate-800 p-4 rounded-2xl border border-slate-700 mb-4 flex justify-between items-center">
            <div>
                <div class="text-[10px] text-gray-400 font-bold uppercase">Game Prize</div>
                <div class="text-2xl font-black text-emerald-400"><span id="prize">0</span> ETB</div>
            </div>
            <div class="text-right">
                <div id="game-status" class="text-[10px] font-bold text-yellow-500 animate-pulse">WAITING...</div>
                <div class="text-xs text-gray-400">Bet: <span id="hall-bet">0</span> ETB</div>
            </div>
        </div>
        <div id="tracker" class="grid grid-cols-1 gap-1 mb-6 p-2 bg-slate-950 rounded-xl border border-slate-900"></div>
        <div id="user-card" class="grid grid-cols-5 gap-1.5 bg-slate-800 p-2 rounded-2xl border-2 border-slate-700 shadow-2xl mb-6"></div>
        <button id="bingo-btn" class="w-full py-5 bg-yellow-500 text-black font-black text-xl rounded-2xl shadow-xl active:scale-95 transition-transform">BINGO! 📢</button>
    </div>

    <script>
        const tg = window.Telegram.WebApp; const uid = tg.initDataUnsafe.user ? tg.initDataUnsafe.user.id : 0;
        let userBal = 0; let activeBet = 0;

        function showLobby() { document.getElementById('view-lobby').style.display='block'; document.getElementById('view-selector').classList.add('view-hidden'); }
        function showSelector(amt) { activeBet = amt; document.getElementById('view-lobby').style.display='none'; document.getElementById('view-selector').classList.remove('view-hidden'); loadGrid(); }
        function showHall() { document.getElementById('view-lobby').style.display='none'; document.getElementById('view-hall').classList.remove('view-hidden'); }

        function loadGrid() {
            const g = document.getElementById('selector-grid'); g.innerHTML = '';
            for(let i=1; i<=100; i++) {
                let btn = document.createElement('button'); btn.className = "bg-slate-800 py-4 rounded-xl font-bold border border-slate-700";
                btn.innerText = i; btn.onclick = () => joinGame(i); g.appendChild(btn);
            }
        }

        function init() {
            fetch('/api/lobby-info/' + uid + '/').then(r=>r.json()).then(data => {
                userBal = data.balance; document.getElementById('header-balance').innerText = data.balance.toFixed(2);
                const rooms = [10, 20, 40, 50, 100]; const list = document.getElementById('room-list'); list.innerHTML = '';
                rooms.forEach(amt => {
                    let canPlay = userBal >= amt;
                    list.innerHTML += `<div onclick="${canPlay ? 'showSelector('+amt+')' : ''}" class="tier-card ${canPlay ? 'tier-enabled' : 'tier-disabled'}">
                        <div class="font-black text-2xl tracking-tighter">BINGO ${amt}</div>
                        <div class="text-right"><div class="text-[9px] opacity-70 uppercase font-bold">Possible Prize</div><div class="font-black text-lg">${(amt*2.4).toFixed(0)} ETB</div></div>
                    </div>`;
                });
                if(data.active_game) { showHall(); loadHall(data.active_game); }
            });
        }

        function joinGame(card) {
            fetch(`/api/join-room/${uid}/${activeBet}/${card}/`).then(r=>r.json()).then(d => {
                if(d.status === 'ok') location.reload(); else alert(d.error);
            });
        }

        function loadHall(gid) {
            const tracker = document.getElementById('tracker');
            ['B','I','N','G','O'].forEach((l, idx) => {
                let h = `<div class="flex gap-1 items-center"><div class="text-yellow-500 font-bold w-4 text-[8px]">${l}</div>`;
                for(let i=(idx*15)+1; i<=(idx*15)+15; i++) h += `<div id="t-${i}" class="num-dot">${i}</div>`;
                tracker.innerHTML += h + '</div>';
            });
            fetch(`/api/game-info/${gid}/${uid}/`).then(r=>r.json()).then(d => {
                document.getElementById('prize').innerText = d.prize;
                document.getElementById('hall-bet').innerText = d.bet;
                if(d.status === 'ACTIVE') document.getElementById('game-status').innerText = '● LIVE';
                d.board.forEach(row => row.forEach(val => {
                    const cell = document.createElement('div'); cell.className = 'card-cell'; cell.innerText = val === 'FREE' ? '★' : val;
                    if(val === 'FREE') cell.classList.add('marked'); cell.onclick = () => cell.classList.toggle('marked');
                    document.getElementById('user-card').appendChild(cell);
                }));
                d.called_numbers.forEach(n => document.getElementById('t-'+n).classList.add('called'));
            });
            const socket = new WebSocket('wss://' + window.location.host + '/ws/game/' + gid + '/');
            socket.onmessage = (e) => {
                const m = JSON.parse(e.data);
                if(m.action === 'call_number') document.getElementById('t-' + m.number).classList.add('called');
                if(m.action === 'game_over') { alert("Game Over! 1 minute until next round."); setTimeout(()=>location.reload(), 5000); }
            };
        }

        document.getElementById('bingo-btn').onclick = () => {
            fetch('/api/check-win/' + uid + '/').then(r=>r.json()).then(d => {
                if(d.status === 'WINNER') { alert("🏆 BINGO! Prize added to balance."); location.reload(); }
                else alert("❌ Not a Bingo yet!");
            });
        };

        init();
    </script>
</body>
</html>
EOF

# 3. VIEWS.PY (Lobby + Tiered Win Logic)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse
from .models import User, GameRound, PermanentCard
from decimal import Decimal

def live_view(request): return render(request, 'live_view.html')

def lobby_info(request, tg_id):
    user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
    active_game = GameRound.objects.exclude(status="ENDED").last()
    has_joined = active_game.id if (active_game and str(tg_id) in active_game.players) else None
    return JsonResponse({'balance': float(user.operational_credit), 'active_game': has_joined})

def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    if user.operational_credit < bet: return JsonResponse({'error': 'Low Balance'})
    game, _ = GameRound.objects.get_or_create(status="LOBBY", bet_amount=bet)
    if card_num in game.players.values(): return JsonResponse({'error': 'Card Taken'})
    user.operational_credit -= Decimal(bet); user.save()
    game.players[str(tg_id)] = card_num; game.save()
    return JsonResponse({'status': 'ok'})

def get_game_info(request, game_id, tg_id):
    game = GameRound.objects.get(id=game_id)
    user = User.objects.get(username=f"tg_{tg_id}")
    card_num = game.players.get(str(tg_id), 1)
    card = PermanentCard.objects.get(card_number=card_num)
    prize = float(len(game.players) * game.bet_amount) * 0.80 # 20% Cut
    return JsonResponse({'board': card.board, 'prize': round(prize, 2), 'bet': float(game.bet_amount), 'called_numbers': game.called_numbers, 'status': game.status})

def check_win(request, tg_id):
    user = User.objects.get(username=f"tg_{tg_id}")
    game = GameRound.objects.filter(status="ACTIVE").last()
    if not game: return JsonResponse({'status': 'NO_GAME'})
    card_num = game.players.get(str(tg_id))
    card = PermanentCard.objects.get(card_number=card_num)
    called_set = set(game.called_numbers)
    lines = 0
    for row in card.board:
        if all(c == "FREE" or c in called_set for c in row): lines += 1
    for c in range(5):
        if all(card.board[r][c] == "FREE" or card.board[r][c] in called_set for r in range(5)): lines += 1
    corners = [card.board[0][0], card.board[0][4], card.board[4][0], card.board[4][4]]
    if all(c in called_set for c in corners): lines += 1
    
    win_threshold = 2 if float(game.bet_amount) <= 40 else 3
    if lines >= win_threshold:
        prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
        user.operational_credit += prize; user.save()
        game.status = "ENDED"; game.save()
        return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
    return JsonResponse({'status': 'NOT_YET'})
EOF

# 4. BOT CENTER (The Simple Door)
cat <<'EOF' > backend/bingo/bot/main.py
import os, sys, django, asyncio
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR)); os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings"); django.setup()
from bingo.models import User

async def start(update, context):
    user, _ = await sync_to_async(User.objects.get_or_create)(username=f"tg_{update.effective_user.id}")
    msg = f"🎰 **VLAD BINGO PRO** 🎰\n💰 Balance: {user.operational_credit} ETB\n\nClick below to enter the lobby and pick a room!"
    kbd = [[InlineKeyboardButton("🎮 OPEN CASINO LOBBY", web_app=WebAppInfo(url="https://vlad-bingo-web.onrender.com/api/live/"))]]
    await update.message.reply_text(msg, reply_markup=InlineKeyboardMarkup(kbd), parse_mode='Markdown')

def run():
    app = Application.builder().token(os.environ.get("TELEGRAM_BOT_TOKEN")).build()
    app.add_handler(CommandHandler("start", start))
    app.run_polling()
if __name__ == "__main__": run()
EOF

# 5. URLS & BUILD
cat <<'EOF' > backend/bingo/urls.py
from django.urls import path
from .views import *
urlpatterns = [
    path('live/', live_view),
    path('lobby-info/<int:tg_id>/', lobby_info),
    path('join-room/<int:tg_id>/<int:bet>/<int:card_num>/', join_room),
    path('game-info/<int:game_id>/<int:tg_id>/', get_game_info),
    path('check-win/<int:tg_id>/', check_win),
]
EOF

echo "✅ COMPLETE CASINO SYSTEM READY!"
