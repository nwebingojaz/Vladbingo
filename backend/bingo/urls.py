from django.urls import path
from .views import ChapaWebhookView, live_view
urlpatterns = [
    path('chapa-webhook/', ChapaWebhookView.as_view()),
    path('live/', live_view, name='live_view'),
]
