import random
from django.core.management.base import BaseCommand
from bingo.models import PermanentCard, GameRound

class Command(BaseCommand):
    def handle(self, *args, **options):
        # Always wipe and rebuild cards to ensure authentic layout
        PermanentCard.objects.all().delete()
        
        self.stdout.write("Generating 200 Authentic B-I-N-G-O Cards...")
        for i in range(1, 201):
            # Strict Column Rules
            b = random.sample(range(1, 16), 5)
            i_col = random.sample(range(16, 31), 5)
            n = random.sample(range(31, 46), 5)
            g = random.sample(range(46, 61), 5)
            o = random.sample(range(61, 76), 5)
            
            n[2] = "FREE" # The center space
            
            # Transpose columns into rows for the 5x5 Grid UI
            board = []
            for row_idx in range(5):
                board.append([b[row_idx], i_col[row_idx], n[row_idx], g[row_idx], o[row_idx]])
            
            PermanentCard.objects.create(card_number=i, board=board)
            
        # Ensure rooms exist
        for t in [10, 20, 30, 40, 50, 100]:
            GameRound.objects.get_or_create(bet_amount=t, status="LOBBY")
            
        self.stdout.write("✅ Authentic Cards Generated!")
