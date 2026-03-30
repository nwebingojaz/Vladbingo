#!/bin/bash
echo "🎁 ADDING PRIZE TRACKER & SMOOTH TIMER..."

cd ~/vladbingo/backend

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
    
    <!-- SUB-NAV WITH PRIZE (GIFT BOX) -->
    <div class="bg-slate-900/80 p-2 flex justify-around items-center text-[9px] font-bold text-blue-400 uppercase border-b border-blue-900/50">
        <div>🎲 Room: <span id="nav-room" class="text-white">10</span></div>
        <div>🎁 Win: <span id="nav-prize" class="text-white text-[11px]">0</span></div>
        <div onclick="openHistory()">📜 History</div>
        <div onclick="location.reload()">🔄 Refresh</div>
    </div>
    
    <!-- TIMER -->
    <div class="bg-black/60 p-1 text-center border-b border-white/5">
        <span class="text-[10px] text-blue-400 font-bold uppercase">Lobby Closes: </span>
        <span id="timer" class="text-[10px] font-mono font-black text-white ml-1">00:00</span>
    </div>
    
    <!-- LOBBY -->
    <div id="v-lobby" class="p-4 h-screen overflow-y-auto pb-32">
        <div id="room-list"></div>
    </div>

    <!-- SELECTOR -->
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
        let currentRoomTime = 0; let currentRoomStatus = 'LOBBY';

        function handleDeposit() { tg.showAlert("Redirecting to secure Chapa Payment Gateway..."); }

        function refreshLobby() {
            fetch('/api/lobby-info/'+uid+'/').then(r=>r.json()).then(d => {
                document.getElementById('bal-header').innerText = d.balance.toFixed(2);
                const list = document.getElementById('room-list'); list.innerHTML = '';
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
                    
                    // SYNC DATA FOR THE ACTIVE ROOM VIEW
                    if(activeBet == room.bet) {
                        currentRoomTime = room.time_left;
                        currentRoomStatus = room.status;
                        document.getElementById('nav-prize').innerText = room.win.toFixed(0);
                        updateBanner(room.status, room.called_count);
                    }
                });
            });
        }

        // SMOOTH LOCAL TIMER (Ticks every 1 second without waiting for network)
        setInterval(() => {
            const tEl = document.getElementById('timer');
            if(currentRoomStatus === 'ACTIVE') {
                tEl.innerText = "PLAYING...";
                tEl.classList.add('text-red-400');
            } else {
                tEl.classList.remove('text-red-400');
                if(currentRoomTime > 0) currentRoomTime--;
                let m = Math.floor(currentRoomTime / 60);
                let s = currentRoomTime % 60;
                tEl.innerText = m + ":" + (s < 10 ? "0" + s : s);
            }
        }, 1000);

        function updateBanner(status, count) {
            const b = document.getElementById('active-call-banner'); const btn = document.getElementById('join-btn');
            if(status === 'ACTIVE') { b.classList.remove('hidden'); document.getElementById('call-count').innerText=count; btn.disabled=true; btn.style.opacity="0.3"; btn.innerText="WAITING...";}
            else { b.classList.add('hidden'); btn.disabled=false; btn.style.opacity="1"; btn.innerText="▶ START!";}
        }
        
        function showLobby() { document.getElementById('v-selector').classList.add('hidden'); document.getElementById('v-lobby').classList.remove('hidden'); }
        
        function selectRoom(t) { 
            activeBet=t; document.getElementById('nav-room').innerText=t; 
            document.getElementById('v-lobby').classList.add('hidden'); 
            document.getElementById('v-selector').classList.remove('hidden'); 
            initGrid(); refreshLobby(); 
        }
        
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
            document.getElementById('tab-bets').className = "tab-btn " + (tab==='bets' ? 'active' : '');
            document.getElementById('tab-win').className = "tab-btn " + (tab==='win' ? 'active' : '');
            const content = document.getElementById('history-content'); content.innerHTML = '';
            if(tab === 'bets') {
                if(historyData.my_bets.length===0) content.innerHTML="<div class='text-center text-gray-500 mt-10'>No bets yet.</div>";
                historyData.my_bets.forEach(h => {
                    content.innerHTML += `<div class="history-row border-l-2 ${h.status==='WON' ? 'border-green-500' : 'border-red-500'}">
                        <div><div class="text-gray-400">Game</div><div class="font-bold">#${h.game_id}</div></div>
                        <div><div class="text-gray-400">Bet/Card</div><div class="text-blue-400">${h.bet}/#${h.card}</div></div>
                        <div class="text-right"><div class="text-gray-400">Result</div><div class="font-black ${h.status==='WON' ? 'text-green-500' : 'text-red-500'}">${h.status==='WON' ? '+'+h.prize : '-'+h.bet}</div></div>
                    </div>`;
                });
            } else {
                historyData.winners.forEach(h => {
                    content.innerHTML += `<div class="history-row">
                        <div><div class="text-gray-400">Game</div><div class="font-bold">#${h.game_id}</div></div>
                        <div><div class="text-gray-400">Winner</div><div class="text-blue-400">@${h.winner}</div></div>
                        <div class="text-right"><div class="text-gray-400">Prize</div><div class="text-green-400 font-black">${h.prize} ETB</div></div>
                    </div>`;
                });
            }
        }
        
        refreshLobby(); setInterval(refreshLobby, 3000); // Network sync every 3s
    </script>
</body>
</html>
INNER

git add .
git commit -m "UI: Added Prize Tracker (Gift Box) and fixed smooth timer ticking"
git push -f origin main
echo "✅ PRIZE TRACKER AND SMOOTH TIMER DEPLOYED!"
