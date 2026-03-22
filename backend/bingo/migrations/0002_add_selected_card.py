from django.db import migrations, models

class Migration(migrations.Migration):
    dependencies = [('bingo', '0001_initial')]
    operations = [
        migrations.AddField(
            model_name='user',
            name='selected_card',
            field=models.PositiveSmallIntegerField(default=1),
        ),
        migrations.CreateModel(
            name='Transaction',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('timestamp', models.DateTimeField(default=django.utils.timezone.now)),
                ('amount', models.DecimalField(decimal_places=2, max_digits=12)),
                ('running_balance', models.DecimalField(decimal_places=2, max_digits=12)),
                ('note', models.TextField(blank=True)),
                ('agent', models.ForeignKey(on_delete=models.deletion.CASCADE, to='bingo.user')),
            ],
        ),
    ]
