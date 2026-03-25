#!/bin/bash
# VladBingo - Final Business Logic & Name Sync

# 1. Update views.py (Correct names: home, live_view, get_game_info, check_win)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo Engine: Ready</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_game_info(request, tg_id):
    """Provides card data and live prize math to the Mini App"""
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status__in=["LOBBY", "ACTIVE"]).last()
        total_bet = (len(game.players) * game.bet_amount) if game else 0
        prize = float(total_bet) * 0.85 # 15% Admin cut
        
        # Get the card the user is currently playing
        card_num = user.selected_cards[-1] if user.selected_cards else 1
        card = PermanentCard.objects.get(card_number=card_num)
        
        return JsonResponse({
            'card_number': card.card_number, 
            'board': card.board, 
            'prize': round(prize, 2), 
            'status': game.status if game else 'OFFLINE'
        })
    except: return JsonResponse({'error': 'Error fetching info'})

def check_win(request, tg_id):
    """The logic that handles payouts and ends the game"""
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status="ACTIVE").last()
        if not game: return JsonResponse({'status': 'NO_ACTIVE_GAME'})
        
        # Check if the game is already won by someone else
        if "WON_BY" in game.status: return JsonResponse({'status': 'ALREADY_WON'})

        card = PermanentCard.objects.get(card_number=user.selected_cards[-1])
        called_set = set(game.called_numbers)
        board = card.board
        
        # Standard Win Check
        won = any(all(c == "FREE" or c in called_set for c in row) for row in board) or \
              any(all(board[r][c] == "FREE" or board[r][c] in called_set for r in range(5)) for c in range(5))

        if won:
            total_pool = Decimal(len(game.players)) * game.bet_amount
            prize = total_pool * Decimal("0.85") # The 85% payout
            
            user.operational_credit += prize
            user.save()
            
            # Change status to announce the winner in the bot loop
            game.status = f"WON_BY_{card.card_number}"
            game.save()
            
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        
        return JsonResponse({'status': 'NOT_YET'})
    except Exception as e:
        return JsonResponse({'status': 'ERROR', 'msg': str(e)})

class ChapaWebhookView(import_rest_framework.APIView):
    def post(self, request): return Response({"status": "ok"})
EOF

# 2. Update urls.py (Matching the names exactly)
cat <<'EOF' > backend/bingo/urls.py
from django.urls import path
from .views import live_view, get_game_info, check_win
urlpatterns = [
    path('live/', live_view),
    path('game-info/<int:tg_id>/', get_game_info),
    path('check-win/<int:tg_id>/', check_win),
]
EOF

# 3. Update Mini App JS to call the correct names
sed -i 's/user-card-data/game-info/g' backend/bingo/templates/live_view.html
sed -i 's/check-win/check-win/g' backend/bingo/templates/live_view.html

echo "✅ Business logic and names synchronized!"
