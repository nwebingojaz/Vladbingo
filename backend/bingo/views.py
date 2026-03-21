from django.shortcuts import render
from django.http import HttpResponse, JsonResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import PermanentCard, User

def home(request):
    return HttpResponse("<h1>VladBingo Server is Online</h1><p>The system is running perfectly.</p>")

def live_view(request):
    return render(request, 'live_view.html')

def get_card_data(request, card_num):
    try:
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
    except:
        return JsonResponse({'error': 'Card not found'}, status=404)

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request):
        return Response({"status": "ok"})
