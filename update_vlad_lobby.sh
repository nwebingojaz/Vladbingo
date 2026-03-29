#!/bin/bash
echo "🎭 ADDING DYNAMIC ROOM LIST & REAL-TIME PRIZES..."

cd ~/vladbingo/backend

# 1. Update lobby_info View to return all active rooms
cat << 'INNER' > bingo/views.py
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
    # Get all active lobbies
    rooms = GameRound.objects.filter(status="LOBBY").values('id', 'bet_amount', 'players')
    room_data = []
    for r in rooms:
        p_count = len(r['players'])
        room_data.append({
            'id': r['id'],
            'bet': float(r['bet_amount']),
            'players': p_count,
            'win': float(r['bet_amount'] * p_count) * 0.8
        })
    
    # Check if user is already IN a game
    active_game = GameRound.objects.filter(players__has_key=str(tg_id)).exclude(status="ENDED").first()
    
    return JsonResponse({
        'balance': float(user.operational_credit), 
        'rooms': room_data,
        'active_game_id': active_game.id if active_game else None
    })

def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    if user.operational_credit < bet: return JsonResponse({'status': 'error', 'error': 'Low Balance'})
    game, _ = GameRound.objects.get_or_create(status="LOBBY", bet_amount=bet)
    game.players[str(tg_id)] = card_num
    game.save(); user.operational_credit -= Decimal(bet); user.save()
    return JsonResponse({'status': 'ok'})
INNER

