from django.urls import path
from .views import live_view, lobby_info, join_room, get_history, get_card_data
urlpatterns = [
    path('live/', live_view),
    path('lobby-info/<int:tg_id>/', lobby_info),
    path('join-room/<int:tg_id>/<int:bet>/<int:card_num>/', join_room),
    path('card-data/<int:num>/', get_card_data),
    path('history/', get_history),
]
