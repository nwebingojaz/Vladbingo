import random
from django.core.management.base import BaseCommand
from bingo.models import PermanentCard, GameRound

class Command(BaseCommand):
    def handle(self, *args, **options):
        if not PermanentCard.objects.exists():
            for i in range(1, 201):
                board = [[random.randint(1,75) for _ in range(5)] for _ in range(5)]
                board[2][2] = "FREE"
                PermanentCard.objects.create(card_number=i, board=board)
        for t in [10, 20, 50, 100]:
            GameRound.objects.get_or_create(bet_amount=t, status="LOBBY")
