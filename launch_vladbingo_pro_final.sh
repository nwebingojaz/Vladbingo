#!/bin/bash
echo "🚀 STARTING VLAD BINGO PRO TOTAL REBUILD..."

# 1. SETUP FOLDERS
cd ~/vladbingo/backend
mkdir -p bingo/templates
mkdir -p bingo/management/commands
mkdir -p bingo/bot

# 2. CREATE MODELS (Fixed with Transaction)
cat << 'EOF' > bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone

class User(AbstractUser):
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    selected_cards = models.JSONField(default=list)
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
    winner_username = models.CharField(max_length=100, null=True, blank=True)
    winner_prize = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    finished_at = models.DateTimeField(null=True, blank=True)

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    type = models.CharField(max_length=20, default="DEPOSIT")
    note = models.TextField(default="")
EOF

# 3. CREATE VIEWS (History, Timer, Tiered Win Logic)
cat << 'EOF' > bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound, Transaction
from django.utils import timezone
from decimal import Decimal

def live_view(request):
    return render(request, 'live_view.html')

def lobby_info(request, tg_id):
    user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
    active_game = GameRound.objects.filter(status="LOBBY", bet_amount=10).first()
    time_left = 0
    if active_game:
        elapsed = (timezone.now() - active_game.created_at).total_seconds()
        time_left = max(0, 60 - int(elapsed))
    
    joined_id = active_game.id if (active_game and str(tg_id) in active_game.players) else None
    return JsonResponse({'balance': float(user.operational_credit), 'active_game': joined_id, 'time_left': time_left})

def get_history(request):
    history = GameRound.objects.filter(status="ENDED").order_by('-id')[:15]
    data = [{'game_id': g.id, 'winner': g.winner_username or "None", 'called': f"{len(g.called_numbers)}/75", 'prize': float(g.winner_prize)} for g in history]
    return JsonResponse({'history': data})

def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    if user.operational_credit < bet: return JsonResponse({'status': 'error', 'error': 'Low Balance'})
    game, _ = GameRound.objects.get_or_create(status="LOBBY", bet_amount=bet)
    game.players[str(tg_id)] = card_num
    game.save()
    user.operational_credit -= Decimal(bet)
    user.save()
    return JsonResponse({'status': 'ok'})

def get_game_info(request, game_id, tg_id):
    game = GameRound.objects.get(id=game_id)
    card_num = game.players.get(str(tg_id), 1)
    card = PermanentCard.objects.get(card_number=card_num)
    prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
    return JsonResponse({'board': card.board, 'called': game.called_numbers, 'prize': float(prize), 'status': game.status})

def check_win(request, game_id, tg_id):
    user = User.objects.get(username=f"tg_{tg_id}")
    game = GameRound.objects.get(id=game_id)
    if game.status != "ACTIVE": return JsonResponse({'status': 'WAITING'})
    card_num = game.players.get(str(tg_id))
    card = PermanentCard.objects.get(card_number=card_num)
    called_set = set(game.called_numbers)
    board = card.board
    lines = 0
    for r in range(5):
        if all(board[r][c] == "FREE" or board[r][c] in called_set for c in range(5)): lines += 1
        if all(board[c][r] == "FREE" or board[c][r] in called_set for c in range(5)): lines += 1
    corners = [board[0][0], board[0][4], board[4][0], board[4][4]]
    if all(c == "FREE" or c in called_set for c in corners): lines += 1
    
    threshold = 2 if float(game.bet_amount) <= 40 else 3
    if lines >= threshold:
        prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
        user.operational_credit += prize; user.save()
        game.status = "ENDED"; game.winner_username = user.username; game.winner_prize = prize
        game.finished_at = timezone.now(); game.save()
        return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
    return JsonResponse({'status': 'NOT_YET'})
EOF

