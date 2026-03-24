from django.shortcuts import render
from django.http import HttpResponse, JsonResponse
from .models import User, PermanentCard
def home(request): return HttpResponse("<h1>VladBingo Online</h1>")
def live_view(request): return render(request, 'live_view.html')
def get_user_card(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        card = PermanentCard.objects.get(card_number=user.selected_cards[0])
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
    except:
        card = PermanentCard.objects.first()
        return JsonResponse({'card_number': 1, 'board': card.board if card else []})
