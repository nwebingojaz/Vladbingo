#!/bin/bash
# VladBingo - Final NameError Fix & Business Logic Sync

# 1. Update views.py (Fixed imports and ChapaWebhookView)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): 
    return HttpResponse("<h1>VladBingo Engine: Ready</h1>")

def live_view(request): 
    return render(request, 'live_view.html')

def get_game_info(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status__in=["LOBBY", "ACTIVE"]).last()
        total_bet = (len(game.players) * game.bet_amount) if game else 0
        prize = float(total_bet) * 0.85 # 15% Admin cut
        
        card_num = user.selected_cards[-1] if user.selected_cards else 1
        card = PermanentCard.objects.get(card_number=card_num)
        
        return JsonResponse({
            'card_number': card.card_number, 
            'board': card.board, 
            'prize': round(prize, 2), 
            'status': game.status if game else 'OFFLINE'
        })
    except: 
        return JsonResponse({'error': 'Error fetching info'})

def check_win(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status="ACTIVE").last()
        if not game: return JsonResponse({'status': 'NO_ACTIVE_GAME'})
        if "WON_BY" in game.status: return JsonResponse({'status': 'ALREADY_WON'})

        card = PermanentCard.objects.get(card_number=user.selected_cards[-1])
        called_set = set(game.called_numbers)
        board = card.board
        
        won = any(all(c == "FREE" or c in called_set for c in row) for row in board) or \
              any(all(board[r][c] == "FREE" or board[r][c] in called_set for r in range(5)) for c in range(5))

        if won:
            total_pool = Decimal(len(game.players)) * game.bet_amount
            prize = total_pool * Decimal("0.85")
            user.operational_credit += prize
            user.save()
            game.status = f"WON_BY_{card.card_number}"
            game.save()
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        
        return JsonResponse({'status': 'NOT_YET'})
    except Exception as e:
        return JsonResponse({'status': 'ERROR', 'msg': str(e)})

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request):
        # We will add real balance logic here later, for now just 'ok'
        return Response({"status": "ok"})
EOF

echo "✅ Typo fixed and views synchronized!"
