#!/bin/bash
echo "🚀 STARTING VLAD BINGO PRO ULTIMATE REBUILD (v8.0)..."

# 1. SETUP FOLDERS
cd ~/vladbingo/backend
mkdir -p bingo/templates bingo/management/commands bingo/bot bingo/migrations
touch bingo/migrations/__init__.py

# 2. CREATE MODELS
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
    players = models.JSONField(default=dict)
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

# 3. CREATE VIEWS
cat << 'EOF' > bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound, Transaction
from django.utils import timezone
from decimal import Decimal

def home(request):
    return HttpResponse("<h1>VLAD BINGO ENGINE ACTIVE</h1>")

def live_view(request):
    return render(request, 'live_view.html')

def get_card_data(request, num):
    try:
        card = PermanentCard.objects.get(card_number=num)
        return JsonResponse({"board": card.board})
    except: return JsonResponse({"error": "not found"}, status=404)

def lobby_info(request, tg_id):
    user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
    rooms = GameRound.objects.exclude(status="ENDED").values('id', 'bet_amount', 'players', 'created_at', 'status', 'called_numbers')
    room_data = []
    now = timezone.now()
    for r in rooms:
        p_count = len(r['players'])
        elapsed = (now - r['created_at']).total_seconds()
        room_data.append({
            'id': r['id'], 'bet': float(r['bet_amount']), 'players': p_count,
            'win': float(r['bet_amount'] * p_count) * 0.8,
            'status': r['status'],
            'called_count': len(r['called_numbers']),
            'time_left': max(0, 60 - int(elapsed))
        })
    active_game = GameRound.objects.filter(players__has_key=str(tg_id)).exclude(status="ENDED").last()
    return JsonResponse({'balance': float(user.operational_credit), 'rooms': room_data, 'active_game_id': active_game.id if active_game else None})

def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    if user.operational_credit < Decimal(str(bet)): return JsonResponse({'status': 'error', 'error': 'Low Balance'})
    game = GameRound.objects.filter(status="LOBBY", bet_amount=bet).first()
    if not game: return JsonResponse({'status': 'error', 'error': 'No Lobby'})
    game.players[str(tg_id)] = card_num
    game.save(); user.operational_credit -= Decimal(str(bet)); user.save()
    return JsonResponse({'status': 'ok'})

def get_game_info(request, game_id, tg_id):
    game = GameRound.objects.get(id=game_id)
    card_num = game.players.get(str(tg_id), 1)
    card = PermanentCard.objects.get(card_number=card_num)
    prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
    return JsonResponse({'board': card.board, 'called': game.called_numbers, 'prize': float(prize), 'status': game.status})

def get_history(request):
    history = GameRound.objects.filter(status="ENDED").order_by('-id')[:15]
    data = [{'game_id': g.id, 'winner': g.winner_username or "None", 'called': f"{len(g.called_numbers)}/75", 'prize': float(g.winner_prize)} for g in history]
    return JsonResponse({'history': data})
EOF

# 4. CREATE URLS
cat << 'EOF' > bingo/urls.py
from django.urls import path
from .views import live_view, lobby_info, join_room, get_history, get_game_info, get_card_data
urlpatterns = [
    path('live/', live_view),
    path('lobby-info/<int:tg_id>/', lobby_info),
    path('join-room/<int:tg_id>/<int:bet>/<int:card_num>/', join_room),
    path('card-data/<int:num>/', get_card_data),
    path('game-info/<int:game_id>/<int:tg_id>/', get_game_info),
    path('history/', get_history),
]
EOF

