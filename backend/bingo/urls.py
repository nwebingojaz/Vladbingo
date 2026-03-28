from django.urls import path
from .views import *
urlpatterns = [
    path('', home, name='home'),
    path('live/', live_view, name='live_view'),
    path('lobby-info/<int:tg_id>/', lobby_info),
    path('join-room/<int:tg_id>/<int:bet>/<int:card_num>/', join_room),
    path('game-info/<int:game_id>/<int:tg_id>/', get_game_info),
    path('check-win/<int:tg_id>/', check_win),
    path('chapa-webhook/', ChapaWebhookView.as_view()),
]
