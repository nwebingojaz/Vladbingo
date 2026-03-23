from django.shortcuts import render
from django.http import HttpResponse, JsonResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, Transaction
from decimal import Decimal
import os, requests

def home(request):
    return HttpResponse("<h1>VladBingo Banker is Online</h1>")

def live_view(request):
    return render(request, 'live_view.html')

def get_card_data(request, card_num):
    from .models import PermanentCard
    try:
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
    except:
        return JsonResponse({'error': 'Not found'}, status=404)

class ChapaWebhookView(APIView):
    permission_classes = [] 
    def post(self, request):
        data = request.data
        if data.get('status') == 'success':
            # Chapa returns the email we sent. We use it to find the user.
            email = data.get('email') # format: user_ID@vladbingo.com
            user_id = email.split('_')[1].split('@')[0]
            amount = Decimal(data.get('amount'))
            
            user = User.objects.get(id=user_id)
            user.operational_credit += amount
            user.save()
            
            Transaction.objects.create(
                agent=user, amount=amount, type="DEPOSIT", status="SUCCESS",
                note=f"Chapa Ref: {data.get('tx_ref')}"
            )
            
            # NOTIFY BOT: Send a message to the user via Telegram API
            bot_token = os.environ.get("TELEGRAM_BOT_TOKEN")
            tg_id = user.username.split('_')[1]
            msg = f"💰 **DEPOSIT CONFIRMED!**\n\n{amount} ETB has been added to your balance.\nYour new balance: {user.operational_credit} ETB"
            requests.get(f"https://api.telegram.org/bot{bot_token}/sendMessage?chat_id={tg_id}&text={msg}&parse_mode=Markdown")
            
            return Response(status=200)
        return Response(status=400)
