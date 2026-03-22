#!/bin/bash
# VladBingo - Emergency Table Creator

cat <<EOF > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend

# 1. Install dependencies
pip install -r requirements.txt

# 2. Collect static files
python manage.py collectstatic --no-input

# 3. Apply standard migrations
python manage.py migrate --no-input

# 4. THE TABLE HAMMER: Force create missing tables if they are missing
python manage.py shell <<innerEOF
from django.db import connection
with connection.cursor() as cursor:
    # Create PermanentCard table
    try:
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS bingo_permanentcard (
                id bigserial PRIMARY KEY,
                card_number smallint UNIQUE NOT NULL,
                board jsonb NOT NULL
            );
        """)
        print("✅ Table Hammer: bingo_permanentcard created!")
    except Exception as e:
        print(f"ℹ️ Info: PermanentCard table exists or error: {e}")

    # Create GameRound table
    try:
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS bingo_gameround (
                id bigserial PRIMARY KEY,
                created_at timestamptz NOT NULL,
                called_numbers jsonb NOT NULL,
                status varchar(16) NOT NULL,
                amount numeric(12, 2) NOT NULL
            );
        """)
        print("✅ Table Hammer: bingo_gameround created!")
    except Exception as e:
        print(f"ℹ️ Info: GameRound table exists or error: {e}")

    # Create Transaction table
    try:
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS bingo_transaction (
                id bigserial PRIMARY KEY,
                timestamp timestamptz NOT NULL,
                amount numeric(12, 2) NOT NULL,
                running_balance numeric(12, 2) NOT NULL,
                note text NOT NULL,
                agent_id integer NOT NULL
            );
        """)
        print("✅ Table Hammer: bingo_transaction created!")
    except Exception as e:
        print(f"ℹ️ Info: Transaction table exists or error: {e}")
innerEOF

# 5. Initialize Cards (Optional)
python manage.py init_bingo || true
EOF

echo "✅ Table hammer added to build script!"
