from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo Business is LIVE</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_game_info(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status__in=["LOBBY", "STARTING", "ACTIVE"]).last()
        total_pool = (len(game.players) * game.bet_amount) if game else 0
        prize = float(total_pool) * 0.80 # THE 20% CUT: Winner gets 80%
        card_num = user.selected_cards[-1] if user.selected_cards else 1
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board, 'prize': round(prize, 2), 'status': game.status if game else 'OFFLINE', 'called_numbers': game.called_numbers if game else []})
    except: return JsonResponse({'error': 'Error'})

def check_win(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(status="ACTIVE")
        if "WON" in game.status: return JsonResponse({'status': 'ALREADY_WON'})
        card = PermanentCard.objects.get(card_number=user.selected_cards[-1])
        called_set = set(game.called_numbers)
        won = any(all(c == "FREE" or c in called_set for c in row) for row in card.board)
        if won:
            prize = (Decimal(len(game.players)) * game.bet_amount) * Decimal("0.80")
            user.operational_credit += prize; user.save()
            game.status = f"WON_BY_{card.card_number}"; game.save()
            Transaction.objects.create(agent=user, amount=prize, type="WIN", note=f"Game #{game.id}")
            return JsonResponse({'status': 'WINNER', 'prize': float(prize)})
        return JsonResponse({'status': 'NOT_YET'})
    except: return JsonResponse({'status': 'ERROR'})

from rest_framework.views import APIView
from rest_framework.response import Response
class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request):
        data = request.data
        if data.get('status') == 'success':
            ref = data.get('tx_ref') # dep_USERID_unique
            user_id = ref.split('_')[1]
            amount = Decimal(data.get('amount'))
            user = User.objects.get(id=user_id)
            user.operational_credit += amount; user.save()
            return Response(status=200)
        return Response(status=400)
