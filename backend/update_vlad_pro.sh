#!/bin/bash
echo "🚀 Starting VLAD BINGO PRO Master Update..."

# Ensure directories exist
mkdir -p bingo/templates
mkdir -p bingo/bot

# 1. Update Models
cat << 'INNER' > bingo/models.py
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
    players = models.JSONField(default=dict)
    bet_amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=20, default="LOBBY")
    winner_username = models.CharField(max_length=100, null=True, blank=True)
    winner_prize = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    finished_at = models.DateTimeField(null=True, blank=True)
INNER

# 2. Update Views
cat << 'INNER' > bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound
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
    return JsonResponse({
        'balance': float(user.operational_credit), 
        'active_game': joined_id,
        'time_left': time_left
    })

def get_history(request):
    history = GameRound.objects.filter(status="ENDED").order_by('-id')[:10]
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
INNER

# 3. Update HTML
cat << 'INNER' > bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>VLAD BINGO PRO</title>
    <script src="https://telegram.org/js/telegram-web-app.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #0b2e24; color: white; font-family: sans-serif; overflow: hidden; }
        .header-bg { background: #111827; border-bottom: 2px solid #10b981; }
        .card-num { height: 32px; background: #1a3a32; border: 1px solid #2d5a4e; border-radius: 4px; font-size: 0.65rem; font-weight: bold; color: #4ade80; }
        .card-num.active { background: #10b981 !important; color: white; border-color: white; transform: scale(1.1); }
        .modal { background: rgba(0,0,0,0.9); position: fixed; inset: 0; z-index: 100; padding: 20px; }
        .hidden { display: none; }
        .history-row { background: #1a3a32; margin-bottom: 4px; padding: 8px; border-radius: 6px; font-size: 10px; display: grid; grid-template-columns: 1fr 2fr 1fr 1fr; }
    </style>
</head>
<body class="antialiased select-none">
    <div class="header-bg p-3 flex justify-between items-center shadow-lg">
        <div class="flex items-center gap-2">
            <div class="bg-emerald-500 p-1 rounded font-black text-[10px] text-black italic">VLAD</div>
            <div class="font-black text-xs uppercase">BINGO PRO</div>
        </div>
        <div class="bg-slate-800 px-3 py-1 rounded-full flex items-center gap-2">
            <span class="text-yellow-400">👛</span><span id="bal-header" class="font-bold text-xs">0.00</span>
        </div>
    </div>
    <div class="bg-emerald-950/50 p-2 flex justify-around text-[9px] font-bold text-emerald-300 uppercase border-b border-emerald-900">
        <div>🎲 Tier: 10</div><div onclick="openHistory()">📜 History</div><div onclick="location.reload()">🔄 Refresh</div>
    </div>
    <div class="bg-black/40 p-1 text-center border-b border-white/5">
        <span class="text-[10px] text-emerald-400 font-bold uppercase">Lobby Closes: </span>
        <span id="timer" class="text-[10px] font-mono font-black text-white ml-1">00:00</span>
    </div>
    <div id="v-selector" class="p-4">
        <div id="grid-200" class="grid grid-cols-10 gap-1 h-72 overflow-y-auto mb-6 p-2 bg-black/20 rounded-xl"></div>
        <button onclick="joinGame()" class="w-full py-4 bg-emerald-500 rounded-xl font-black text-lg shadow-lg active:scale-95">▶ START!</button>
    </div>
    <div id="m-history" class="modal hidden">
        <div class="flex justify-between items-center mb-4 border-b border-emerald-500 pb-2">
            <h2 class="text-emerald-400 font-black italic uppercase">History</h2>
            <button onclick="closeHistory()" class="text-xl">✕</button>
        </div>
        <div id="history-list"></div>
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
                d.history.forEach(h => { list.innerHTML += `<div class="history-row"><span>#${h.game_id}</span><span class="text-emerald-400">@${h.winner}</span><span>${h.called}</span><span class="font-bold">${h.prize}</span></div>`; });
            });
        }
        function closeHistory() { document.getElementById('m-history').classList.add('hidden'); }
        function joinGame() {
            if(!myCard) return alert("Select Card!");
            fetch(`/api/join-room/${uid}/10/${myCard}/`).then(r=>r.json()).then(d => { if(d.status==='ok') location.reload(); else alert(d.error); });
        }
        initGrid();
        fetch('/api/lobby-info/'+uid+'/').then(r=>r.json()).then(d => {
            document.getElementById('bal-header').innerText = d.balance.toFixed(2);
            let timeLeft = d.time_left;
            const tEl = document.getElementById('timer');
            setInterval(() => { if(timeLeft > 0) { timeLeft--; let m=Math.floor(timeLeft/60), s=timeLeft%60; tEl.innerText=m+":"+(s<10?"0"+s:s); } }, 1000);
        });
    </script>
</body>
</html>
INNER

# 4. Update URLs
cat << 'INNER' > bingo/urls.py
from django.urls import path
from .views import live_view, lobby_info, join_room, get_history
urlpatterns = [
    path('live/', live_view),
    path('lobby-info/<int:tg_id>/', lobby_info),
    path('join-room/<int:tg_id>/<int:bet>/<int:card_num>/', join_room),
    path('history/', get_history),
]
INNER

# 5. Run Migrations
python3 manage.py makemigrations bingo
python3 manage.py migrate

echo "✅ VLAD BINGO PRO is Updated!"
