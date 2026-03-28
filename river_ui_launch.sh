#!/bin/bash
# VLAD BINGO - RIVER OF NUMBERS UI (NEXT-LUDO CLONE)

# 1. Update the Mini App (The Full UI Rewrite)
cat <<'EOF' > backend/bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>VladBingo Pro</title>
    <script src="https://telegram.org/js/telegram-web-app.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #0b1d1a; color: white; font-family: sans-serif; overflow-x: hidden; }
        /* The River Grid */
        .river-grid { display: grid; grid-template-columns: repeat(10, 1fr); gap: 4px; padding: 10px; background: #071412; border-radius: 10px; height: 350px; overflow-y: auto; }
        .river-cell { background: #132a26; border: 1px solid #1c3d38; height: 30px; display: flex; align-items: center; justify-content: center; font-size: 0.7rem; font-weight: bold; border-radius: 4px; color: #4ade80; cursor: pointer; }
        .river-cell.selected { background: #000; color: #94a3b8; border-color: #000; }
        .river-cell.mine { background: #10b981 !important; color: white !important; border-color: #34d399; transform: scale(1.1); }
        
        /* Bottom Preview Area */
        .preview-box { background: #071412; border: 2px solid #10b981; border-radius: 15px; padding: 10px; width: 140px; }
        .preview-cell { font-size: 0.6rem; text-align: center; color: #4ade80; height: 20px; border: 0.1px solid #1c3d38; display: flex; align-items: center; justify-content: center; }
        
        /* Action Buttons */
        .btn-action { background: #10b981; color: #0b1d1a; padding: 12px; border-radius: 10px; font-weight: 900; text-transform: uppercase; font-size: 0.8rem; width: 100%; box-shadow: 0 4px 0 #065f46; transition: 0.1s; }
        .btn-action:active { transform: translateY(4px); box-shadow: none; }
        
        /* Red Error Modal */
        .modal-err { position: fixed; top: 20%; left: 50%; transform: translateX(-50%); background: #1e1b1b; border: 2px solid #ef4444; border-radius: 15px; padding: 20px; width: 85%; z-index: 100; text-align: center; box-shadow: 0 0 30px rgba(239, 68, 68, 0.4); }
        .hidden { display: none; }
    </style>
</head>
<body class="p-3">
    <!-- TOP BAR -->
    <div class="flex justify-between items-center mb-4">
        <div class="flex items-center gap-2 bg-slate-900/50 p-2 rounded-lg border border-slate-800">
            <div class="bg-yellow-500 text-black p-1 rounded-md text-xs">💰</div>
            <div class="font-black text-sm"><span id="user-bal">0.00</span> ETB</div>
        </div>
        <div class="font-black text-emerald-400 italic">NEXT VLAD GAMES</div>
    </div>

    <!-- ERROR MODAL -->
    <div id="modal-err" class="modal-err hidden">
        <div class="bg-red-500 w-10 h-10 rounded-full flex items-center justify-center mx-auto mb-3">❌</div>
        <h2 class="text-white font-bold text-lg mb-1">Error</h2>
        <p class="text-red-400 text-xs mb-4">Insufficient Balance</p>
        <button onclick="hideErr()" class="w-full py-2 bg-slate-800 rounded-lg font-bold">CLOSE</button>
    </div>

    <!-- VIEW: SELECTOR (The River) -->
    <div id="view-selector">
        <div class="river-grid mb-4" id="river"></div>
        
        <div class="flex gap-3 items-end">
            <!-- Card Preview (Left) -->
            <div class="preview-box">
                <div class="grid grid-cols-5 gap-0.5" id="preview-grid"></div>
                <div class="text-[10px] text-center mt-2 text-emerald-500 font-bold">Card #<span id="preview-num">--</span></div>
            </div>
            
            <!-- Controls (Right) -->
            <div class="flex-1 space-y-3">
                <button onclick="pickRandom()" class="btn-action" style="background: #1c3d38; color: #4ade80; border: 1px solid #10b981;">🎲 RANDOM</button>
                <button onclick="requestStart()" class="btn-action">▶ START!</button>
            </div>
        </div>
    </div>

    <!-- VIEW: HALL (Hidden initially) -->
    <div id="view-hall" class="hidden text-center">
        <h1 class="text-yellow-500 font-black mb-4 tracking-widest">LIVE BINGO HALL</h1>
        <div id="tracker" class="grid grid-cols-1 gap-1 mb-4 p-2 bg-black/40 rounded-xl border border-emerald-900/30"></div>
        <div id="hall-card" class="grid grid-cols-5 gap-1.5 bg-slate-800 p-2 rounded-2xl border-2 border-slate-700 shadow-2xl"></div>
    </div>

    <script>
        const tg = window.Telegram.WebApp; const uid = tg.initDataUnsafe.user ? tg.initDataUnsafe.user.id : 0;
        let selectedId = null; let activeBet = 20; // Default room

        function hideErr() { document.getElementById('modal-err').classList.add('hidden'); }
        function showHall() { document.getElementById('view-selector').classList.add('hidden'); document.getElementById('view-hall').classList.remove('hidden'); }

        // 1. Build the River (1-200)
        const river = document.getElementById('river');
        for(let i=1; i<=200; i++) {
            let div = document.createElement('div'); div.className = 'river-cell'; div.id = 'r-'+i; div.innerText = i;
            div.onclick = () => selectCard(i);
            river.appendChild(div);
        }

        function selectCard(num) {
            selectedId = num;
            // Highlight in river
            Array.from(river.children).forEach(c=>c.classList.remove('mine'));
            document.getElementById('r-'+num).classList.add('mine');
            // Fetch preview
            fetch('/api/card-data/' + num + '/').then(r=>r.json()).then(d => {
                const prev = document.getElementById('preview-grid'); prev.innerHTML = '';
                document.getElementById('preview-num').innerText = num;
                d.board.forEach(row => row.forEach(val => {
                    let c = document.createElement('div'); c.className = 'preview-cell';
                    c.innerText = val === 'FREE' ? 'X' : val;
                    prev.appendChild(c);
                }));
            });
        }

        function pickRandom() { selectCard(Math.floor(Math.random() * 200) + 1); }

        function requestStart() {
            if(!selectedId) return alert("Select a card first!");
            fetch(`/api/join-room/${uid}/${activeBet}/${selectedId}/`).then(r=>r.json()).then(d => {
                if(d.status === 'ok') location.reload();
                else document.getElementById('modal-err').classList.remove('hidden');
            });
        }

        // Initialize Balance & Check if user is already in a game
        fetch('/api/lobby-info/' + uid + '/').then(r=>r.json()).then(d => {
            document.getElementById('user-bal').innerText = d.balance.toFixed(2);
            if(d.active_game) { showHall(); loadHall(d.active_game); }
        });

        function loadHall(gid) {
            const tr = document.getElementById('tracker');
            ['B','I','N','G','O'].forEach((l, idx) => {
                let h = `<div class="flex gap-1 items-center"><div class="text-yellow-500 font-bold w-4 text-[8px]">${l}</div>`;
                for(let i=(idx*15)+1; i<=(idx*15)+15; i++) h += `<div id="t-${i}" class="num-dot">${i}</div>`;
                tr.innerHTML += h + '</div>';
            });
            // Fetch game data and build the big hall card... (Previous Hall Logic)
        }
    </script>
</body>
</html>
EOF

# 2. Update views.py (Add card-data endpoint)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse
from .models import User, GameRound, PermanentCard
from decimal import Decimal

def live_view(request): return render(request, 'live_view.html')

def lobby_info(request, tg_id):
    user, _ = User.objects.get_or_create(username=f"tg_{tg_id}")
    active_game = GameRound.objects.exclude(status="ENDED").last()
    joined_id = active_game.id if (active_game and str(tg_id) in active_game.players) else None
    return JsonResponse({'balance': float(user.operational_credit), 'active_game': joined_id})

def get_card_data(request, card_num):
    try:
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'board': card.board})
    except: return JsonResponse({'error': 'Not found'}, status=404)

def join_room(request, tg_id, bet, card_num):
    user = User.objects.get(username=f"tg_{tg_id}")
    if user.operational_credit < bet: return JsonResponse({'status': 'error'})
    game, _ = GameRound.objects.get_or_create(status="LOBBY", bet_amount=bet)
    user.operational_credit -= Decimal(bet); user.save()
    game.players[str(tg_id)] = card_num; game.save()
    return JsonResponse({'status': 'ok'})
EOF

# 3. URLs Sync
cat <<'EOF' > backend/bingo/urls.py
from django.urls import path
from .views import *
urlpatterns = [
    path('live/', live_view),
    path('lobby-info/<int:tg_id>/', lobby_info),
    path('card-data/<int:card_num>/', get_card_data),
    path('join-room/<int:tg_id>/<int:bet>/<int:card_num>/', join_room),
]
EOF

echo "✅ RIVER UI SYSTEM APPLIED!"
