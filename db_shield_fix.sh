#!/bin/bash
# VladBingo - Database Shield and Migration Force

# 1. Update init_bingo.py to be more robust
cat <<EOF > backend/bingo/management/commands/init_bingo.py
from django.core.management.base import BaseCommand
from django.db import connection
from bingo.models import PermanentCard
import random

class Command(BaseCommand):
    def handle(self, *args, **options):
        # Shield: Check if table actually exists before querying
        tables = connection.introspection.table_names()
        if "bingo_permanentcard" not in tables:
            self.stdout.write("Table 'bingo_permanentcard' not found. skipping init.")
            return

        if PermanentCard.objects.exists():
            self.stdout.write("Cards already exist. skipping.")
            return
        
        self.stdout.write("Generating 100 Bingo Cards...")
        for i in range(1, 101):
            board = []
            ranges = [(1,15), (16,30), (31,45), (46,60), (61,75)]
            for r in ranges:
                col = random.sample(range(r[0], r[1]+1), 5)
                board.append(col)
            rows = [[board[c][r] for c in range(5)] for r in range(5)]
            rows[2][2] = "FREE"
            PermanentCard.objects.create(card_number=i, board=rows)
        self.stdout.write("Success!")
EOF

# 2. Update build.sh to ensure migrations are CRITICAL
cat <<EOF > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input

# FORCE migration creation on the server
python manage.py makemigrations --no-input
python manage.py makemigrations bingo --no-input

# APPLY migrations
python manage.py migrate --no-input

# Now run the generator
python manage.py init_bingo
EOF

echo "✅ Database shield applied!"
