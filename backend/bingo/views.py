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
