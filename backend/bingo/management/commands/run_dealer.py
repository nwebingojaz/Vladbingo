import time, random
from django.core.management.base import BaseCommand
from django.utils import timezone
from bingo.models import GameRound

class Command(BaseCommand):
    def handle(self, *args, **options):
        self.stdout.write("VLAD BINGO DEALER IS LIVE")
        while True:
            now = timezone.now()
            room = GameRound.objects.filter(bet_amount=10).exclude(status="ENDED").first()
            if not room:
                last = GameRound.objects.filter(bet_amount=10, status="ENDED").order_by("-finished_at").first()
                if not last or (now - last.finished_at).total_seconds() >= 60:
                    room = GameRound.objects.create(bet_amount=10, status="LOBBY")
            elif room.status == "LOBBY" and (now - room.created_at).total_seconds() >= 60:
                room.status = "ACTIVE"; room.save()
            elif room.status == "ACTIVE":
                called = room.called_numbers
                if len(called) < 75:
                    remaining = [n for n in range(1, 76) if n not in called]
                    called.append(random.choice(remaining))
                    room.called_numbers = called; room.save()
                else:
                    room.status = "ENDED"; room.finished_at = now; room.save()
            time.sleep(4)
