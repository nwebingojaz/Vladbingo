from django.urls import path
from .views import *
urlpatterns = [
    path('live/', live_view),
    path('lobby-info/<int:tg_id>/', lobby_info),
    path('card-data/<int:card_num>/', get_card_data),
    path('join-room/<int:tg_id>/<int:bet>/<int:card_num>/', join_room),
]
