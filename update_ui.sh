#!/bin/bash
# VladBingo - Professional Compressed UI

cat <<EOF > backend/bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VladBingo Live Hall</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #0f172a; color: white; overflow-x: hidden; }
        .letter-box { background-color: #334155; width: 30px; height: 30px; display: flex; align-items: center; justify-content: center; font-weight: 900; border-radius: 4px; color: #fbbf24; }
        .num-box { background-color: #1e293b; width: 22px; height: 22px; display: flex; align-items: center; justify-content: center; font-size: 0.7rem; font-weight: bold; border-radius: 50%; border: 1px solid #334155; }
        .called { background-color: #fbbf24; color: black; border-color: #fbbf24; box-shadow: 0 0 8px #fbbf24; transform: scale(1.1); transition: all 0.2s; }
        .row-container { display: flex; align-items: center; gap: 4px; margin-bottom: 8px; justify-content: center; }
    </style>
</head>
<body class="p-2">
    <div class="max-w-xl mx-auto">
        <header class="flex justify-between items-center mb-4 px-2">
            <h1 class="text-xl font-black text-yellow-500 italic">VLAD BINGO</h1>
            <div id="status" class="text-xs text-green-400 animate-pulse">● LIVE</div>
        </header>

        <!-- B-I-N-G-O Professional Grid -->
        <div id="bingo-board" class="bg-slate-900/50 p-2 rounded-xl border border-slate-800 mb-4">
            <!-- Rows will be injected here by JS -->
        </div>

        <!-- Latest Call Display -->
        <div class="flex gap-4 items-center mb-4">
            <div class="flex-1 bg-slate-800 p-3 rounded-lg border-l-4 border-yellow-500">
                <div class="text-[10px] text-gray-400 uppercase font-bold">Latest Number</div>
                <div id="latest" class="text-4xl font-black">--</div>
            </div>
            <button id="audio-btn" class="flex-1 py-4 bg-green-600 hover:bg-green-500 rounded-lg font-bold text-sm shadow-lg">
                ENABLE VOICE 🔊
            </button>
        </div>
    </div>

    <script>
        const board = document.getElementById('bingo-board');
        const letters = ['B', 'I', 'N', 'G', 'O'];
        const ranges = [[1,15], [16,30], [31,45], [46,60], [61,75]];

        // Create the 5 rows
        letters.forEach((letter, index) => {
            const row = document.createElement('div');
            row.className = 'row-container';
            
            // Add Letter
            row.innerHTML = '<div class="letter-box">' + letter + '</div>';
            
            // Add 15 numbers for this letter
            const start = ranges[index][0];
            const end = ranges[index][1];
            for (let i = start; i <= end; i++) {
                row.innerHTML += '<div id="n-' + i + '" class="num-box">' + i + '</div>';
            }
            board.appendChild(row);
        });

        document.getElementById('audio-btn').onclick = function() {
            this.classList.add('bg-slate-700');
            this.innerText = "VOICE ACTIVE ✅";
            // Audio logic goes here
        };

        // WebSocket placeholder for live updates
        const socket = new WebSocket('wss://' + window.location.host + '/ws/game/live/');
        socket.onmessage = function(e) {
            const data = JSON.parse(e.data);
            if (data.action === 'call_number') {
                const num = data.number;
                document.getElementById('latest').innerText = num;
                const el = document.getElementById('n-' + num);
                if (el) el.classList.add('called');
            }
        };
    </script>
</body>
</html>
EOF

echo "✅ UI Updated to Professional Compressed Layout!"
