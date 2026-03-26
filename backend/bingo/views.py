from django.shortcuts import render
from django.http import HttpResponse, JsonResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard, GameRound
from decimal import Decimal

def home(request):
    return HttpResponse("<h1>VladBingo Platform is Online</h1>")

def live_view(request):
    return render(request, 'live_view.html')

def get_game_info(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        prize = float(len(game.players) * game.bet_amount) * 0.80 # 20% Cut
        card_num = game.players.get(str(tg_id), 1)
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({
            'game_id': game.id, 'card_number': card.card_number, 
            'board': card.board, 'prize': round(prize, 2),
            'status': game.status, 'called_numbers': game.called_numbers
        })
    except: return JsonResponse({'error': 'Error'}, status=404)

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request): return Response({"status": "ok"})
