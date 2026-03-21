#!/bin/bash
# VladBingo - PermanentCard Model Fix + Generator

# 1. Restore the complete models.py
cat <<EOF > backend/bingo/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone
import random

class User(AbstractUser):
    is_agent = models.BooleanField(default=False)
    operational_credit = models.DecimalField(max_digits=12, decimal_places=2, default=0)

class Transaction(models.Model):
    agent = models.ForeignKey("User", on_delete=models.CASCADE)
    timestamp = models.DateTimeField(default=timezone.now)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    running_balance = models.DecimalField(max_digits=12, decimal_places=2)
    note = models.TextField(blank=True)

class PermanentCard(models.Model):
    card_number = models.PositiveSmallIntegerField(unique=True)
    board = models.JSONField() # Stores the 5x5 grid

class GameRound(models.Model):
    created_at = models.DateTimeField(default=timezone.now)
    called_numbers = models.JSONField(default=list)
    status = models.CharField(max_length=16, default="PENDING")
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
EOF

# 2. Create a Management Command to generate cards automatically on Render
mkdir -p backend/bingo/management/commands
cat <<EOF > backend/bingo/management/commands/init_bingo.py
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
EOF

# 3. Update build.sh to run the generator
cat <<EOF > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py makemigrations bingo --no-input
python manage.py migrate --no-input
# Run the card generator
python manage.py init_bingo
EOF

echo "✅ Models fixed and Card Generator added!"
