#!/bin/bash
# VLAD BINGO - COMPACT CASINO (FIXED NAVIGATION + SMALL BUTTONS)

# 1. MINI APP UI (Ultra-Compressed)
cat <<'EOF' > backend/bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>VladBingo Pro</title>
    <script src="https://telegram.org/js/telegram-web-app.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #0b1220; color: white; font-family: sans-serif; overflow-x: hidden; }
        /* Room Buttons */
        .tier-card { border-radius: 12px; padding: 15px; display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; cursor: pointer; transition: 0.2s; border: 2px solid #1f2937; background: #111827; }
        .tier-enabled { background: linear-gradient(135deg, #065f46, #059669); border-color: #10b981; }
        /* Compact Card Selector (10 columns) */
        .card-btn { background: #1e293b; border: 1px solid #334155; border-radius: 4px; height: 30px; font-size: 0.7rem; font-weight: bold; transition: 0.1s; }
        .card-mine { background: #10b981 !important; border-color: #34d399; color: white; transform: scale(1.1); }
        /* Game Hall Styles */
        .num-dot { width: 14px; height: 14px; border-radius: 50%; background: #1e293b; font-size: 0.5rem; display: flex; align-items: center; justify-content: center; border: 1px solid #334155; }
        .called { background: #fbbf24 !important; color: black !important; box-shadow: 0 0 8px #fbbf24; }
        .card-cell { background: #1e293b; aspect-ratio: 1/1; display: flex; align-items: center; justify-content: center; font-weight: bold; font-size: 1rem; border-radius: 6px; border: 1px solid #334155; }
        .marked { background: #10b981 !important; }
        .view-hidden { display: none; }
    </style>
</head>
<body class="p-3">
    <!-- BAL BAR -->
    <div class="flex justify-between items-center mb-4 bg-slate-800/50 p-2 rounded-xl border border-slate-700">
        <div class="text-sm font-bold text-emerald-400">💰 <span id="header-bal">0.00</span> ETB</div>
        <button onclick="location.reload()" class="text-[9px] bg-slate-700 px-2 py-1 rounded font-bold">REFRESH 🔄</button>
    </div>

    <!-- VIEW 1: LOBBY -->
    <div id="view-lobby">
        <h2 class="text-[10px] font-bold text-gray-500 uppercase mb-3 tracking-widest">Select Room</h2>
        <div id="room-list"></div>
    </div>

    <!-- VIEW 2: SELECTOR (COMPRESSED 10 COLS) -->
    <div id="view-selector" class="view-hidden">
        <h2 class="text-center text-xs font-bold mb-3 uppercase text-gray-400">Choose a Card (1-200)</h2>
        <div id="selector-grid" class="grid grid-cols-10 gap-1 h-80 overflow-y-auto bg-slate-900/50 p-2 rounded-xl border border-slate-800 mb-4"></div>
        <div class="flex gap-2">
            <button onclick="showLobby()" class="flex-1 py-3 bg-slate-800 rounded-xl font-bold text-sm">CANCEL</button>
            <button id="start-btn" class="flex-1 py-3 bg-emerald-600 rounded-xl font-bold text-sm">START! ▶</button>
        </div>
    </div>

    <!-- VIEW 3: GAME HALL -->
    <div id="view-hall" class="view-hidden">
        <div class="bg-slate-800 p-3 rounded-xl border border-slate-700 mb-3 flex justify-between items-center">
            <div>
                <div class="text-[8px] text-gray-400 font-bold uppercase">Prize Pool</div>
                <div class="text-xl font-black text-emerald-400"><span id="prize">0</span> ETB</div>
            </div>
            <div id="game-status" class="text-[10px] font-bold text-yellow-500 animate-pulse">LOBBY</div>
        </div>
        <div id="tracker" class="grid grid-cols-1 gap-1 mb-4 p-2 bg-slate-950 rounded-lg border border-slate-900"></div>
        <div id="user-card" class="grid grid-cols-5 gap-1 bg-slate-800 p-2 rounded-xl border-2 border-slate-700 shadow-2xl mb-4"></div>
        <button id="bingo-btn" class="w-full py-4 bg-yellow-500 text-black font-black text-lg rounded-xl shadow-lg">BINGO! 📢</button>
    </div>

    <script>
        const tg = window.Telegram.WebApp; const uid = tg.initDataUnsafe.user ? tg.initDataUnsafe.user.id : 0;
        let activeBet = 0; let myCard = null;

        function showLobby() { document.getElementById('view-lobby').classList.remove('view-hidden'); document.getElementById('view-selector').classList.add('view-hidden'); }
        function showSelector(amt) { activeBet = amt; document.getElementById('view-lobby').classList.add('view-hidden'); document.getElementById('view-selector').classList.remove('view-hidden'); renderSelector(); }
        function showHall() { document.getElementById('view-lobby').classList.add('view-hidden'); document.getElementById('view-selector').classList.add('view-hidden'); document.getElementById('view-hall').classList.remove('view-hidden'); }

        function renderSelector() {
            const g = document.getElementById('selector-grid'); g.innerHTML = '';
            for(let i=1; i<=200; i++) {
                let b = document.createElement('button'); b.className = "card-btn"; b.innerText = i;
                b.onclick = () => { myCard = i; Array.from(g.children).forEach(c=>c.classList.remove('card-mine')); b.classList.add('card-mine'); };
                g.appendChild(b);
            }
        }

        function init() {
            fetch('/api/lobby-info/' + uid + '/').then(r=>r.json()).then(d => {
                document.getElementById('header-bal').innerText = d.balance.toFixed(2);
                const list = document.getElementById('room-list'); list.innerHTML = '';
                [10, 20, 40, 50, 100].forEach(amt => {
                    let active = d.balance >= amt;
                    list.innerHTML += `<div onclick="showSelector(${amt})" class="tier-card ${active ? 'tier-enabled' : ''}"><div class="font-black text-lg">BINGO ${amt}</div><div class="text-[9px] font-bold uppercase">WIN ~${amt*4}</div></div>`;
                });
                if(d.active_game) { showHall(); loadHall(d.active_game); }
            });
        }

        document.getElementById('start-btn').onclick = () => {
            if(!myCard) return alert("Select a card!");
            fetch(`/api/join-room/${uid}/${activeBet}/${myCard}/`).then(r=>r.json()).then(d => {
                if(d.status === 'ok') { showHall(); loadHall(d.game_id); } else alert(d.error);
            });
        };

        function loadHall(gid) {
            const tr = document.getElementById('tracker'); tr.innerHTML = '';
            ['B','I','N','G','O'].forEach((l, idx) => {
                let h = `<div class="flex gap-1 items-center"><div class="text-yellow-500 font-bold w-4 text-[7px]">${l}</div>`;
                for(let i=(idx*15)+1; i<=(idx*15)+15; i++) h += `<div id="t-${i}" class="num-dot">${i}</div>`;
                tr.innerHTML += h + '</div>';
            });
            fetch(`/api/game-info/${gid}/${uid}/`).then(r=>r.json()).then(d => {
                document.getElementById('prize').innerText = d.prize;
                if(d.status === 'ACTIVE') document.getElementById('game-status').innerText = '● LIVE';
                document.getElementById('user-card').innerHTML = '';
                d.board.forEach(row => row.forEach(val => {
                    const c = document.createElement('div'); c.className = 'card-cell'; c.innerText = val === 'FREE' ? '★' : val;
                    if(val === 'FREE') c.classList.add('marked'); c.onclick = () => c.classList.toggle('marked');
                    document.getElementById('user-card').appendChild(c);
                }));
                d.called_numbers.forEach(n => { if(document.getElementById('t-'+n)) document.getElementById('t-'+n).classList.add('called'); });
            });
        }

        init();
    </script>
</body>
</html>
EOF

# 2. UPDATE JOIN_ROOM VIEW (Return Game ID)
sed -i "s/return JsonResponse({'status': 'ok'})/return JsonResponse({'status': 'ok', 'game_id': game.id})/g" backend/bingo/views.py

echo "✅ UI Compressed & Navigation Fixed!"
