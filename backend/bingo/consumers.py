import json
from channels.generic.websocket import AsyncWebsocketConsumer
class BingoConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.game_id = self.scope['url_route']['kwargs']['game_id']
        self.room_group_name = f'game_{self.game_id}'
        await self.channel_layer.group_add(self.room_group_name, self.channel_name)
        await self.accept()
    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.room_group_name, self.channel_name)
    async def bingo_message(self, event):
        await self.send(text_data=json.dumps(event["message"]))
