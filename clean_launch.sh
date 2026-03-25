#!/bin/bash
# VladBingo - Final Launch Logic (Win Verification & Payouts)

# 1. Update views.py (Win Checking + Home View)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo is LIVE</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_user_card(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        card_num = user.selected_cards[-1] if user.selected_cards else 1
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
    except:
        return JsonResponse({'error': 'No card'}, status=404)

def check_win(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status="ACTIVE").last()
        if not game: return JsonResponse({'status': 'NO_ACTIVE_GAME'})
        card = PermanentCard.objects.get(card_number=user.selected_cards[-1])
        called_set = set(game.called_numbers)
        board = card.board
        won = False
        for row in board:
            if all(cell == "FREE" or cell in called_set for cell in row): won = True
        for c in range(5):
            col = [board[r][c] for r in range(5)]
            if all(cell == "FREE" or cell in called_set for cell in col): won = True
        if won:
            prize = Decimal("50.00")
            user.operational_credit += prize
            user.save()
            game.status = "ENDED"
            game.save()
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        return JsonResponse({'status': 'NOT_YET'})
    except:
        return JsonResponse({'status': 'ERROR'})
EOF

# 2. Update urls.py
cat <<'EOF' > backend/bingo/urls.py
from django.urls import path
from .views import live_view, get_user_card, check_win
urlpatterns = [
    path('live/', live_view),
    path('user-card-data/<int:tg_id>/', get_user_card),
    path('check-win/<int:tg_id>/', check_win),
]
EOF

# 3. Final Mini App HTML (With the BINGO! Button logic)
cat <<'EOF' > backend/bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>VladBingo Live</title>
    <script src="https://telegram.org/js/telegram-web-app.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background-color: #0f172a; color: white; font-family: sans-serif; }
        .num-dot { width: 18px; height: 18px; display: flex; align-items: center; justify-content: center; font-size: 0.6rem; border-radius: 50%; background: #1e293b; }
        .called { background: #fbbf24 !important; color: black !important; }
        .card-cell { background: #1e293b; aspect-ratio: 1/1; display: flex; align-items: center; justify-content: center; font-weight: bold; border: 1px solid #334155; border-radius: 6px; }
        .marked { background: #10b981 !important; color: white !important; }
    </style>
</head>
<body class="p-3">
    <div id="tracker" class="grid grid-cols-1 gap-1 mb-4 p-2 bg-slate-900 rounded-lg"></div>
    <div id="user-card" class="grid grid-cols-5 gap-1 bg-slate-800 p-2 rounded-xl border-2 border-slate-700 shadow-2xl"></div>
    <button id="bingo-btn" class="mt-6 w-full py-4 bg-yellow-500 text-black font-black text-xl rounded-lg shadow-lg">BINGO! 📢</button>
    <script>
        const tg = window.Telegram.WebApp;
        const uid = tg.initDataUnsafe.user ? tg.initDataUnsafe.user.id : 0;
        fetch('/api/user-card-data/' + uid + '/').then(r=>r.json()).then(data=>{
            data.board.forEach(row => row.forEach(val => {
                const cell = document.createElement('div');
                cell.className = 'card-cell';
                cell.innerText = val === 'FREE' ? '★' : val;
                if(val === 'FREE') cell.classList.add('marked');
                cell.onclick = () => cell.classList.toggle('marked');
                document.getElementById('user-card').appendChild(cell);
            }));
        });
        document.getElementById('bingo-btn').onclick = () => {
            fetch('/api/check-win/' + uid + '/').then(r=>r.json()).then(d=>{
                if(d.status==='WINNER') alert("🏆 BINGO! You won "+d.prize+" ETB!");
                else alert("❌ Not a Bingo yet!");
            });
        };
    </script>
</body>
</html>
EOF

echo "✅ Files prepared! Now run the manual git commands."
