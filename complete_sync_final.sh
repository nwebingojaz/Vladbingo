#!/bin/bash
# VladBingo - Final Synchronized Logic (Home + Live + Dynamic Sync)

# 1. Update bingo/views.py (Includes EVERYTHING)
cat <<EOF > backend/bingo/views.py
from django.shortcuts import render
from django.http import HttpResponse, JsonResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard

def home(request):
    return HttpResponse("<h1>VladBingo Server is Online</h1>")

def live_view(request):
    return render(request, 'live_view.html')

def get_user_card(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        card = PermanentCard.objects.get(card_number=user.selected_card)
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
    except Exception as e:
        # Fallback to Card #1 if user/card not found
        card = PermanentCard.objects.first()
        return JsonResponse({'card_number': 1, 'board': card.board if card else []})

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request):
        return Response({"status": "ok"})
EOF

# 2. Update bingo/urls.py
cat <<EOF > backend/bingo/urls.py
from django.urls import path
from .views import live_view, get_user_card, ChapaWebhookView
urlpatterns = [
    path('live/', live_view, name='live_view'),
    path('chapa-webhook/', ChapaWebhookView.as_view()),
    path('user-card-data/<int:tg_id>/', get_user_card),
]
EOF

# 3. Update Mini App Template (Self-Updating based on User ID)
cat <<EOF > backend/bingo/templates/live_view.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
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
    <h2 class="text-emerald-400 font-bold mb-2 text-center text-xl">YOUR CARD #<span id="card-num">--</span></h2>
    <div id="user-card" class="grid grid-cols-5 gap-1 bg-slate-800 p-2 rounded-xl border-2 border-slate-700 shadow-2xl"></div>
    <button id="audio-btn" class="mt-4 w-full py-4 bg-green-600 rounded-lg font-bold shadow-lg">ACTIVATE VOICE 🔊</button>

    <script>
        const tg = window.Telegram.WebApp;
        const uid = tg.initDataUnsafe.user ? tg.initDataUnsafe.user.id : 0;
        
        const tracker = document.getElementById('tracker');
        ['B','I','N','G','O'].forEach((l, idx) => {
            let html = '<div class="flex gap-1 items-center"><div class="text-yellow-500 font-bold w-4 text-xs">'+l+'</div>';
            for(let i=(idx*15)+1; i<=(idx*15)+15; i++) {
                html += '<div id="t-'+i+'" class="num-dot">'+i+'</div>';
            }
            tracker.innerHTML += html + '</div>';
        });

        fetch('/api/user-card-data/' + uid + '/')
            .then(res => res.json())
            .then(data => {
                document.getElementById('card-num').innerText = data.card_number;
                data.board.forEach(row => {
                    row.forEach(val => {
                        const cell = document.createElement('div');
                        cell.className = 'card-cell';
                        cell.innerText = val === 'FREE' ? '★' : val;
                        if(val === 'FREE') cell.classList.add('marked');
                        cell.onclick = () => cell.classList.toggle('marked');
                        document.getElementById('user-card').appendChild(cell);
                    });
                });
            });
    </script>
</body>
</html>
EOF

echo "✅ All files synchronized and ready!"
