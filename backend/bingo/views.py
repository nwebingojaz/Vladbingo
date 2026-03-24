from django.shortcuts import render
from django.http import HttpResponse, JsonResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): 
    return HttpResponse("<h1>VladBingo Server is Online</h1>")

def live_view(request): 
    return render(request, 'live_view.html')

def get_user_card(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        card_num = user.selected_cards[-1] if user.selected_cards else 1
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
    except:
        return JsonResponse({'error': 'Not found'}, status=404)

def check_bingo_win(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status="ACTIVE").last()
        card = PermanentCard.objects.get(card_number=user.selected_cards[-1])
        called_set = set(game.called_numbers)
        board = card.board
        is_winner = False
        # Rows
        for row in board:
            if all(c == "FREE" or c in called_set for c in row): is_winner = True
        # Columns
        for c_idx in range(5):
            col = [board[r_idx][c_idx] for r_idx in range(5)]
            if all(c == "FREE" or c in called_set for c in col): is_winner = True
        
        if is_winner:
            prize = Decimal("500.00")
            user.operational_credit += prize
            user.save()
            game.status = "ENDED"
            game.save()
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        return JsonResponse({'status': 'NOT_YET'})
    except:
        return JsonResponse({'status': 'ERROR'})

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request): return Response({"status": "ok"})
