#!/bin/bash
# VladBingo - Manual Migration Injection

# 1. Create the migration file manually
cat <<EOF > backend/bingo/migrations/0002_add_selected_card.py
from django.db import migrations, models

class Migration(migrations.Migration):

    dependencies = [
        ('bingo', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='selected_card',
            field=models.PositiveSmallIntegerField(default=1),
        ),
    ]
EOF

# 2. Update build.sh to be simpler and focus on applying migrations
cat <<EOF > backend/build.sh
#!/usr/bin/env bash
set -o errexit
cd backend
pip install -r requirements.txt
python manage.py collectstatic --no-input
# We skip makemigrations here because we created the file manually
python manage.py migrate --no-input
python manage.py init_bingo || true
EOF

echo "✅ Migration injected manually!"
