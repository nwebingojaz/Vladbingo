from django.shortcuts import render
from django.http import HttpResponse, JsonResponse
from rest_framework.views import APIView
from rest_framework.response import Response
from .models import User, PermanentCard

def home(request):
    return HttpResponse("<h1>VladBingo Server is Online</h1>")

def live_view(request):
    return render(request, 'live_view.html')

def get_user_card(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        card = PermanentCard.objects.get(card_number=user.selected_card)
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
    except Exception as e:
        # Fallback to Card #1 if user/card not found
        card = PermanentCard.objects.first()
        return JsonResponse({'card_number': 1, 'board': card.board if card else []})

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request):
        return Response({"status": "ok"})