# 4. CREATE THE EMERALD UI (Vlad Pro Style)
cat << 'EOF' > bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>VLAD BINGO PRO</title>
    <script src="https://telegram.org/js/telegram-web-app.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #064e3b; color: white; font-family: sans-serif; overflow: hidden; }
        .header-bg { background: #111827; border-bottom: 2px solid #10b981; }
        .card-num { height: 32px; background: #065f46; border: 1px solid #059669; border-radius: 4px; font-size: 0.65rem; font-weight: bold; color: #a7f3d0; }
        .card-num.active { background: #10b981 !important; color: white; border-color: white; transform: scale(1.1); box-shadow: 0 0 10px #10b981; }
        .modal { background: rgba(0,0,0,0.95); position: fixed; inset: 0; z-index: 100; padding: 20px; }
        .hidden { display: none; }
        .history-row { background: #065f46; margin-bottom: 4px; padding: 8px; border-radius: 6px; font-size: 10px; display: grid; grid-template-columns: 1fr 2.5fr 1fr 1fr; }
    </style>
</head>
<body class="antialiased select-none">
    <div class="header-bg p-3 flex justify-between items-center shadow-lg">
        <div class="flex items-center gap-2">
            <div class="bg-emerald-500 p-1 rounded font-black text-[10px] text-black italic">VLAD</div>
            <div class="font-black text-xs uppercase">BINGO PRO</div>
        </div>
        <div class="bg-slate-800 px-3 py-1 rounded-full border border-slate-700 flex items-center gap-2">
            <span class="text-yellow-400">👛</span><span id="bal-header" class="font-bold text-xs">0.00</span>
        </div>
    </div>
    <div class="bg-emerald-900/50 p-2 flex justify-around text-[9px] font-bold text-emerald-300 uppercase border-b border-emerald-800">
        <div>🎲 Room: 10 Birr</div><div onclick="openHistory()">📜 History</div><div onclick="location.reload()">🔄 Refresh</div>
    </div>
    <div class="bg-black/40 p-1 text-center border-b border-white/5">
        <span class="text-[10px] text-emerald-400 font-bold uppercase tracking-widest">Lobby Closes: </span>
        <span id="timer" class="text-[10px] font-mono font-black text-white ml-1">01:00</span>
    </div>
    <div id="v-selector" class="p-4">
        <div id="grid-200" class="grid grid-cols-10 gap-1 h-80 overflow-y-auto mb-6 p-2 bg-black/20 rounded-xl border border-white/5"></div>
        <button onclick="joinGame()" class="w-full py-5 bg-emerald-500 rounded-2xl font-black text-xl shadow-xl active:scale-95 transition-all">▶ START!</button>
    </div>
    <div id="m-history" class="modal hidden">
        <div class="flex justify-between items-center mb-6 border-b border-emerald-500 pb-3">
            <h2 class="text-emerald-400 font-black italic uppercase text-lg">Bets History</h2>
            <button onclick="closeHistory()" class="text-2xl">✕</button>
        </div>
        <div id="history-list" class="h-full overflow-y-auto pb-20"></div>
    </div>
    <script>
        const tg = window.Telegram.WebApp; const uid = tg.initDataUnsafe.user ? tg.initDataUnsafe.user.id : 0;
        let myCard = null;
        function initGrid() {
            const g = document.getElementById('grid-200'); g.innerHTML = '';
            for(let i=1; i<=200; i++) {
                let b = document.createElement('button'); b.className="card-num"; b.id="c-"+i; b.innerText=i;
                b.onclick=()=> { myCard=i; document.querySelectorAll('.card-num').forEach(el=>el.classList.remove('active')); b.classList.add('active'); };
                g.appendChild(b);
            }
        }
        function openHistory() {
            document.getElementById('m-history').classList.remove('hidden');
            fetch('/api/history/').then(r=>r.json()).then(d => {
                const list = document.getElementById('history-list'); list.innerHTML = '';
                d.history.forEach(h => { list.innerHTML += `<div class="history-row"><span>#${h.game_id}</span><span class="text-emerald-400">@${h.winner}</span><span>${h.called}</span><span class="text-white font-black">${h.prize}</span></div>`; });
            });
        }
        function closeHistory() { document.getElementById('m-history').classList.add('hidden'); }
        function joinGame() {
            if(!myCard) return alert("Select a card!");
            fetch(`/api/join-room/${uid}/10/${myCard}/`).then(r=>r.json()).then(d => { if(d.status==='ok') location.reload(); else alert(d.error); });
        }
        initGrid();
        fetch('/api/lobby-info/' + uid + '/').then(r=>r.json()).then(d => {
            document.getElementById('bal-header').innerText = d.balance.toFixed(2);
            let timeLeft = d.time_left; const tEl = document.getElementById('timer');
            const itv = setInterval(() => { if(timeLeft<=0){ tEl.innerText="00:00"; clearInterval(itv); return; } timeLeft--; let m=Math.floor(timeLeft/60), s=timeLeft%60; tEl.innerText=m+":"+(s<10?"0"+s:s); }, 1000);
        });
    </script>
</body>
</html>
EOF

# 5. CREATE API URLS
cat << 'EOF' > bingo/urls.py
from django.urls import path
from .views import live_view, lobby_info, join_room, get_history, get_game_info, check_win
urlpatterns = [
    path('live/', live_view),
    path('lobby-info/<int:tg_id>/', lobby_info),
    path('join-room/<int:tg_id>/<int:bet>/<int:card_num>/', join_room),
    path('game-info/<int:game_id>/<int:tg_id>/', get_game_info),
    path('check-win/<int:game_id>/<int:tg_id>/', check_win),
    path('history/', get_history),
]
EOF

# 6. CREATE INFINITE DEALER LOOP
cat << 'EOF' > bingo/management/commands/run_dealer.py
import time, random
from django.core.management.base import BaseCommand
from django.utils import timezone
from bingo.models import GameRound

class Command(BaseCommand):
    def handle(self, *args, **options):
        self.stdout.write("VLAD BINGO DEALER IS LIVE")
        while True:
            now = timezone.now()
            room = GameRound.objects.filter(bet_amount=10).exclude(status="ENDED").first()
            if not room:
                last = GameRound.objects.filter(bet_amount=10, status="ENDED").order_by("-finished_at").first()
                if not last or (now - last.finished_at).total_seconds() >= 60:
                    room = GameRound.objects.create(bet_amount=10, status="LOBBY")
            elif room.status == "LOBBY" and (now - room.created_at).total_seconds() >= 60:
                room.status = "ACTIVE"; room.save()
            elif room.status == "ACTIVE":
                called = room.called_numbers
                if len(called) < 75:
                    remaining = [n for n in range(1, 76) if n not in called]
                    called.append(random.choice(remaining))
                    room.called_numbers = called; room.save()
                else:
                    room.status = "ENDED"; room.finished_at = now; room.save()
            time.sleep(4)
EOF

# 7. RUN DATABASE UPDATE
python3 manage.py makemigrations bingo
python3 manage.py migrate
python3 manage.py init_bingo

echo "✅ VLAD BINGO PRO REBUILD COMPLETE!"