# 2. Update HTML with Lobby View
cat << 'INNER' > bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>VLAD BINGO PRO</title>
    <script src="https://telegram.org/js/telegram-web-app.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #0b4d36; color: white; font-family: sans-serif; overflow: hidden; }
        .header-bg { background: #1e293b; border-bottom: 2px solid #10b981; }
        .room-card { background: #111827; border-radius: 12px; padding: 20px; margin-bottom: 12px; border-left: 5px solid #10b981; display: flex; justify-content: space-between; align-items: center; box-shadow: 0 4px 10px rgba(0,0,0,0.3); }
        .card-num { height: 32px; background: #1a3a32; border: 1px solid #2d5a4e; border-radius: 4px; font-size: 0.65rem; font-weight: bold; color: #4ade80; }
        .card-num.active { background: #10b981 !important; color: white; border-color: white; transform: scale(1.1); box-shadow: 0 0 15px rgba(16,185,129,0.5); }
        .preview-container { border: 2px solid #10b981; border-radius: 16px; padding: 12px; background: rgba(0,0,0,0.3); width: 145px; }
        .mini-cell { aspect-ratio: 1/1; display: flex; align-items: center; justify-content: center; font-size: 0.65rem; font-weight: bold; border: 0.1px solid #1c3d38; color: #4ade80; }
        .hidden { display: none; }
    </style>
</head>
<body class="antialiased select-none">
    <!-- HEADER -->
    <div class="header-bg p-3 flex justify-between items-center shadow-lg">
        <div class="flex items-center gap-2">
            <div class="bg-emerald-500 p-1 rounded font-black text-[10px] text-black italic uppercase">VLAD</div>
            <div class="font-black text-xs uppercase tracking-tighter">BINGO PRO</div>
        </div>
        <div class="bg-slate-800 px-3 py-1 rounded-full flex items-center gap-2">
            <span class="text-yellow-400">👛</span><span id="bal-header" class="font-bold text-xs">0.00</span>
        </div>
    </div>

    <!-- VIEW 1: LOBBY (ROOM LIST) -->
    <div id="v-lobby" class="p-4 h-screen overflow-y-auto">
        <h2 class="text-emerald-400 font-bold text-[10px] uppercase tracking-widest mb-4">Select Game Room</h2>
        <div id="room-list"></div>
    </div>

    <!-- VIEW 2: SELECTOR (GRID + PREVIEW) -->
    <div id="v-selector" class="hidden p-4">
        <div class="flex justify-between items-center mb-2">
            <button onclick="showLobby()" class="text-emerald-400 text-[10px] font-bold">← BACK TO ROOMS</button>
            <div class="text-[10px] font-bold text-white uppercase">Bingo <span id="sel-tier-label">10</span></div>
        </div>
        <div id="grid-200" class="grid grid-cols-10 gap-1 h-64 overflow-y-auto mb-6 p-2 bg-black/20 rounded-xl"></div>
        <div class="flex gap-4 items-end bg-slate-900/50 p-3 rounded-2xl border border-white/5">
            <div class="preview-container">
                <div id="mini-grid" class="grid grid-cols-5 gap-0.5"></div>
                <div class="text-[9px] text-center mt-2 text-emerald-400 font-bold uppercase">Card <span id="prev-num">#---</span></div>
            </div>
            <div class="flex-1">
                <button onclick="pickRandom()" class="w-full py-2 bg-slate-800 border border-emerald-500/50 rounded-lg text-[10px] font-bold mb-2">🎲 RANDOM</button>
                <button onclick="joinGame()" class="w-full py-4 bg-emerald-500 rounded-xl font-black text-lg shadow-lg active:scale-95 transition-all">▶ START!</button>
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
                    list.innerHTML += `
                        <div onclick="selectTier(${room.bet})" class="room-card">
                            <div>
                                <div class="text-emerald-400 font-black text-lg">Bingo ${room.bet}</div>
                                <div class="text-gray-400 text-xs mt-1">Win: <span class="text-white font-bold">${room.win.toFixed(0)} ETB</span></div>
                                <div class="text-[10px] bg-emerald-950 text-emerald-400 px-2 py-0.5 rounded-full inline-block mt-2">${room.players} Players Online</div>
                            </div>
                            <div class="text-emerald-500 text-xl font-bold">〉</div>
                        </div>`;
                });
            });
        }

        function selectTier(t) {
            activeBet = t;
            document.getElementById('sel-tier-label').innerText = t;
            document.getElementById('v-lobby').classList.add('hidden');
            document.getElementById('v-selector').classList.remove('hidden');
            initGrid();
        }

        function showLobby() {
            document.getElementById('v-selector').classList.add('hidden');
            document.getElementById('v-lobby').classList.remove('hidden');
        }

        function initGrid() {
            const g = document.getElementById('grid-200'); g.innerHTML = '';
            for(let i=1; i<=200; i++) {
                let b = document.createElement('button'); b.className="card-num"; b.id="c-"+i; b.innerText=i;
                b.onclick=()=> selectCard(i); g.appendChild(b);
            }
        }

        function selectCard(num) {
            myCard = num;
            document.querySelectorAll('.card-num').forEach(el=>el.classList.remove('active'));
            document.getElementById('c-'+num).classList.add('active');
            document.getElementById('prev-num').innerText = "#"+num;
            fetch('/api/card-data/'+num+'/').then(r=>r.json()).then(d => {
                const mini = document.getElementById('mini-grid'); mini.innerHTML = '';
                d.board.forEach(row => row.forEach(val => {
                    let c = document.createElement('div'); c.className = 'mini-cell';
                    c.innerText = val === 'FREE' ? 'X' : val; mini.appendChild(c);
                }));
            });
        }

        function pickRandom() {
            const r = Math.floor(Math.random()*200)+1; selectCard(r);
            document.getElementById('c-'+r).scrollIntoView({behavior:'smooth', block:'center'});
        }

        function joinGame() {
            if(!myCard) return alert("Select a card!");
            fetch(`/api/join-room/${uid}/${activeBet}/${myCard}/`).then(r=>r.json()).then(d => {
                if(d.status==='ok') alert("Joined!"); else alert(d.error);
            });
        }

        setInterval(refreshLobby, 3000);
        refreshLobby();
    </script>
</body>
</html>
INNER

# 3. Add more tiers to init_bingo
cat << 'INNER' > bingo/management/commands/init_bingo.py
import random
from django.core.management.base import BaseCommand
from bingo.models import PermanentCard, GameRound

class Command(BaseCommand):
    def handle(self, *args, **options):
        if not PermanentCard.objects.exists():
            for i in range(1, 201):
                board = [[random.randint(1,75) for _ in range(5)] for _ in range(5)]
                board[2][2] = "FREE"
                PermanentCard.objects.create(card_number=i, board=board)
        for t in [10, 20, 50, 100]:
            GameRound.objects.get_or_create(bet_amount=t, status="LOBBY")
INNER

git add .
git commit -m "Lobby: Added Dynamic Room List with live prize updates"
git push -f origin main
echo "✅ DYNAMIC ROOM SYSTEM DEPLOYED!"
