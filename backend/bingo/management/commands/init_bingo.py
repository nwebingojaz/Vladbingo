from django.core.management.base import BaseCommand
from bingo.models import PermanentCard
import random

class Command(BaseCommand):
    def handle(self, *args, **options):
        if PermanentCard.objects.exists():
            return
        
        self.stdout.write("Generating 100 Bingo Cards...")
        for i in range(1, 101):
            board = []
            ranges = [(1,15), (16,30), (31,45), (46,60), (61,75)]
            for r in ranges:
                col = random.sample(range(r[0], r[1]+1), 5)
                board.append(col)
            
            # Rotate to rows and add FREE space
            rows = [[board[c][r] for c in range(5)] for r in range(5)]
            rows[2][2] = "FREE"
            
            PermanentCard.objects.create(card_number=i, board=rows)
        self.stdout.write("Success!")
