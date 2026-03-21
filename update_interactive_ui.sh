#!/bin/bash
# VladBingo - Interactive Markable Customer Card

# 1. Update Views to include Card Data API
cat <<EOF > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse
from .models import PermanentCard, User

def live_view(request):
    return render(request, 'live_view.html')

def get_card_data(request, card_num):
    try:
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
    except:
        return JsonResponse({'error': 'Not found'}, status=404)
EOF

# 2. Update URLs
cat <<EOF > backend/bingo/urls.py
from django.urls import path
from .views import live_view, get_card_data
urlpatterns = [
    path('live/', live_view, name='live_view'),
    path('card-data/<int:card_num>/', get_card_data),
]
EOF

# 3. Update the Live View (The Masterpiece UI)
cat <<EOF > backend/bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>VladBingo Live</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #0f172a; color: white; font-family: sans-serif; touch-action: manipulation; }
        /* Tracker Styles */
        .num-dot { width: 20px; height: 20px; display: flex; align-items: center; justify-content: center; font-size: 0.65rem; border-radius: 50%; background: #1e293b; border: 1px solid #334155; }
        .called { background: #fbbf24 !important; color: black !important; box-shadow: 0 0 8px #fbbf24; }
        
        /* Personal Card Styles */
        .card-cell { background: #1e293b; aspect-ratio: 1/1; display: flex; align-items: center; justify-content: center; font-weight: bold; font-size: 1.1rem; border: 1px solid #334155; border-radius: 8px; position: relative; }
        .marked { background: #10b981 !important; color: white !important; border-color: #34d399; box-shadow: inset 0 0 10px rgba(0,0,0,0.5); }
        .marked::after { content: '✓'; position: absolute; top: 2px; right: 4px; font-size: 0.6rem; }
        .free-space { background: #3b82f6; color: white; font-size: 0.7rem; }
    </style>
</head>
<body class="p-3">
    <div class="max-w-md mx-auto">
        <!-- 1. THE TRACKER (Top) -->
        <div id="tracker" class="mb-6 p-2 bg-slate-900/50 rounded-xl border border-slate-800">
            <div id="tracker-rows" class="space-y-1"></div>
        </div>

        <!-- 2. THE PERSONAL CARD (Bottom) -->
        <div class="flex justify-between items-end mb-2 px-1">
            <h2 class="text-lg font-bold text-emerald-400">MY CARD <span id="card-label">#--</span></h2>
            <div id="latest-box" class="bg-yellow-500 text-black px-3 py-1 rounded-full font-black text-xl">--</div>
        </div>
        
        <div id="user-card" class="grid grid-cols-5 gap-1.5 bg-slate-800 p-2 rounded-xl border-2 border-slate-700 shadow-2xl">
            <!-- 5x5 Card will be injected here -->
        </div>

        <button id="audio-btn" class="mt-4 w-full py-3 bg-slate-700 rounded-lg font-bold text-sm">ACTIVATE VOICE 🔊</button>
    </div>

    <script>
        const cardGrid = document.getElementById('user-card');
        const trackerRows = document.getElementById('tracker-rows');
        
        // Build Tracker
        ['B','I','N','G','O'].forEach((l, idx) => {
            let rowHtml = '<div class="flex items-center gap-1"><div class="w-6 font-black text-yellow-500 text-xs">'+l+'</div>';
            for(let i=(idx*15)+1; i<=(idx*15)+15; i++) {
                rowHtml += '<div id="t-'+i+'" class="num-dot">'+i+'</div>';
            }
            trackerRows.innerHTML += rowHtml + '</div>';
        });

        // Get Card Number from URL (e.g., ?card=12)
        const urlParams = new URLSearchParams(window.location.search);
        const cardNum = urlParams.get('card') || 1; 
        document.getElementById('card-label').innerText = '#' + cardNum;

        // Fetch and Build User Card
        fetch('/api/card-data/' + cardNum + '/')
            .then(res => res.json())
            .then(data => {
                // Flatten the 5x5 board for display
                const board = data.board; // This is rows [ [c1,c2..], [c1..] ]
                for(let r=0; r<5; r++) {
                    for(let c=0; c<5; c++) {
                        const val = board[r][c];
                        const cell = document.createElement('div');
                        cell.className = 'card-cell' + (val === 'FREE' ? ' marked free-space' : '');
                        cell.innerText = val === 'FREE' ? 'FREE' : val;
                        if(val !== 'FREE') {
                            cell.onclick = () => cell.classList.toggle('marked');
                        }
                        cardGrid.appendChild(cell);
                    }
                }
            });

        // WebSocket for Live Calls
        const socket = new WebSocket('wss://' + window.location.host + '/ws/game/live/');
        socket.onmessage = (e) => {
            const msg = JSON.parse(e.data);
            if(msg.action === 'call_number') {
                document.getElementById('latest-box').innerText = msg.number;
                const dot = document.getElementById('t-' + msg.number);
                if(dot) dot.classList.add('called');
            }
        };
    </script>
</body>
</html>
EOF

echo "✅ Interactive UI with Green Marking Added!"
