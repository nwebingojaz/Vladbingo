import os, sys, django
from pathlib import Path
from asgiref.sync import sync_to_async
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, KeyboardButton, ReplyKeyboardMarkup, ReplyKeyboardRemove, WebAppInfo
from telegram.ext import Application, CommandHandler, MessageHandler, CallbackQueryHandler, filters

BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()
from bingo.models import User

def db_op(uid, action, val=None):
    user, _ = User.objects.get_or_create(username=f"tg_{uid}")
    if action == "name": 
        user.real_name = val
        user.bot_state = "IDLE"
    elif action == "phone": 
        user.phone_number = val
        user.bot_state = "IDLE"
    elif action == "state": 
        user.bot_state = val
    user.save()
    return user

async def send_main_menu(update: Update, user):
    # GUARANTEED WORKING IMAGE LINK
    photo_url = "https://i.ibb.co/3m20B6k/bingo-money.jpg"
    
    caption = (
        f"🎰 **BIGEST BINGO BOT** 🎰\n\n"
        f"እንኳን በደህና መጡ፣ **{user.real_name}**! (Welcome)\n"
        f"💰 **ቀሪ ሂሳብ (Balance):** {user.operational_credit} ETB\n\n"
        f"ከታች ካሉት አማራጮች ውስጥ ይምረጡ:\n_(Choose an option below)_"
    )
    
    base_url = "https://vladbingo-dmzg.onrender.com/api/live/"
    
    keyboard = [
        [InlineKeyboardButton("🎮 ጌም ይጫወቱ (Play Games)", web_app=WebAppInfo(url=base_url))],
        [InlineKeyboardButton("💰 ያስገቡ (Deposit)", web_app=WebAppInfo(url=base_url + "#deposit")), InlineKeyboardButton("💸 ያውጡ (Withdraw)", web_app=WebAppInfo(url=base_url + "#withdraw"))],
        [InlineKeyboardButton("↔️ ያስተላልፉ (Transfer)", web_app=WebAppInfo(url=base_url + "#transfer")), InlineKeyboardButton("👤 ፕሮፋይል (Profile)", callback_data="profile")],
        [InlineKeyboardButton("📜 ታሪክ (History)", web_app=WebAppInfo(url=base_url + "#history")), InlineKeyboardButton("⚖️ ሂሳብ (Balance)", callback_data="balance")],
        [InlineKeyboardButton("📢 ቻናል (Channel)", url="https://t.me/bigestbingo"), InlineKeyboardButton("💬 ግሩፕ (Group)", url="https://t.me/bigestbingochat")],
        [InlineKeyboardButton("🎧 ያግኙን (Contact Admin)", url="https://t.me/yeab")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)

    if update.message:
        try:
            await update.message.reply_photo(photo=photo_url, caption=caption, reply_markup=reply_markup, parse_mode='Markdown')
        except:
            await update.message.reply_text(text=caption, reply_markup=reply_markup, parse_mode='Markdown')

async def start(update: Update, context):
    tg_id = update.effective_user.id
    user = await sync_to_async(db_op)(tg_id, "get")
    
    if not user.real_name:
        await sync_to_async(db_op)(tg_id, "state", "REG_NAME")
        return await update.message.reply_text("👋 ወደ **BIGEST BINGO BOT** እንኳን በደህና መጡ!\n\nእባክዎ ትክክለኛ ሙሉ ስምዎን ያስገቡ (Please enter your Full Name):", parse_mode='Markdown')
        
    if not user.phone_number:
        btn = [[KeyboardButton("📲 ስልክ ቁጥር ያጋሩ (Share Phone)", request_contact=True)]]
        return await update.message.reply_text("አካውንትዎን ለማረጋገጥ ከታች ያለውን ቁልፍ ይጫኑ:\n(Tap the button below to verify your phone number)", reply_markup=ReplyKeyboardMarkup(btn, one_time_keyboard=True, resize_keyboard=True))
    
    await send_main_menu(update, user)

async def handle_text(update, context):
    tg_id = update.effective_user.id
    user = await sync_to_async(db_op)(tg_id, "get")
    if user.bot_state == "REG_NAME":
        await sync_to_async(db_op)(tg_id, "name", update.message.text)
        await start(update, context)

async def handle_contact(update, context):
    tg_id = update.effective_user.id
    phone = update.message.contact.phone_number
    if phone.startswith('+251'): phone = '0' + phone[4:]
    elif phone.startswith('251'): phone = '0' + phone[3:]
        
    await sync_to_async(db_op)(tg_id, "phone", phone)
    await update.message.reply_text("✅ ስልክዎ በትክክል ተረጋግጧል! (Phone Verified Successfully!)", reply_markup=ReplyKeyboardRemove())
    await start(update, context)

async def handle_buttons(update: Update, context):
    query = update.callback_query
    user = await sync_to_async(db_op)(query.from_user.id, "get")
    
    if query.data == "balance":
        await query.answer(f"💰 ቀሪ ሂሳብዎ (Balance): {user.operational_credit} ETB", show_alert=True)
    elif query.data == "profile":
        phone = user.phone_number if user and user.phone_number else "ያልተመዘገበ (Not linked)"
        msg = f"👤 <b>የእርስዎ ፕሮፋይል (Profile)</b>\n\n🆔 መለያ (ID): <code>{user.username.replace('tg_','')}</code>\n📱 ስልክ (Phone): {phone}\n💰 ሂሳብ (Balance): {user.operational_credit} ETB"
        await context.bot.send_message(query.message.chat.id, msg, parse_mode="HTML")
        await query.answer()
    else:
        await query.answer()

def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not token:
        print("CRITICAL ERROR: TELEGRAM_BOT_TOKEN is missing!")
        return
        
    app = Application.builder().token(token).post_init(lambda a: a.bot.delete_webhook(drop_pending_updates=True)).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    app.add_handler(MessageHandler(filters.CONTACT, handle_contact))
    app.add_handler(CallbackQueryHandler(handle_buttons))
    
    print("BIGEST BINGO BOT Started successfully!")
    app.run_polling()

if __name__ == "__main__": 
    run()