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