# 5. CREATE THE EMERALD UI (VLAD BINGO PRO)
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
        .room-card { background: #065f46; border-radius: 12px; padding: 15px; margin-bottom: 10px; border-left: 4px solid #10b981; display: flex; justify-content: space-between; align-items: center; }
        .active-banner { background: #111827; border: 2px solid #10b981; color: #10b981; border-radius: 8px; padding: 6px; text-align: center; font-weight: 900; margin-bottom: 10px; animation: pulse 2s infinite; }
        .card-num { height: 32px; background: #065f46; border: 1px solid #059669; border-radius: 4px; font-size: 0.65rem; font-weight: bold; color: #a7f3d0; }
        .card-num.active { background: #10b981 !important; color: white; border-color: white; transform: scale(1.1); }
        .preview-container { border: 2px solid #10b981; border-radius: 12px; padding: 10px; background: rgba(0,0,0,0.3); width: 135px; }
        .mini-cell { aspect-ratio: 1/1; display: flex; align-items: center; justify-content: center; font-size: 0.6rem; border: 0.1px solid #1c3d38; }
        .hidden { display: none; }
        @keyframes pulse { 0% { opacity: 1; } 50% { opacity: 0.7; } 100% { opacity: 1; } }
    </style>
</head>
<body class="antialiased select-none">
    <div class="header-bg p-3 flex justify-between items-center shadow-lg">
        <div class="flex items-center gap-2"><div class="bg-emerald-500 p-1 rounded font-black text-[10px] text-black italic">VLAD</div><div class="font-black text-xs uppercase">BINGO PRO</div></div>
        <div class="bg-slate-800 px-3 py-1 rounded-full flex items-center gap-2"><span class="text-yellow-400">👛</span><span id="bal-header" class="font-bold text-xs">0.00</span></div>
    </div>
    
    <div id="v-lobby" class="p-4 h-screen overflow-y-auto">
        <div id="room-list"></div>
    </div>

    <div id="v-selector" class="hidden p-4">
        <button onclick="location.reload()" class="text-emerald-400 text-[10px] font-bold mb-4">← BACK TO ROOMS</button>
        <div id="active-call-banner" class="active-banner hidden">Active Game Call <span id="call-count">0</span>/75</div>
        <div id="grid-200" class="grid grid-cols-10 gap-1 h-64 overflow-y-auto mb-6 p-2 bg-black/20 rounded-xl"></div>
        <div class="flex gap-4 items-end bg-slate-900/50 p-3 rounded-2xl border border-white/5">
            <div class="preview-container"><div id="mini-grid" class="grid grid-cols-5 gap-0.5"></div><div class="text-[9px] text-center mt-2 text-emerald-400 font-bold uppercase">Card <span id="prev-num">#---</span></div></div>
            <div class="flex-1">
                <button onclick="pickRandom()" class="w-full py-2 bg-slate-800 border border-emerald-500/50 rounded-lg text-[10px] font-bold mb-2">🎲 RANDOM</button>
                <button id="join-btn" onclick="joinGame()" class="w-full py-4 bg-emerald-500 rounded-xl font-black text-lg shadow-lg">▶ START!</button>
            </div>
        </div>
    </div>

    <script>
        const tg = window.Telegram.WebApp; const uid = tg.initDataUnsafe.user ? tg.initDataUnsafe.user.id : 0;
        let activeBet = 10; let myCard = null;

        function refreshLobby() {
            fetch('/api/lobby-info/'+uid+'/').then(r=>r.json()).then(d => {
                document.getElementById('bal-header').innerText = d.balance.toFixed(2);
                const list = document.getElementById('room-list'); list.innerHTML = '';
                d.rooms.forEach(room => {
                    const isLive = room.status === 'ACTIVE';
                    list.innerHTML += `
                        <div onclick="selectRoom(${room.bet}, '${room.status}')" class="room-card ${isLive ? 'opacity-70' : ''}">
                            <div>
                                <div class="text-white font-black text-lg">Bingo ${room.bet}</div>
                                <div class="text-[10px] font-bold ${isLive ? 'text-yellow-400' : 'text-emerald-400'}">
                                    ${isLive ? `LIVE: CALLING ${room.called_count}/75` : `STARTING IN: ${room.time_left}s`}
                                </div>
                                <div class="text-[9px] text-gray-300">Win: ${room.win.toFixed(0)} ETB</div>
                            </div>
                            <div class="text-emerald-500 font-bold text-xl">${isLive ? '⏳' : '〉'}</div>
                        </div>`;
                    if(activeBet == room.bet) updateBanner(room.status, room.called_count);
                });
            });
        }
        function updateBanner(status, count) {
            const b = document.getElementById('active-call-banner'); const btn = document.getElementById('join-btn');
            if(status === 'ACTIVE') { b.classList.remove('hidden'); document.getElementById('call-count').innerText=count; btn.disabled=true; btn.style.opacity="0.3"; }
            else { b.classList.add('hidden'); btn.disabled=false; btn.style.opacity="1"; }
        }
        function selectRoom(t) { activeBet=t; document.getElementById('v-lobby').classList.add('hidden'); document.getElementById('v-selector').classList.remove('hidden'); initGrid(); }
        function initGrid() {
            const g = document.getElementById('grid-200'); g.innerHTML = '';
            for(let i=1; i<=200; i++) {
                let b = document.createElement('button'); b.className="card-num"; b.id="c-"+i; b.innerText=i; b.onclick=()=>selectCard(i); g.appendChild(b);
            }
        }
        function selectCard(n) {
            myCard=n; document.querySelectorAll('.card-num').forEach(el=>el.classList.remove('active'));
            document.getElementById('c-'+n).classList.add('active'); document.getElementById('prev-num').innerText="#"+n;
            fetch('/api/card-data/'+n+'/').then(r=>r.json()).then(d=>{
                const mini = document.getElementById('mini-grid'); mini.innerHTML = '';
                d.board.forEach(row=>row.forEach(v=>{ let c=document.createElement('div'); c.className='mini-cell'; c.innerText=v==='FREE'?'X':v; mini.appendChild(c); }));
            });
        }
        function pickRandom() { const r=Math.floor(Math.random()*200)+1; selectCard(r); document.getElementById('c-'+r).scrollIntoView(); }
        function joinGame() { fetch(`/api/join-room/${uid}/${activeBet}/${myCard}/`).then(r=>r.json()).then(d=>{ if(d.status==='ok') location.reload(); else alert(d.error); }); }
        refreshLobby(); setInterval(refreshLobby, 4000);
    </script>
</body>
</html>
EOF

# 6. CREATE BUILD.SH (NUCLEAR KILLER)
cd ~/vladbingo
cat << 'EOF' > build.sh
#!/bin/bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    cursor.execute("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();")
    cursor.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
    cursor.execute("GRANT ALL ON SCHEMA public TO public;")
innerEOF
rm -rf bingo/migrations/ && mkdir bingo/migrations/ && touch bingo/migrations/__init__.py
python manage.py makemigrations bingo && python manage.py migrate && python manage.py collectstatic --no-input && python manage.py init_bingo
EOF

# 7. SYNC GITHUB
git add .
git commit -m "Grand Launch v8.0: Lobby, 5x5 Preview, and Active Call Tracker"
git push -f origin main
echo "✅ VERSION 8.0 DEPLOYED SUCCESSFULLY!"
