from django.shortcuts import render
from django.http import JsonResponse
from .models import PermanentCard, User

def live_view(request):
    return render(request, 'live_view.html')

def get_card_data(request, card_num):
    try:
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board})
    except:
        return JsonResponse({'error': 'Not found'}, status=404)
