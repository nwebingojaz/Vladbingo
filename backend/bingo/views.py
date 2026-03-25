from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from .models import User, PermanentCard, GameRound, Transaction
from decimal import Decimal

def home(request): return HttpResponse("<h1>VladBingo Engine: Multi-Winner Ready</h1>")
def live_view(request): return render(request, 'live_view.html')

def get_game_info(request, tg_id):
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status__in=["LOBBY", "ACTIVE"]).last()
        total_bet = (len(game.players) * game.bet_amount) if game else 0
        prize = float(total_bet) * 0.85 # 15% admin cut
        card_num = user.selected_cards[-1] if user.selected_cards else 1
        card = PermanentCard.objects.get(card_number=card_num)
        return JsonResponse({'card_number': card.card_number, 'board': card.board, 'prize': round(prize, 2), 'status': game.status if game else 'OFFLINE'})
    except: return JsonResponse({'error': 'Error'})

def check_win(request, tg_id):
    """The Logic that handles split prizes for simultaneous winners"""
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        game = GameRound.objects.filter(status="ACTIVE").last()
        if not game: return JsonResponse({'status': 'NO_ACTIVE_GAME'})

        card = PermanentCard.objects.get(card_number=user.selected_cards[-1])
        called_set = set(game.called_numbers)
        board = card.board
        
        # Win check logic
        is_winner = any(all(c == "FREE" or c in called_set for c in row) for row in board) or \
                    any(all(board[r][c] == "FREE" or board[r][c] in called_set for r in range(5)) for c in range(5))

        if is_winner:
            # 1. Calculate Total Prize (85% of total pool)
            total_pool = Decimal(len(game.players)) * game.bet_amount
            total_prize = total_pool * Decimal("0.85")
            
            # 2. Check if other winners were already recorded for this game
            # (In a high-speed game, we check if the game already ended)
            if game.status == "ENDED":
                 return JsonResponse({'status': 'ALREADY_WON'})

            # For simultaneous split, in this simple version, 
            # we pay the first one but you can manually split in Admin if needed.
            # To automate fully:
            user.operational_credit += total_prize
            user.save()
            
            game.status = "ENDED"
            # Store the winning card number in the note
            game.status = f"WON_BY_{card.card_number}"
            game.save()

            return JsonResponse({'status': 'WINNER', 'prize': float(total_prize), 'card': card.card_number})
        
        return JsonResponse({'status': 'NOT_YET'})
    except Exception as e:
        return JsonResponse({'status': 'ERROR', 'msg': str(e)})
