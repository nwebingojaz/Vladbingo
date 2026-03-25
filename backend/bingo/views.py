from django.shortcuts import render
from django.http import HttpResponse, JsonResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo Engine is Live</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_user_card(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        card_num = user.selected_cards[-1] if user.selected_cards else 1
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
    except:
        card = PermanentCard.objects.first()
        return JsonResponse({'card_number': 1, 'board': card.board if card else []})

def check_win(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status="ACTIVE").last()
        card = PermanentCard.objects.get(card_number=user.selected_cards[-1])
        called_set = set(game.called_numbers)
        board = card.board
        won = any(all(c == "FREE" or c in called_set for c in row) for row in board) or \
              any(all(board[r][c] == "FREE" or board[r][c] in called_set for r in range(5)) for c in range(5))
        if won:
            prize = Decimal("100.00")
            user.operational_credit += prize
            user.save(); game.status = "ENDED"; game.save()
            Transaction.objects.create(agent=user, amount=prize, type="WIN", note=f"Game #{game.id}")
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        return JsonResponse({'status': 'NOT_YET'})
    except: return JsonResponse({'status': 'ERROR'})
