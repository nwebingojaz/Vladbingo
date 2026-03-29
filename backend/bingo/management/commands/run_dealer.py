import time, random
from django.core.management.base import BaseCommand
from django.utils import timezone
from bingo.models import GameRound

class Command(BaseCommand):
    def handle(self, *args, **options):
        self.stdout.write("VLAD BINGO DEALER: INSTANT RESPAWN ACTIVE")
        TIERS = [10, 20, 30, 40, 50, 100]

        while True:
            now = timezone.now()
            for tier in TIERS:
                room = GameRound.objects.filter(bet_amount=tier).exclude(status="ENDED").first()
                
                # INSTANT RESPAWN: If no lobby/active room exists, make one immediately
                if not room:
                    room = GameRound.objects.create(bet_amount=tier, status="LOBBY")
                    self.stdout.write(f"New {tier} ETB Lobby Created instantly.")
                
                elif room.status == "LOBBY":
                    elapsed = (now - room.created_at).total_seconds()
                    if elapsed >= 60:
                        room.status = "ACTIVE"
                        room.save()
                
                elif room.status == "ACTIVE":
                    called = room.called_numbers
                    if len(called) < 75:
                        remaining = [n for n in range(1, 76) if n not in called]
                        if remaining:
                            called.append(random.choice(remaining))
                            room.called_numbers = called
                            room.save()
                    else:
                        room.status = "ENDED"
                        room.finished_at = now
                        room.save()
            time.sleep(4)
