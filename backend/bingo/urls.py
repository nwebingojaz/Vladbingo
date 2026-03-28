from django.urls import path
from .views import home, live_view, get_game_info, check_win, lobby_info
urlpatterns = [
    path('', home, name='home'),
    path('live/', live_view, name='live_view'),
    path('lobby-info/<int:tg_id>/', lobby_info),
    path('game-info/<int:game_id>/<int:tg_id>/', get_game_info),
    path('check-win/<int:game_id>/<int:tg_id>/', check_win),
]
