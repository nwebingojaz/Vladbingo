#!/bin/bash
echo "🎮 FIXING SORT ORDER & ADDING LIVE PLAY HALL..."

cd ~/vladbingo/backend

# 1. FIX VIEWS.PY (Add order_by to rooms)
cat << 'INNER' > bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound, Transaction
from django.utils import timezone
from decimal import Decimal

def home(request): return HttpResponse("<h1>VLAD BINGO ENGINE ACTIVE</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_card_data(request, num):
    try:
        card = PermanentCard.objects.get(card_number=num)
        return JsonResponse({"board": card.board})
    except: return JsonResponse({"error": "not found"}, status=404)

def lobby_info(request, tg_id):
    user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
    # FIX: order_by('bet_amount') guarantees 10, 20, 30, 40... order!
    rooms = GameRound.objects.exclude(status="ENDED").order_by('bet_amount').values('id', 'bet_amount', 'players', 'created_at', 'status', 'called_numbers')
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

def get_history(request, tg_id):
    recent_winners = GameRound.objects.filter(status="ENDED").order_by('-id')[:15]
    winners_data = [{'game_id': g.id, 'winner': g.winner_username or "None", 'called': f"{len(g.called_numbers)}/75", 'prize': float(g.winner_prize)} for g in recent_winners]
    my_games = GameRound.objects.filter(players__has_key=str(tg_id)).order_by('-id')[:15]
    my_bets_data = []
    for g in my_games:
        won = (g.winner_username == f"tg_{tg_id}")
        my_bets_data.append({
            'game_id': g.id, 'bet': float(g.bet_amount), 'card': g.players.get(str(tg_id)),
            'status': "WON" if won else "LOST", 'prize': float(g.winner_prize) if won else 0
        })
    return JsonResponse({'winners': winners_data, 'my_bets': my_bets_data})

def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    if user.operational_credit < Decimal(str(bet)): return JsonResponse({'status': 'error', 'error': 'Low Balance'})
    game = GameRound.objects.filter(status="LOBBY", bet_amount=bet).first()
    if not game: return JsonResponse({'status': 'error', 'error': 'No Lobby'})
    game.players[str(tg_id)] = card_num
    game.save(); user.operational_credit -= Decimal(str(bet)); user.save()
    return JsonResponse({'status': 'ok'})

def get_game_info(request, game_id, tg_id):
    try:
        game = GameRound.objects.get(id=game_id)
        card_num = game.players.get(str(tg_id), 1)
        card = PermanentCard.objects.get(card_number=card_num)
        prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
        return JsonResponse({'board': card.board, 'called': game.called_numbers, 'prize': float(prize), 'status': game.status})
    except: return JsonResponse({'error': 'not found'}, status=404)

def check_win(request, game_id, tg_id):
    user = User.objects.get(username=f"tg_{tg_id}")
    game = GameRound.objects.get(id=game_id)
    if game.status != "ACTIVE": return JsonResponse({'status': 'WAITING'})
    card_num = game.players.get(str(tg_id)); card = PermanentCard.objects.get(card_number=card_num)
    called_set = set(game.called_numbers); board = card.board; lines = 0
    for r in range(5):
        if all(board[r][c] == "FREE" or board[r][c] in called_set for c in range(5)): lines += 1
        if all(board[c][r] == "FREE" or board[c][r] in called_set for r in range(5)): lines += 1
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
INNER

# 2. ADD THE "PLAY HALL" TO HTML
cat << 'INNER' > bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>VLAD BINGO PRO</title>
    <script src="https://telegram.org/js/telegram-web-app.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #0f172a; color: white; font-family: sans-serif; overflow: hidden; }
        .header-bg { background: #0b0f19; border-bottom: 2px solid #3b82f6; }
        .room-card { background: #1e293b; border-radius: 12px; padding: 15px; margin-bottom: 10px; border-left: 4px solid #3b82f6; box-shadow: 0 4px 6px rgba(0,0,0,0.3); }
        .room-card.live { border-left-color: #ef4444; opacity: 0.8; }
        .active-banner { background: #0b0f19; border: 2px solid #ef4444; color: #ef4444; border-radius: 8px; padding: 6px; text-align: center; font-weight: 900; margin-bottom: 10px; animation: pulse 2s infinite; }
        .card-num { height: 32px; background: #1e293b; border: 1px solid #3b82f6; border-radius: 4px; font-size: 0.65rem; font-weight: bold; color: #93c5fd; }
        .card-num.active { background: #3b82f6 !important; color: white; border-color: white; transform: scale(1.1); box-shadow: 0 0 10px #3b82f6; }
        .preview-container { border: 2px solid #3b82f6; border-radius: 12px; padding: 10px; background: rgba(0,0,0,0.4); width: 135px; }
        .mini-cell { aspect-ratio: 1/1; display: flex; align-items: center; justify-content: center; font-size: 0.6rem; border: 0.1px solid #1e3a8a; color: #93c5fd;}
        .btn-start { background: linear-gradient(135deg, #ef4444, #dc2626); border-radius: 12px; padding: 15px; font-weight: 900; font-size: 1.1rem; width: 100%; box-shadow: 0 4px 15px rgba(239, 68, 68, 0.4); color: white; }
        .btn-start:active { transform: scale(0.95); }
        .btn-random { background: #1e293b; border: 1px solid #3b82f6; border-radius: 12px; width: 100%; padding: 10px; font-size: 0.8rem; font-weight: bold; color: #3b82f6; margin-bottom: 8px; }
        .btn-deposit { background: #3b82f6; color: white; padding: 4px 12px; border-radius: 20px; font-weight: 900; font-size: 10px; }
        .modal { background: rgba(0,0,0,0.95); position: fixed; inset: 0; z-index: 100; padding: 20px; display: none; flex-direction: column;}
        .history-row { background: #1e293b; margin-bottom: 4px; padding: 10px; border-radius: 6px; font-size: 10px; display: flex; justify-content: space-between; }
        .tab-btn { flex: 1; text-align: center; padding: 10px; font-weight: bold; border-bottom: 2px solid transparent; color: gray; }
        .tab-btn.active { border-bottom-color: #3b82f6; color: #3b82f6; }
        @keyframes pulse { 0% { opacity: 1; } 50% { opacity: 0.6; } 100% { opacity: 1; } }
    </style>
</head>
<body class="antialiased select-none">
    <!-- HEADER -->
    <div class="header-bg p-3 flex justify-between items-center shadow-lg">
        <div class="flex items-center gap-2"><div class="bg-blue-600 p-1 rounded font-black text-[10px] text-white italic">VLAD</div><div class="font-black text-xs uppercase text-white">BINGO PRO</div></div>
        <div class="flex items-center gap-2">
            <div class="bg-slate-800 px-3 py-1 rounded-full flex items-center gap-2"><span class="text-yellow-400">👛</span><span id="bal-header" class="font-bold text-xs">0.00</span></div>
            <button onclick="handleDeposit()" class="btn-deposit">+ DEPOSIT</button>
        </div>
    </div>
    
    <!-- SUB-NAV -->
    <div class="bg-slate-900/80 p-2 flex justify-around items-center text-[9px] font-bold text-blue-400 uppercase border-b border-blue-900/50">
        <div>🎲 Room: <span id="nav-room" class="text-white">10</span></div>
        <div>🎁 Win: <span id="nav-prize" class="text-white text-[11px]">0</span></div>
        <div onclick="openHistory()">📜 History</div>
        <div onclick="location.reload()">🔄 Refresh</div>
    </div>
    
    <!-- TIMER -->
    <div id="timer-bar" class="bg-black/60 p-1 text-center border-b border-white/5">
        <span class="text-[10px] text-blue-400 font-bold uppercase">Lobby Closes: </span>
        <span id="timer" class="text-[10px] font-mono font-black text-white ml-1">00:00</span>
    </div>
    
    <!-- LOBBY VIEW -->
    <div id="v-lobby" class="p-4 h-screen overflow-y-auto pb-32">
        <div id="room-list"></div>
    </div>

    <!-- SELECTOR VIEW -->
    <div id="v-selector" class="hidden p-4">
        <button onclick="showLobby()" class="text-blue-400 text-[10px] font-bold mb-3 flex items-center gap-1">← BACK TO ROOMS</button>
        <div id="active-call-banner" class="active-banner hidden">Active Game Call <span id="call-count">0</span>/75</div>
        <div id="grid-200" class="grid grid-cols-10 gap-1 h-64 overflow-y-auto mb-6 p-2 bg-black/30 rounded-xl"></div>
        <div class="flex gap-4 items-end bg-slate-800/50 p-3 rounded-2xl border border-white/5">
            <div class="preview-container"><div id="mini-grid" class="grid grid-cols-5 gap-0.5"></div><div class="text-[9px] text-center mt-2 text-blue-400 font-bold uppercase">Card <span id="prev-num">#---</span></div></div>
            <div class="flex-1">
                <button onclick="pickRandom()" class="btn-random">🎲 RANDOM</button>
                <button id="join-btn" onclick="joinGame()" class="btn-start">▶ START!</button>
            </div>
        </div>
    </div>

    <!-- LIVE PLAY HALL (NEW!) -->
    <div id="v-play" class="hidden p-4 h-screen overflow-y-auto pb-32">
        <div class="flex justify-between items-center mb-3">
            <h2 class="text-blue-400 font-bold text-xs uppercase tracking-widest">My Board</h2>
            <div id="play-status-badge" class="text-[10px] bg-blue-500/20 border border-blue-500 text-blue-500 px-3 py-1 rounded-full font-black">WAITING...</div>
        </div>
        <!-- 1-75 TRACKER -->
        <div id="play-tracker" class="grid grid-cols-10 gap-1 mb-6 p-3 bg-slate-900/80 rounded-2xl border border-blue-900/50"></div>
        <!-- 5x5 CARD -->
        <div class="flex justify-center mb-6">
            <div id="play-card" class="grid grid-cols-5 gap-1 bg-slate-800 p-2 rounded-2xl border-2 border-blue-500 shadow-[0_0_20px_rgba(59,130,246,0.3)]"></div>
        </div>
        <!-- BINGO BUTTON -->
        <button onclick="hitBingo()" class="w-full py-5 bg-gradient-to-r from-yellow-400 to-yellow-600 rounded-2xl font-black text-2xl shadow-[0_0_20px_rgba(250,204,21,0.4)] text-black active:scale-95 transition-all tracking-widest">📢 BINGO!</button>
    </div>

    <!-- HISTORY MODAL -->
    <div id="m-history" class="modal">
        <div class="flex justify-between items-center mb-2">
            <h2 class="text-blue-400 font-black italic uppercase text-lg">My Bets History</h2>
            <button onclick="closeHistory()" class="text-2xl text-gray-400">✕</button>
        </div>
        <div class="flex mb-4">
            <div id="tab-bets" onclick="switchTab('bets')" class="tab-btn active">My Bets</div>
            <div id="tab-win" onclick="switchTab('win')" class="tab-btn">All Winners</div>
        </div>
        <div id="history-content" class="h-full overflow-y-auto pb-20"></div>
    </div>

    <script>
        const tg = window.Telegram.WebApp; const uid = tg.initDataUnsafe.user ? tg.initDataUnsafe.user.id : 0;
        let activeBet = 10; let myCard = null; let historyData = {winners: [], my_bets: []};
        let currentRoomTime = 0; let currentRoomStatus = 'LOBBY'; let myActiveGameId = null;

        function handleDeposit() { tg.showAlert("Redirecting to secure Chapa Payment Gateway..."); }

        function appLoop() {
            if (myActiveGameId) { updatePlayHall(); } else { refreshLobby(); }
        }

        function refreshLobby() {
            fetch('/api/lobby-info/'+uid+'/').then(r=>r.json()).then(d => {
                document.getElementById('bal-header').innerText = d.balance.toFixed(2);
                
                // IF JOINED A GAME -> JUMP TO PLAY HALL
                if(d.active_game_id) {
                    myActiveGameId = d.active_game_id;
                    document.getElementById('v-lobby').classList.add('hidden');
                    document.getElementById('v-selector').classList.add('hidden');
                    document.getElementById('timer-bar').classList.add('hidden');
                    document.getElementById('v-play').classList.remove('hidden');
                    updatePlayHall();
                    return;
                }

                // OTHERWISE RENDER LOBBY
                const list = document.getElementById('room-list'); list.innerHTML = '';
                // Guarantee Sort by Bet Amount
                d.rooms.sort((a,b) => a.bet - b.bet);
                d.rooms.forEach(room => {
                    const isLive = room.status === 'ACTIVE';
                    list.innerHTML += `
                        <div onclick="selectRoom(${room.bet})" class="room-card ${isLive ? 'live' : ''} cursor-pointer">
                            <div class="flex justify-between w-full">
                                <div>
                                    <div class="text-white font-black text-xl">Bingo ${room.bet}</div>
                                    <div class="text-[11px] font-bold ${isLive ? 'text-red-400' : 'text-blue-400'} mt-1">
                                        ${isLive ? 'LIVE: CALLING ' + room.called_count + '/75' : 'STARTING IN: ' + room.time_left + 's'}
                                    </div>
                                    <div class="text-[10px] text-gray-400 mt-1">Win: <span class="text-white font-bold">${room.win.toFixed(0)} ETB</span></div>
                                </div>
                                <div class="flex flex-col items-end justify-center">
                                    <div class="${isLive ? 'text-red-500' : 'text-blue-500'} font-bold text-2xl">${isLive ? '⏳' : '▶'}</div>
                                    <div class="text-[9px] text-gray-500 mt-2">${room.players} Players</div>
                                </div>
                            </div>
                        </div>`;
                    
                    if(activeBet == room.bet) {
                        currentRoomTime = room.time_left; currentRoomStatus = room.status;
                        document.getElementById('nav-prize').innerText = room.win.toFixed(0);
                        updateBanner(room.status, room.called_count);
                    }
                });
            });
        }

        // PLAY HALL LOGIC
        function updatePlayHall() {
            if(!myActiveGameId) return;
            fetch(`/api/game-info/${myActiveGameId}/${uid}/`).then(r=>r.json()).then(d => {
                if(d.status === 'ENDED') { tg.showAlert("Game Over! Check History."); location.reload(); return; }
                
                document.getElementById('nav-prize').innerText = d.prize.toFixed(0);
                const badge = document.getElementById('play-status-badge');
                if(d.status === 'ACTIVE') {
                    badge.innerText = "LIVE: " + d.called.length + "/75";
                    badge.className = "text-[10px] bg-red-500/20 border border-red-500 text-red-500 px-3 py-1 rounded-full font-black animate-pulse";
                }

                const tracker = document.getElementById('play-tracker');
                if(tracker.children.length === 0) {
                    for(let i=1; i<=75; i++) {
                        let dot = document.createElement('div'); dot.id = 'dot-'+i;
                        dot.className = "text-[7px] font-bold text-center py-1 rounded bg-slate-800 text-gray-500";
                        dot.innerText = i; tracker.appendChild(dot);
                    }
                }
                d.called.forEach(num => {
                    const dot = document.getElementById('dot-'+num);
                    if(dot && !dot.classList.contains('bg-red-500')) dot.className = "text-[7px] font-bold text-center py-1 rounded bg-red-500 text-white scale-110";
                });

                const pc = document.getElementById('play-card'); pc.innerHTML = '';
                d.board.forEach(row => row.forEach(val => {
                    let cell = document.createElement('div');
                    cell.className = 'w-12 h-12 flex items-center justify-center text-lg font-black rounded-lg border border-blue-900/50 bg-slate-900 shadow-inner';
                    if (val === 'FREE') { cell.innerText = '⭐'; cell.classList.add('bg-blue-600', 'text-white'); } 
                    else {
                        cell.innerText = val;
                        if (d.called.includes(val)) cell.classList.add('bg-red-500', 'text-white', 'border-red-400');
                        else cell.classList.add('text-blue-200');
                    }
                    pc.appendChild(cell);
                }));
            });
        }

        function hitBingo() {
            fetch(`/api/check-win/${myActiveGameId}/${uid}/`).then(r=>r.json()).then(d => {
                if (d.status === 'WINNER') { tg.showAlert(`🎉 BINGO! YOU WON ${d.prize} ETB!`); location.reload(); } 
                else if (d.status === 'NOT_YET') { tg.showScanQrPopup({text: "Lines not completed yet!"}); setTimeout(() => tg.closeScanQrPopup(), 1500); } 
                else { tg.showAlert("Waiting for numbers to be drawn."); }
            });
        }

        setInterval(() => {
            if(!myActiveGameId) {
                const tEl = document.getElementById('timer');
                if(currentRoomStatus === 'ACTIVE') { tEl.innerText = "PLAYING..."; tEl.classList.add('text-red-400'); } 
                else {
                    tEl.classList.remove('text-red-400');
                    if(currentRoomTime > 0) currentRoomTime--;
                    let m = Math.floor(currentRoomTime / 60), s = currentRoomTime % 60;
                    tEl.innerText = m + ":" + (s < 10 ? "0" + s : s);
                }
            }
        }, 1000);

        function updateBanner(status, count) {
            const b = document.getElementById('active-call-banner'); const btn = document.getElementById('join-btn');
            if(status === 'ACTIVE') { b.classList.remove('hidden'); document.getElementById('call-count').innerText=count; btn.disabled=true; btn.style.opacity="0.3"; btn.innerText="WAITING...";}
            else { b.classList.add('hidden'); btn.disabled=false; btn.style.opacity="1"; btn.innerText="▶ START!";}
        }
        
        function showLobby() { document.getElementById('v-selector').classList.add('hidden'); document.getElementById('v-lobby').classList.remove('hidden'); }
        function selectRoom(t) { activeBet=t; document.getElementById('nav-room').innerText=t; document.getElementById('v-lobby').classList.add('hidden'); document.getElementById('v-selector').classList.remove('hidden'); initGrid(); appLoop(); }
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
            document.getElementById('c-'+n).scrollIntoView({behavior:'smooth', block:'center'});
        }
        function pickRandom() { const r=Math.floor(Math.random()*200)+1; selectCard(r); }
        function joinGame() { fetch(`/api/join-room/${uid}/${activeBet}/${myCard}/`).then(r=>r.json()).then(d=>{ if(d.status==='ok') location.reload(); else tg.showAlert(d.error); }); }

        function openHistory() { document.getElementById('m-history').style.display = 'flex'; fetch('/api/history/'+uid+'/').then(r=>r.json()).then(d => { historyData = d; switchTab('bets'); }); }
        function closeHistory() { document.getElementById('m-history').style.display = 'none'; }
        function switchTab(tab) {
            document.getElementById('tab-bets').className = "tab-btn " + (tab==='bets' ? 'active' : ''); document.getElementById('tab-win').className = "tab-btn " + (tab==='win' ? 'active' : '');
            const content = document.getElementById('history-content'); content.innerHTML = '';
            if(tab === 'bets') {
                if(historyData.my_bets.length===0) content.innerHTML="<div class='text-center text-gray-500 mt-10'>No bets yet.</div>";
                historyData.my_bets.forEach(h => { content.innerHTML += `<div class="history-row border-l-2 ${h.status==='WON' ? 'border-green-500' : 'border-red-500'}"><div><div class="text-gray-400">Game</div><div class="font-bold">#${h.game_id}</div></div><div><div class="text-gray-400">Bet/Card</div><div class="text-blue-400">${h.bet}/#${h.card}</div></div><div class="text-right"><div class="text-gray-400">Result</div><div class="font-black ${h.status==='WON' ? 'text-green-500' : 'text-red-500'}">${h.status==='WON' ? '+'+h.prize : '-'+h.bet}</div></div></div>`; });
            } else {
                historyData.winners.forEach(h => { content.innerHTML += `<div class="history-row"><div><div class="text-gray-400">Game</div><div class="font-bold">#${h.game_id}</div></div><div><div class="text-gray-400">Winner</div><div class="text-blue-400">@${h.winner}</div></div><div class="text-right"><div class="text-gray-400">Prize</div><div class="text-green-400 font-black">${h.prize} ETB</div></div></div>`; });
            }
        }
        
        appLoop(); setInterval(appLoop, 2000); // 2 second sync for faster ball drops
    </script>
</body>
</html>
INNER

git add .
git commit -m "UI: Fixed Lobby Sorting and Added Live Play Hall"
git push -f origin main
echo "✅ PLAY HALL DEPLOYED! Watch Render update."
