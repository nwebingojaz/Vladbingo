from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal
import os, requests

def home(request): return HttpResponse("<h1>VladBingo Engine: Online</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_game_info(request, game_id, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.get(id=game_id)
        prize = float(len(game.players) * game.bet_amount) * 0.80
        card_num = game.players.get(str(tg_id), 1)
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board, 'prize': round(prize, 2), 'status': game.status, 'called_numbers': game.called_numbers})
    except: return JsonResponse({'error': 'Error'})

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request):
        data = request.data
        if data.get('status') == 'success':
            ref = data.get('tx_ref') # Format: vlad_USERID_unique
            try:
                u_id = ref.split('_')[1]
                amount = Decimal(data.get('amount'))
                user = User.objects.get(id=u_id)
                user.operational_credit += amount
                user.save()
                # Notify User on Telegram
                bot_token = os.environ.get("TELEGRAM_BOT_TOKEN")
                tg_id = user.username.split('_')[1]
                msg = f"💰 **DEPOSIT SUCCESS!**\n\n{amount} ETB added.\nNew Balance: {user.operational_credit} ETB"
                requests.get(f"https://api.telegram.org/bot{bot_token}/sendMessage?chat_id={tg_id}&text={msg}&parse_mode=Markdown")
                return Response(status=200)
            except: pass
        return Response(status=200) # Always return 200 to Chapa
