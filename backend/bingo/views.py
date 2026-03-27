from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard, GameRound
from decimal import Decimal

def home(request): 
    return HttpResponse("<h1>VladBingo Engine is Active</h1>")

def live_view(request): 
    return render(request, 'live_view.html')

def get_game_info(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        prize = float(len(game.players) * game.bet_amount) * 0.80 # 20% cut for Admin
        card_num = game.players.get(str(tg_id), 1)
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({
            'game_id': game.id, 'card_number': card.card_number, 'board': card.board,
            'prize': round(prize, 2), 'status': game.status, 'called_numbers': game.called_numbers
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
        lines = 0
        for row in board:
            if all(c == "FREE" or c in called_set for c in row): lines += 1
        for c in range(5):
            if all(board[r][c] == "FREE" or board[r][c] in called_set for r in range(5)): lines += 1
        corners = [board[0][0], board[0][4], board[4][0], board[4][4]]
        if all(c in called_set for c in corners): lines += 1
        is_winner = (float(game.bet_amount) <= 40 and lines >= 2) or (float(game.bet_amount) >= 50 and lines >= 3)
        if is_winner:
            prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
            user.operational_credit += prize; user.save()
            game.status = f"WON_BY_{card.card_number}"; game.save()
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        return JsonResponse({'status': 'NOT_YET'})
    except: return JsonResponse({'status': 'ERROR'})

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request):
        return Response({"status": "ok"})
