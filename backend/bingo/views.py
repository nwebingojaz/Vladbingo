from django.shortcuts import render
from rest_framework.views import APIView
from rest_framework.response import Response

def live_view(request):
    return render(request, 'live_view.html')

class ChapaWebhookView(APIView):
    permission_classes = []
    def post(self, request):
        return Response({"status": "ok"})
