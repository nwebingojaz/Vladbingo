import os, sys, django
from pathlib import Path
from asgiref.sync import sync_to_async
from django.db.models import Sum
from django.utils import timezone
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, KeyboardButton, ReplyKeyboardMarkup, ReplyKeyboardRemove, WebAppInfo
from telegram.ext import Application, CommandHandler, MessageHandler, CallbackQueryHandler, filters, ContextTypes

# ==========================================
# 1. BOOTSTRAP DJANGO
# ==========================================
BASE_DIR = Path(__file__).resolve().parent.parent.parent
sys.path.append(str(BASE_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
django.setup()

from bingo.models import User, Transaction, GameControl, GameRound

# ==========================================
# 2. ADMIN CONFIGURATION
# ==========================================
ADMIN_TG_ID = os.environ.get("ADMIN_TG_ID", "YOUR_TG_ID") 

def is_admin(tg_id):
    return str(tg_id) == str(ADMIN_TG_ID)

# ==========================================
# 3. DATABASE WRAPPERS (Sync to Async)
# ==========================================
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

@sync_to_async
def get_pending_transactions():
    return list(Transaction.objects.filter(status="pending").order_by('timestamp'))

@sync_to_async
def process_transaction(tx_id, new_status):
    try:
        tx = Transaction.objects.get(id=tx_id)
        if tx.status != 'pending': return False, f"Transaction #{tx_id} is already {tx.status}."
        tx.status = new_status; tx.save()
        return True, f"Transaction #{tx_id} successfully {new_status}!"
    except Transaction.DoesNotExist: return False, f"Transaction #{tx_id} not found."

@sync_to_async
def set_force_win(card_number):
    control, _ = GameControl.objects.get_or_create(id=1)
    if card_number == 0:
        control.forced_winner_card_number = None; control.save()
        return "Cleared forced winner."
    else:
        control.forced_winner_card_number = card_number; control.save()
        return f"Card #{card_number} is now forced to win!"

@sync_to_async
def get_casino_stats():
    total_users = User.objects.count()
    total_liability = User.objects.aggregate(Sum('operational_credit'))['operational_credit__sum'] or 0
    today = timezone.now().date()
    deposits = Transaction.objects.filter(type__startswith='DEPOSIT', status='approved', timestamp__date=today).aggregate(Sum('amount'))['amount__sum'] or 0
    withdrawals = Transaction.objects.filter(type='WITHDRAWAL', status='approved', timestamp__date=today).aggregate(Sum('amount'))['amount__sum'] or 0
    return f"📊 <b>CASINO STATS</b>\n\n👥 Total Users: {total_users}\n💰 Wallet Liability: {total_liability} ETB\n\n<b>TODAY:</b>\n📥 Deposits: {deposits} ETB\n📤 Withdrawals: {withdrawals} ETB\n💵 Net: {deposits - withdrawals} ETB"

@sync_to_async
def get_and_mark_finished_rooms():
    finished_rooms = list(GameRound.objects.filter(status="ENDED", winner_username__isnull=False))
    for room in finished_rooms:
        room.status = "ANNOUNCED"
        room.save(update_fields=['status'])
    return finished_rooms

@sync_to_async
def get_all_user_tg_ids():
    ids = []
    for u in User.objects.filter(username__startswith='tg_'):
        try: ids.append(int(u.username.replace('tg_', '')))
        except: pass
    return ids

@sync_to_async
def change_user_name(target_tg_id, new_name):
    try:
        user = User.objects.get(username=f"tg_{target_tg_id}")
        user.real_name = new_name
        user.save(update_fields=['real_name'])
        return True, f"Successfully changed user {target_tg_id}'s name to: {new_name}"
    except User.DoesNotExist:
        return False, "User not found."

# --- BULLETPROOF DB SAVER FOR GHOST BOT ---
@sync_to_async
def save_ghost_config(tier, min_c, max_c):
    config_user, _ = User.objects.get_or_create(username=f"sys_ghost_{tier}")
    config_user.real_name = f"{min_c},{max_c}"
    config_user.save()

# ==========================================
# 4. BACKGROUND JOBS (Broadcaster & Promo)
# ==========================================
async def broadcast_winners_task(context: ContextTypes.DEFAULT_TYPE):
    channel_id = os.environ.get("CHANNEL_ID", "@bigestbingo")
    finished_rooms = await get_and_mark_finished_rooms()
    
    for room in finished_rooms:
        msg = (f"🏆 <b>Game #{room.id} Finished!</b>\n\n"
               f"💰 Bet: {float(room.bet_amount):.2f} ETB\n"
               f"👤 Winner: {room.winner_username.replace('tg_','')}\n"
               f"🎁 Prize: {float(room.winner_prize):.2f} ETB\n\n"
               f"Play now: https://t.me/Bigestbingobot")
        try: await context.bot.send_message(chat_id=channel_id, text=msg, parse_mode="HTML")
        except: pass

async def daily_promo_task(context: ContextTypes.DEFAULT_TYPE):
    channel_id = os.environ.get("CHANNEL_ID", "@bigestbingo")
    photo_url = "https://i.ibb.co/3m20B6k/bingo-money.jpg" 
    caption = "🎰 <b>BIGGEST BINGO BOT</b> 🎰\n\nበየቀኑ በሺዎች የሚቆጠሩ ብሮችን ያሸንፉ!\nአሁኑኑ ይጫወቱ እና እድልዎን ይሞክሩ!"
    keyboard = [[InlineKeyboardButton("🎮 አሁኑኑ ይጫወቱ (PLAY NOW)", url="https://t.me/Bigestbingobot")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    try: await context.bot.send_photo(chat_id=channel_id, photo=photo_url, caption=caption, parse_mode="HTML", reply_markup=reply_markup)
    except Exception as e: print(f"Daily promo failed: {e}")

# ==========================================
# 5. USER FLOW COMMANDS
# ==========================================
async def send_main_menu(update: Update, context: ContextTypes.DEFAULT_TYPE, user):
    photo_url = "https://i.ibb.co/3m20B6k/bingo-money.jpg"
    
    caption = (
        f"🎰 <b>BIGGEST BINGO BOT</b> 🎰\n\n"
        f"እንኳን በደህና መጡ፣ <b>{user.real_name}</b>! (Welcome)\n"
        f"💰 <b>ቀሪ ሂሳብ (Balance):</b> {user.operational_credit} ETB\n\n"
        f"ከታች ካሉት አማራጮች ውስጥ ይምረጡ:\n<i>(Choose an option below)</i>"
    )

    if is_admin(user.username.replace('tg_', '')):
        caption += "\n\n👑 <b>Admin Commands:</b>\n/pending - View pending TXs\n/approve [id] - Approve TX\n/reject [id] - Reject TX\n/forcewin [card_num] - Force a card\n/setname [id] [name] - Change a user's name\n/setghost [room] [min] [max] - Control Ghost Players\n/stats - View Casino Stats\n/broadcast - Reply to any msg to Mass DM"
    
    base_url = "https://vladbingo-dmzg.onrender.com/api/live/?v=2.1"
    
    keyboard = [
        [InlineKeyboardButton("🎮 ጌም ይጫወቱ (Play Games)", web_app=WebAppInfo(url=base_url))],
        [InlineKeyboardButton("💰 ያስገቡ (Deposit)", web_app=WebAppInfo(url=base_url + "&tab=deposit")), InlineKeyboardButton("💸 ያውጡ (Withdraw)", web_app=WebAppInfo(url=base_url + "&tab=withdraw"))],
        [InlineKeyboardButton("↔️ ያስተላልፉ (Transfer)", web_app=WebAppInfo(url=base_url + "&tab=transfer")), InlineKeyboardButton("👤 ፕሮፋይል (Profile)", callback_data="profile")],
        [InlineKeyboardButton("📜 ታሪክ (History)", web_app=WebAppInfo(url=base_url + "&tab=history")), InlineKeyboardButton("⚖️ ሂሳብ (Balance)", callback_data="balance")],
        [InlineKeyboardButton("📢 ቻናል (Channel)", url="https://t.me/biggestbingo"), InlineKeyboardButton("💬 ግሩፕ (Group)", url="https://t.me/biggestbingochat")],
        [InlineKeyboardButton("🎧 ያግኙን (Contact Admin)", url="https://t.me/yeab")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)

    chat_id = update.effective_chat.id
    try:
        await context.bot.send_photo(chat_id=chat_id, photo=photo_url, caption=caption, reply_markup=reply_markup, parse_mode='HTML')
    except Exception as e:
        print(f"Photo send failed: {e}. Falling back to text.")
        await context.bot.send_message(chat_id=chat_id, text=caption, reply_markup=reply_markup, parse_mode='HTML')

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    tg_id = update.effective_user.id
    user = await sync_to_async(db_op)(tg_id, "get")
    
    if not user.real_name:
        await sync_to_async(db_op)(tg_id, "state", "REG_NAME")
        return await context.bot.send_message(chat_id=update.effective_chat.id, text="👋 ወደ <b>BIGGEST BINGO BOT</b> እንኳን በደህና መጡ!\n\nእባክዎ ትክክለኛ ሙሉ ስምዎን ያስገቡ (Please enter your Full Name):", parse_mode='HTML')
        
    if not user.phone_number:
        btn = [[KeyboardButton("📲 ስልክ ቁጥር ያጋሩ (Share Phone)", request_contact=True)]]
        return await context.bot.send_message(chat_id=update.effective_chat.id, text="አካውንትዎን ለማረጋገጥ ከታች ያለውን ቁልፍ ይጫኑ:\n(Tap the button below to verify your phone number)", reply_markup=ReplyKeyboardMarkup(btn, one_time_keyboard=True, resize_keyboard=True))
    
    await send_main_menu(update, context, user)

async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    tg_id = update.effective_user.id
    user = await sync_to_async(db_op)(tg_id, "get")
    if user.bot_state == "REG_NAME":
        await sync_to_async(db_op)(tg_id, "name", update.message.text)
        await start(update, context)

async def handle_contact(update: Update, context: ContextTypes.DEFAULT_TYPE):
    tg_id = update.effective_user.id
    phone = update.message.contact.phone_number
    if phone.startswith('+251'): phone = '0' + phone[4:]
    elif phone.startswith('251'): phone = '0' + phone[3:]
        
    await sync_to_async(db_op)(tg_id, "phone", phone)
    await context.bot.send_message(chat_id=update.effective_chat.id, text="✅ ስልክዎ በትክክል ተረጋግጧል! (Phone Verified Successfully!)", reply_markup=ReplyKeyboardRemove())
    await start(update, context)

async def handle_buttons(update: Update, context: ContextTypes.DEFAULT_TYPE):
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

# ==========================================
# 6. ADMIN COMMAND HANDLERS
# ==========================================
async def cmd_pending(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.message.from_user.id): return
    txs = await get_pending_transactions()
    if not txs: return await update.message.reply_text("✅ No pending transactions!")
    msg = "📝 <b>PENDING TRANSACTIONS:</b>\n\n"
    for tx in txs: msg += f"<b>ID:</b> <code>{tx.id}</code>\n<b>Type:</b> {tx.type}\n<b>Amount:</b> {tx.amount} ETB\n<b>Note:</b> {tx.note}\n--------------------\n"
    await update.message.reply_text(msg, parse_mode="HTML")

async def cmd_approve(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.message.from_user.id): return
    try:
        success, msg = await process_transaction(int(context.args[0]), "approved")
        await update.message.reply_text(f"✅ {msg}" if success else f"⚠️ {msg}")
    except (IndexError, ValueError): await update.message.reply_text("⚠️ Usage: /approve <transaction_id>")

async def cmd_reject(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.message.from_user.id): return
    try:
        success, msg = await process_transaction(int(context.args[0]), "rejected")
        await update.message.reply_text(f"🚫 {msg}" if success else f"⚠️ {msg}")
    except (IndexError, ValueError): await update.message.reply_text("⚠️ Usage: /reject <transaction_id>")

async def cmd_forcewin(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.message.from_user.id): return
    try:
        msg = await set_force_win(int(context.args[0]))
        await update.message.reply_text(f"🎯 {msg}")
    except (IndexError, ValueError): await update.message.reply_text("⚠️ Usage: /forcewin <card_number>\nUse 0 to clear.")

async def cmd_setname(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.message.from_user.id): return
    try:
        target_tg_id = context.args[0]
        new_name = " ".join(context.args[1:])
        if not new_name:
            raise ValueError
        success, msg = await change_user_name(target_tg_id, new_name)
        await update.message.reply_text(f"✅ {msg}" if success else f"⚠️ {msg}")
    except (IndexError, ValueError):
        await update.message.reply_text("⚠️ Usage: /setname <telegram_id> <New Name Here>")

async def cmd_setghost(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.message.from_user.id): return
    try:
        tier = int(context.args[0])       
        min_cards = int(context.args[1])  
        max_cards = int(context.args[2])  
        
        valid_tiers = [10, 20, 30, 40, 50, 100]
        if tier not in valid_tiers:
            await update.message.reply_text("⚠️ Invalid room! Please use 10, 20, 30, 40, 50, or 100.")
            return
        
        # Uses the new bulletproof database wrapper
        await save_ghost_config(tier, min_cards, max_cards)
        
        await update.message.reply_text(
            f"✅ GHOST BOT UPDATED FOR ROOM {tier} ETB!\n"
            f"The engine will now gracefully buy between {min_cards} and {max_cards} cards in Room {tier}."
        )
    except (IndexError, ValueError):
        await update.message.reply_text(
            "⚠️ Usage: /setghost <room> <min> <max>\n\n"
            "Example 1: /setghost 10 50 150 (Make room 10 viral)\n"
            "Example 2: /setghost 100 0 2 (Make VIP room sleep/rarely play)\n"
            "Example 3: /setghost 50 0 0 (Put Room 50 fully to sleep)"
        )

async def cmd_stats(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.message.from_user.id): return
    msg = await get_casino_stats()
    await update.message.reply_text(msg, parse_mode="HTML")

async def cmd_broadcast(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.message.from_user.id): return
    if not update.message.reply_to_message:
        await update.message.reply_text("⚠️ You must REPLY to a message, photo, or video with /broadcast to send it to everyone.")
        return
        
    target_message = update.message.reply_to_message
    tg_ids = await get_all_user_tg_ids()
    await update.message.reply_text(f"⏳ Copying your message and sending to {len(tg_ids)} users...")
    
    success_count = 0
    for tid in tg_ids:
        try:
            await context.bot.copy_message(chat_id=tid, from_chat_id=target_message.chat_id, message_id=target_message.message_id)
            success_count += 1
        except Exception as e: pass
        
    await update.message.reply_text(f"✅ Broadcast successfully delivered to {success_count} users!")

# ==========================================
# 7. RUN BOT
# ==========================================
def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not token:
        print("CRITICAL ERROR: TELEGRAM_BOT_TOKEN is missing!")
        return
        
    app = Application.builder().token(token).post_init(lambda a: a.bot.delete_webhook(drop_pending_updates=True)).build()
    
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("pending", cmd_pending))
    app.add_handler(CommandHandler("approve", cmd_approve))
    app.add_handler(CommandHandler("reject", cmd_reject))
    app.add_handler(CommandHandler("forcewin", cmd_forcewin))
    app.add_handler(CommandHandler("setname", cmd_setname))
    app.add_handler(CommandHandler("setghost", cmd_setghost))
    app.add_handler(CommandHandler("stats", cmd_stats))
    app.add_handler(CommandHandler("broadcast", cmd_broadcast))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    app.add_handler(MessageHandler(filters.CONTACT, handle_contact))
    app.add_handler(CallbackQueryHandler(handle_buttons))
    
    app.job_queue.run_repeating(broadcast_winners_task, interval=10, first=5)
    app.job_queue.run_repeating(daily_promo_task, interval=86400, first=60)
    
    print("🚀 BIGGEST BINGO BOT & BROADCASTER ARE RUNNING...")
    app.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__": 
    run()