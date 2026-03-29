#!/bin/bash
# VLAD BINGO - LIVE CARD PREVIEW & NAVIGATION FIX

# 1. Update the Mini App (Adding the Preview Grid)
cat <<'EOF' > backend/bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>Vlad Bingo Pro</title>
    <script src="https://telegram.org/js/telegram-web-app.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #0b1220; color: white; font-family: sans-serif; overflow-x: hidden; }
        .card-btn { background: #1e293b; border: 1px solid #334155; border-radius: 4px; height: 35px; font-size: 0.75rem; font-weight: bold; }
        .card-mine { background: #10b981 !important; border-color: #34d399; color: white; transform: scale(1.05); }
        /* Preview Grid Style */
        .preview-box { background: #0f172a; border: 2px solid #10b981; border-radius: 12px; padding: 8px; width: 130px; margin: 0 auto; }
        .preview-cell { aspect-ratio: 1/1; display: flex; align-items: center; justify-content: center; font-size: 0.6rem; font-weight: bold; border: 0.1px solid #1c3d38; color: #4ade80; }
        .hidden { display: none; }
    </style>
</head>
<body class="p-3">
    <!-- BAL BAR -->
    <div class="flex justify-between items-center mb-4 bg-slate-800/50 p-2 rounded-xl border border-slate-700">
        <div class="text-sm font-bold text-emerald-400">💰 <span id="bal">0.00</span> ETB</div>
        <button onclick="location.reload()" class="text-[9px] bg-slate-700 px-2 py-1 rounded">REFRESH 🔄</button>
    </div>

    <!-- VIEW: SELECTOR (The River) -->
    <div id="v-selector">
        <h2 class="text-center text-[10px] font-bold text-gray-500 uppercase mb-3">Pick Card (1-200)</h2>
        <div id="grid-200" class="grid grid-cols-10 gap-1 h-72 overflow-y-auto bg-slate-900/50 p-2 rounded-xl border border-slate-800 mb-4"></div>
        
        <!-- THE PREVIEW SECTION (NEW) -->
        <div class="flex items-center gap-4 bg-slate-900/80 p-3 rounded-2xl border border-slate-800">
            <div class="preview-box">
                <div id="mini-grid" class="grid grid-cols-5 gap-0.5"></div>
                <div class="text-[8px] text-center mt-1 text-emerald-400 font-bold">CARD #<span id="prev-num">--</span></div>
            </div>
            <div class="flex-1">
                <button id="start-btn" class="w-full py-4 bg-emerald-600 rounded-xl font-black text-sm shadow-lg active:scale-95 transition-all">START! ▶</button>
                <button onclick="location.reload()" class="w-full mt-2 text-[10px] text-gray-500 font-bold uppercase">Cancel</button>
            </div>
        </div>
    </div>

    <!-- VIEW: HALL -->
    <div id="v-hall" class="hidden">
        <div class="bg-slate-800 p-3 rounded-xl mb-3 flex justify-between">
            <div class="text-xl font-black text-emerald-400"><span id="prize">0</span> <span class="text-xs">ETB</span></div>
            <div id="status" class="text-xs font-bold text-yellow-500 animate-pulse uppercase">Live</div>
        </div>
        <div id="tracker" class="grid grid-cols-1 gap-1 mb-4 p-2 bg-slate-950 rounded-lg"></div>
        <div id="hall-card" class="grid grid-cols-5 gap-1 bg-slate-800 p-2 rounded-xl border-2 border-slate-700"></div>
        <button id="bingo-btn" class="mt-4 w-full py-4 bg-yellow-500 text-black font-black text-lg rounded-xl">BINGO! 📢</button>
    </div>

    <script>
        const tg = window.Telegram.WebApp; const uid = tg.initDataUnsafe.user ? tg.initDataUnsafe.user.id : 0;
        let activeBet = 20; let myCard = null;

        // 1. Load the River
        const g = document.getElementById('grid-200');
        for(let i=1; i<=200; i++) {
            let b = document.createElement('button'); b.className="card-btn"; b.id="btn-"+i; b.innerText=i;
            b.onclick=()=> { 
                myCard=i; 
                Array.from(g.children).forEach(c=>c.classList.remove('card-mine')); 
                b.classList.add('card-mine');
                loadPreview(i);
            };
            g.appendChild(b);
        }

        function loadPreview(num) {
            document.getElementById('prev-num').innerText = num;
            fetch('/api/card-data/' + num + '/').then(r=>r.json()).then(data => {
                const mini = document.getElementById('mini-grid'); mini.innerHTML = '';
                data.board.forEach(row => row.forEach(val => {
                    let c = document.createElement('div'); c.className = 'preview-cell';
                    c.innerText = val === 'FREE' ? 'X' : val;
                    mini.appendChild(c);
                }));
            });
        }

        // 2. Join Game
        document.getElementById('start-btn').onclick = () => {
            if(!myCard) return alert("Pick a card!");
            fetch(`/api/join-room/${uid}/${activeBet}/${myCard}/`).then(r=>r.json()).then(d => {
                if(d.status==='ok') location.reload(); else alert(d.error);
            });
        };

        // 3. Main Init
        fetch('/api/lobby-info/' + uid + '/').then(r=>r.json()).then(d => {
            document.getElementById('bal').innerText = d.balance.toFixed(2);
            if(d.active_game) { 
                document.getElementById('v-selector').classList.add('hidden');
                document.getElementById('v-hall').classList.remove('hidden');
                loadHall(d.active_game);
            }
        });

        function loadHall(gid) {
            // Hall logic to load 75-dots and WebSocket
        }
    </script>
</body>
</html>
EOF

echo "✅ Preview Engine & UI Fixed!"
