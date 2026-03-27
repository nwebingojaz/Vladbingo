#!/bin/bash
# VladBingo - Tiered Win Engine (Corners = 1 Line)

# 1. Update Views.py (The Logic Core)
cat <<'EOF' > backend/bingo/views.py
from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo Engine: Tiered Wins Ready</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_game_info(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        prize = float(len(game.players) * game.bet_amount) * 0.80 # 20% cut for you
        card_num = game.players.get(str(tg_id), 1)
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({
            'card_number': card.card_number, 'board': card.board,
            'prize': round(prize, 2), 'status': game.status,
            'called_numbers': game.called_numbers
        })
    except: return JsonResponse({'error': 'Sync Error'})

def check_win(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        if game.status != "ACTIVE": return JsonResponse({'status': 'NOT_ACTIVE'})
        if "WON" in game.status: return JsonResponse({'status': 'ALREADY_WON'})

        card_num = game.players.get(str(tg_id))
        card = PermanentCard.objects.get(card_number=card_num)
        called_set = set(game.called_numbers)
        board = card.board
        
        total_lines = 0

        # A. Check Rows (5 total)
        for row in board:
            if all(c == "FREE" or c in called_set for c in row):
                total_lines += 1

        # B. Check Columns (5 total)
        for c in range(5):
            if all(board[r][c] == "FREE" or board[r][c] in called_set for r in range(5)):
                total_lines += 1

        # C. Check Diagonals (2 total)
        if all(board[i][i] == "FREE" or board[i][i] in called_set for i in range(5)):
            total_lines += 1
        if all(board[i][4-i] == "FREE" or board[i][4-i] in called_set for i in range(5)):
            total_lines += 1

        # D. SPECIAL RULE: 4 Corners count as 1 line
        corners = [board[0][0], board[0][4], board[4][0], board[4][4]]
        if all(c in called_set for c in corners):
            total_lines += 1

        # Check Threshold based on Room Bet
        is_winner = False
        bet = float(game.bet_amount)
        if bet <= 40:
            if total_lines >= 2: is_winner = True
        else: # 50 or 100 ETB
            if total_lines >= 3: is_winner = True

        if is_winner:
            prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
            user.operational_credit += prize
            user.save()
            game.status = f"WON_BY_{card.card_number}"
            game.save()
            Transaction.objects.create(agent=user, amount=prize, type="WIN", note=f"Game #{game.id}")
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        
        return JsonResponse({'status': 'NOT_YET', 'lines_found': total_lines})
    except Exception as e:
        return JsonResponse({'status': 'ERROR', 'msg': str(e)})

from rest_framework.views import APIView
from rest_framework.response import Response
class ChapaWebhookView(APIView):
    permission_classes = []; def post(self, request): return Response({"status": "ok"})
EOF

echo "✅ Tiered Win Engine logic updated!"
