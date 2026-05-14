import random
from django.core.management.base import BaseCommand
from bingo.models import PermanentCard, GameRound

class Command(BaseCommand):
    def handle(self, *args, **options):
        # Always wipe and rebuild cards to ensure authentic layout
        # THIS WILL AUTOMATICALLY DELETE YOUR 5000 CARDS AND RESET TO 1000
        PermanentCard.objects.all().delete()
        
        # Updated the message and the range to 1000
        self.stdout.write("Generating 1000 Authentic B-I-N-G-O Cards...")
        for i in range(1, 1001):  # Changed to 1001 to generate exactly 1000 cards
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
            
        self.stdout.write("✅ 1000 Authentic Cards Generated!")