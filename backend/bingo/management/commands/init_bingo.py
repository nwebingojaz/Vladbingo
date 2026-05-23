import random
from django.core.management.base import BaseCommand
from bingo.models import PermanentCard, GameRound

class Command(BaseCommand):
    def handle(self, *args, **options):
        # FIX: Check if we already have 1000 cards. If yes, skip!
        if PermanentCard.objects.count() == 1000:
            self.stdout.write("✅ 1000 Cards already exist. Skipping generation.")
        else:
            self.stdout.write("Generating 1000 Authentic B-I-N-G-O Cards...")
            PermanentCard.objects.all().delete()
            
            for i in range(1, 1001):
                b = random.sample(range(1, 16), 5)
                i_col = random.sample(range(16, 31), 5)
                n = random.sample(range(31, 46), 5)
                g = random.sample(range(46, 61), 5)
                o = random.sample(range(61, 76), 5)
                
                n[2] = "FREE"
                
                board = []
                for row_idx in range(5):
                    board.append([b[row_idx], i_col[row_idx], n[row_idx], g[row_idx], o[row_idx]])
                
                PermanentCard.objects.create(card_number=i, board=board)
            self.stdout.write("✅ 1000 Authentic Cards Generated!")

        # Ensure rooms exist
        for t in [10, 20, 30, 40, 50, 100]:
            GameRound.objects.get_or_create(bet_amount=t, status="LOBBY")