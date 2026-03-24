from django.shortcuts import render
from django.http import JsonResponse
from .models import User, PermanentCard

def live_view(request):
    return render(request, 'live_view.html')

def get_user_card(request, tg_id):
    """The Mini App calls this to find out which card the user owns right now"""
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        card = PermanentCard.objects.get(card_number=user.selected_card)
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
    except:
        # If user hasn't picked a card, default to 1 (or show error)
        card = PermanentCard.objects.first()
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
