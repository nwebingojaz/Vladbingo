#!/bin/bash
echo "🎨 ADDING CARD PREVIEW & RANDOM BUTTON..."

# 1. Add Card Data View
sed -i '/def lobby_info/i \
def get_card_data(request, num):\
    try:\
        card = PermanentCard.objects.get(card_number=num)\
        return JsonResponse({"board": card.board})\
    except: return JsonResponse({"error": "not found"}, status=404)\
' bingo/views.py

# 2. Update URLs to include card-data path
sed -i "/path('history\/', get_history),/a \    path('card-data/<int:num>/', get_card_data)," bingo/urls.py

# 3. Update HTML to add Preview Box and Random Button
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
        .card-num.active { background: #10b981 !important; color: white; border-color: white; transform: scale(1.1); box-shadow: 0 0 15px rgba(16,185,129,0.5); }
        .preview-container { border: 2px solid #10b981; border-radius: 16px; padding: 12px; background: rgba(0,0,0,0.3); width: 150px; }
        .mini-cell { aspect-ratio: 1/1; display: flex; align-items: center; justify-content: center; font-size: 0.65rem; font-weight: bold; border: 0.1px solid #1c3d38; color: #4ade80; }
        .btn-start { background: #10b981; border-radius: 12px; padding: 15px; font-weight: 900; font-size: 1rem; width: 100%; box-shadow: 0 4px 15px rgba(16, 185, 129, 0.4); }
        .btn-random { background: #1a3a32; border: 1px solid #10b981; border-radius: 12px; width: 100%; padding: 10px; font-size: 0.8rem; font-weight: bold; color: #10b981; margin-bottom: 8px; }
    </style>
</head>
<body class="antialiased select-none">
    <!-- HEADER -->
    <div class="header-bg p-3 flex justify-between items-center shadow-lg">
        <div class="flex items-center gap-2">
            <div class="bg-emerald-500 p-1 rounded font-black text-[10px] text-black italic">VLAD</div>
            <div class="font-black text-xs uppercase">BINGO PRO</div>
        </div>
        <div class="bg-slate-800 px-3 py-1 rounded-full flex items-center gap-2">
            <span class="text-yellow-400">👛</span><span id="bal-header" class="font-bold text-xs">0.00</span>
        </div>
    </div>

    <!-- SUB-NAV -->
    <div class="bg-emerald-950/50 p-2 flex justify-around text-[9px] font-bold text-emerald-300 uppercase border-b border-emerald-900">
        <div>🎲 Room: 10 Birr</div><div onclick="openHistory()">📜 History</div><div onclick="location.reload()">🔄 Refresh</div>
    </div>

    <!-- TIMER -->
    <div class="bg-black/40 p-1 text-center border-b border-white/5">
        <span class="text-[9px] text-emerald-400 font-bold uppercase tracking-widest">Lobby Closes: </span>
        <span id="timer" class="text-[10px] font-mono font-black text-white ml-1">00:00</span>
    </div>

    <!-- SELECTOR -->
    <div id="v-selector" class="p-4">
        <div id="grid-200" class="grid grid-cols-10 gap-1 h-64 overflow-y-auto mb-6 p-2 bg-black/20 rounded-xl"></div>

        <!-- PREVIEW & ACTIONS -->
        <div class="flex gap-4 items-end">
            <div class="preview-container">
                <div id="mini-grid" class="grid grid-cols-5 gap-0.5"></div>
                <div class="text-[9px] text-center mt-2 text-emerald-400 font-bold uppercase">Card <span id="prev-num">#---</span></div>
            </div>
            
            <div class="flex-1">
                <button onclick="pickRandom()" class="btn-random">🎲 RANDOM</button>
                <button onclick="joinGame()" class="btn-start">▶ START!</button>
            </div>
        </div>
    </div>

    <script>
        const tg = window.Telegram.WebApp; const uid = tg.initDataUnsafe.user ? tg.initDataUnsafe.user.id : 0;
        let myCard = null;

        function initGrid() {
            const g = document.getElementById('grid-200'); g.innerHTML = '';
            for(let i=1; i<=200; i++) {
                let b = document.createElement('button'); b.className="card-num"; b.id="c-"+i; b.innerText=i;
                b.onclick=()=> selectCard(i);
                g.appendChild(b);
            }
        }

        function selectCard(num) {
            myCard = num;
            document.querySelectorAll('.card-num').forEach(el=>el.classList.remove('active'));
            document.getElementById('c-'+num).classList.add('active');
            document.getElementById('prev-num').innerText = "#" + num;
            
            // FETCH CARD DETAILS FOR PREVIEW
            fetch('/api/card-data/' + num + '/').then(r=>r.json()).then(data => {
                const mini = document.getElementById('mini-grid'); mini.innerHTML = '';
                data.board.forEach(row => row.forEach(val => {
                    let c = document.createElement('div'); c.className = 'mini-cell';
                    c.innerText = val === 'FREE' ? 'X' : val;
                    mini.appendChild(c);
                }));
            });
        }

        function pickRandom() {
            const rand = Math.floor(Math.random() * 200) + 1;
            selectCard(rand);
            document.getElementById('c-'+rand).scrollIntoView({behavior:'smooth', block:'center'});
        }

        function joinGame() {
            if(!myCard) return alert("Select a Card!");
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
INNER

git add .
git commit -m "UI: Added 5x5 Card Preview and Random button"
git push -f origin main
echo "🚀 PREVIEW SYSTEM UPDATED! Render will refresh now."
