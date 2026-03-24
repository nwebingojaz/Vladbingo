from django.shortcuts import render
from django.http import JsonResponse
from .models import User, PermanentCard

def live_view(request):
    return render(request, 'live_view.html')

def get_user_card(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        # Always show the last card they added
        if user.selected_cards:
            card_to_show = user.selected_cards[-1]
            card = PermanentCard.objects.get(card_number=card_to_show)
            return JsonResponse({'card_number': card.card_number, 'board': card.board})
        return JsonResponse({'error': 'No cards selected'}, status=404)
    except:
        return JsonResponse({'error': 'Not found'}, status=404)
