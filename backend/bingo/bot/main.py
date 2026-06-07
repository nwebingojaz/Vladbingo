import os, sys, django
from pathlib import Path
from asgiref.sync import sync_to_async
from django.db.models import Sum
from django.utils import timezone
from django.core.cache import cache
from django.db import close_old_connections  
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
BOSS_TG_ID = str(os.environ.get("ADMIN_TG_ID", "YOUR_TG_ID"))

def is_boss(tg_id):
    return str(tg_id) == BOSS_TG_ID

def is_admin(tg_id):
    if is_boss(tg_id):
        return True
    sub_admins = cache.get('sub_admins_list', [])
    return str(tg_id) in sub_admins

# ==========================================
# 3. DATABASE WRAPPERS
# ==========================================
def db_op(uid, action, val=None):
    close_old_connections()
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
    close_old_connections()
    return list(Transaction.objects.filter(status="pending").order_by('timestamp'))

@sync_to_async
def process_transaction(tx_id, new_status):
    close_old_connections()
    try:
        tx = Transaction.objects.get(id=tx_id)
        if tx.status != 'pending': return False, f"Transaction #{tx_id} is already {tx.status}."
        tx.status = new_status; tx.save()
        return True, f"Transaction #{tx_id} successfully {new_status}!"
    except Transaction.DoesNotExist: return False, f"Transaction #{tx_id} not found."

@sync_to_async
def set_force_win(card_number):
    close_old_connections()
    control, _ = GameControl.objects.get_or_create(id=1)
    if card_number == 0:
        control.forced_winner_card_number = None; control.save()
        return "Cleared forced winner."
    else:
        control.forced_winner_card_number = card_number; control.save()
        return f"Card #{card_number} is now forced to win!"

@sync_to_async
def get_casino_stats():
    close_old_connections()
    total_users = User.objects.count()
    total_liability = User.objects.aggregate(Sum('operational_credit'))['operational_credit__sum'] or 0
    today = timezone.now().date()
    deposits = Transaction.objects.filter(type__startswith='DEPOSIT', status='approved', timestamp__date=today).aggregate(Sum('amount'))['amount__sum'] or 0
    withdrawals = Transaction.objects.filter(type='WITHDRAWAL', status='approved', timestamp__date=today).aggregate(Sum('amount'))['amount__sum'] or 0
    return f"📊 <b>CASINO STATS</b>\n\n👥 Total Users: {total_users}\n💰 Wallet Liability: {total_liability} ETB\n\n<b>TODAY:</b>\n📥 Deposits: {deposits} ETB\n📤 Withdrawals: {withdrawals} ETB\n💵 Net: {deposits - withdrawals} ETB"

@sync_to_async
def get_and_mark_finished_rooms():
    close_old_connections()
    finished_rooms = list(GameRound.objects.filter(status="ENDED", winner_username__isnull=False))
    for room in finished_rooms:
        room.status = "ANNOUNCED"
        room.save(update_fields=['status'])
    return finished_rooms

@sync_to_async
def get_all_user_tg_ids():
    close_old_connections()
    ids = []
    for u in User.objects.filter(username__startswith='tg_'):
        try: ids.append(int(u.username.replace('tg_', '')))
        except: pass
    return ids

@sync_to_async
def change_user_name(target_tg_id, new_name):
    close_old_connections()
    try:
        user = User.objects.get(username=f"tg_{target_tg_id}")
        user.real_name = new_name
        user.save(update_fields=['real_name'])
        return True, f"Successfully changed user {target_tg_id}'s name to: {new_name}"
    except User.DoesNotExist:
        return False, "User not found."

@sync_to_async
def save_ghost_config(tier, min_cards, max_cards):
    close_old_connections()
    config_user, _ = User.objects.get_or_create(username=f"sys_ghost_{tier}")
    config_user.real_name = f"{min_cards},{max_cards}"
    config_user.save()
    return True

@sync_to_async
def adjust_user_balance(tg_id, amount, action="add"):
    close_old_connections()
    try:
        user = User.objects.get(username=f"tg_{tg_id}")
        amount = float(amount)
        if action == "add":
            user.operational_credit += amount
        elif action == "deduct":
            if user.operational_credit < amount:
                return False, f"User only has {user.operational_credit} ETB! Cannot deduct {amount} ETB."
            user.operational_credit -= amount
        
        user.save(update_fields=['operational_credit'])
        return True, f"Success! User {tg_id} balance is now: {user.operational_credit} ETB."
    except User.DoesNotExist:
        return False, "User not found in database."
    except ValueError:
        return False, "Invalid amount provided."

# ==========================================
# 4. BACKGROUND JOBS 
# ==========================================
async def broadcast_winners_task(context: ContextTypes.DEFAULT_TYPE):
    target_chats = ["@bigestbingo", "@bigestbingochat"]
    finished_rooms = await get_and_mark_finished_rooms()
    for room in finished_rooms:
        msg = (f"🏆 <b>Game #{room.id} Finished!</b>\n\n💰 Bet: {float(room.bet_amount):.2f} ETB\n👤 Winner: {room.winner_username.replace('tg_','')}\n🎁 Prize: {float(room.winner_prize):.2f} ETB\n\nPlay now: https://t.me/Bigestbingobot")
        for chat_id in target_chats:
            try: await context.bot.send_message(chat_id=chat_id, text=msg, parse_mode="HTML")
            except: pass

async def daily_promo_task(context: ContextTypes.DEFAULT_TYPE):
    channel_id = os.environ.get("CHANNEL_ID", "@bigestbingo")
    photo_url = "https://i.ibb.co/3m20B6k/bingo-money.jpg" 
    caption = "🎰 <b>BIGEST BINGO BOT</b> 🎰\n\nበየቀኑ በሺዎች የሚቆጠሩ ብሮችን ያሸንፉ!\nአሁኑኑ ይጫወቱ እና እድልዎን ይሞክሩ!"
    keyboard = [[InlineKeyboardButton("🎮 አሁኑኑ ይጫወቱ (PLAY NOW)", url="https://t.me/Bigestbingobot")]]
    reply_markup = InlineKeyboardMarkup(keyboard)
    try: await context.bot.send_photo(chat_id=channel_id, photo=photo_url, caption=caption, parse_mode="HTML", reply_markup=reply_markup)
    except Exception as e: print(f"Daily promo failed: {e}")

# ==========================================
# 5. USER FLOW COMMANDS
# ==========================================
async def send_main_menu(update: Update, context: ContextTypes.DEFAULT_TYPE, user):
    photo_url = "https://i.ibb.co/3m20B6k/bingo-money.jpg"
    caption = (f"🎰 <b>BIGEST BINGO BOT</b> 🎰\n\nእንኳን በደህና መጡ፣ <b>{user.real_name}</b>!\n💰 <b>ቀሪ ሂሳብ:</b> {user.operational_credit} ETB\n\nከታች ካሉት አማራጮች ውስጥ ይምረጡ:")

    tg_id = user.username.replace('tg_', '')
    
    # CASHIERS MENU (Restricted, but added /housewin and /broadcast)
    if is_admin(tg_id) and not is_boss(tg_id):
        caption += "\n\n👔 <b>Cashier Commands:</b>\n/pending | /approve [id] | /reject [id]\n/requestpromo [rm] [amt] (Max: 15)\n/housewin [room] 💀 (Stop a winning streak)\n/stats | /broadcast (Reply to msg)"
    
    # BOSS MENU (Full Power)
    elif is_boss(tg_id):
        caption += "\n\n👑 <b>Boss Commands:</b>\n/addadmin [id] | /removeadmin [id]\n/pending | /approve | /reject\n/addbal [id] | /subbal [id] | /forcewin\n/setname | /setghost [rm] [min] [max]\n/housewin [room] 💀\n/stats | /broadcast"
    
    base_url = "https://vladbingo-dmzg.onrender.com/api/live/?v=2.1"
    
    keyboard = [
        [InlineKeyboardButton("🎮 ጌም ይጫወቱ (Play)", web_app=WebAppInfo(url=base_url))],
        [InlineKeyboardButton("💰 ያስገቡ", web_app=WebAppInfo(url=base_url + "&tab=deposit")), InlineKeyboardButton("💸 ያውጡ", web_app=WebAppInfo(url=base_url + "&tab=withdraw"))],
        [InlineKeyboardButton("↔️ ያስተላልፉ", web_app=WebAppInfo(url=base_url + "&tab=transfer")), InlineKeyboardButton("👤 ፕሮፋይል", callback_data="profile")],
        [InlineKeyboardButton("📜 ታሪክ", web_app=WebAppInfo(url=base_url + "&tab=history")), InlineKeyboardButton("⚖️ ሂሳብ", callback_data="balance")],
        [InlineKeyboardButton("📢 ቻናል", url="https://t.me/bigestbingo"), InlineKeyboardButton("💬 ግሩፕ", url="https://t.me/bigestbingochat")]
    ]
    try: await context.bot.send_photo(chat_id=update.effective_chat.id, photo=photo_url, caption=caption, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode='HTML')
    except: await context.bot.send_message(chat_id=update.effective_chat.id, text=caption, reply_markup=InlineKeyboardMarkup(keyboard), parse_mode='HTML')

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    tg_id = update.effective_user.id
    user = await sync_to_async(db_op)(tg_id, "get")
    if not user.real_name:
        await sync_to_async(db_op)(tg_id, "state", "REG_NAME")
        return await context.bot.send_message(chat_id=update.effective_chat.id, text="👋 ወደ <b>BIGEST BINGO BOT</b> እንኳን በደህና መጡ!\n\nእባክዎ ትክክለኛ ሙሉ ስምዎን ያስገቡ (Please enter your Full Name):", parse_mode='HTML')
    if not user.phone_number:
        btn = [[KeyboardButton("📲 ስልክ ቁጥር ያጋሩ", request_contact=True)]]
        return await context.bot.send_message(chat_id=update.effective_chat.id, text="አካውንትዎን ለማረጋገጥ ከታች ያለውን ቁልፍ ይጫኑ:", reply_markup=ReplyKeyboardMarkup(btn, one_time_keyboard=True, resize_keyboard=True))
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
    await context.bot.send_message(chat_id=update.effective_chat.id, text="✅ ተረጋግጧል!", reply_markup=ReplyKeyboardRemove())
    await start(update, context)

async def handle_buttons(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    user = await sync_to_async(db_op)(query.from_user.id, "get")
    if query.data == "balance": await query.answer(f"💰 ቀሪ ሂሳብዎ: {user.operational_credit} ETB", show_alert=True)
    elif query.data == "profile":
        await context.bot.send_message(query.message.chat.id, f"👤 <b>ፕሮፋይል</b>\n🆔 ID: <code>{user.username.replace('tg_','')}</code>\n💰 Balance: {user.operational_credit} ETB", parse_mode="HTML")
        await query.answer()

# ==========================================
# 6. ADMIN COMMAND HANDLERS
# ==========================================

# --- BOSS ONLY COMMANDS ---
async def cmd_addadmin(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_boss(update.message.from_user.id): return
    try:
        new_admin_id = str(context.args[0])
        admins = cache.get('sub_admins_list', [])
        if new_admin_id not in admins: admins.append(new_admin_id); cache.set('sub_admins_list', admins, timeout=None)
        await update.message.reply_text(f"✅ User {new_admin_id} has been Hired as a Cashier!")
    except IndexError: await update.message.reply_text("⚠️ Usage: /addadmin <telegram_id>")

async def cmd_removeadmin(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_boss(update.message.from_user.id): return
    try:
        old_admin_id = str(context.args[0])
        admins = cache.get('sub_admins_list', [])
        if old_admin_id in admins: admins.remove(old_admin_id); cache.set('sub_admins_list', admins, timeout=None)
        await update.message.reply_text(f"🚫 User {old_admin_id} has been Fired.")
    except IndexError: await update.message.reply_text("⚠️ Usage: /removeadmin <telegram_id>")

async def cmd_forcewin(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_boss(update.message.from_user.id): return
    try:
        msg = await set_force_win(int(context.args[0]))
        await update.message.reply_text(f"🎯 {msg}")
    except: await update.message.reply_text("⚠️ Usage: /forcewin <card_number>\nUse 0 to clear.")

async def cmd_setname(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_boss(update.message.from_user.id): return
    try:
        success, msg = await change_user_name(context.args[0], " ".join(context.args[1:]))
        await update.message.reply_text(f"✅ {msg}" if success else f"⚠️ {msg}")
    except: await update.message.reply_text("⚠️ Usage: /setname <id> <name>")

async def cmd_setghost(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_boss(update.message.from_user.id): return
    try:
        tier, min_c, max_c = int(context.args[0]), int(context.args[1]), int(context.args[2])
        if tier not in [10, 20, 30, 40, 50, 100]: return await update.message.reply_text("⚠️ Invalid room!")
        await save_ghost_config(tier, min_c, max_c)
        await update.message.reply_text(f"✅ GHOST BOT UPDATED FOR ROOM {tier} ETB!\nNow buying {min_c}-{max_c} cards.")
    except: await update.message.reply_text("⚠️ Usage: /setghost <room> <min> <max>")

async def cmd_addbal(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_boss(update.message.from_user.id): return
    try:
        success, msg = await adjust_user_balance(context.args[0], context.args[1], "add")
        await update.message.reply_text(f"✅ {msg}" if success else f"⚠️ {msg}")
    except: await update.message.reply_text("⚠️ Usage: /addbal <id> <amount>")

async def cmd_subbal(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_boss(update.message.from_user.id): return
    try:
        success, msg = await adjust_user_balance(context.args[0], context.args[1], "deduct")
        await update.message.reply_text(f"✅ {msg}" if success else f"⚠️ {msg}")
    except: await update.message.reply_text("⚠️ Usage: /subbal <id> <amount>")

# --- GENERAL ADMIN COMMANDS (Boss & Cashiers) ---

async def cmd_requestpromo(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.message.from_user.id): return
    try:
        tier = int(context.args[0])
        amount = int(context.args[1])
        if tier not in [10, 20, 30, 40, 50, 100]: return await update.message.reply_text("⚠️ Invalid room!")
        if not is_boss(update.message.from_user.id) and amount > 15:
            return await update.message.reply_text("⚠️ You can only request up to 15 promo players.")
            
        msg_to_boss = (
            f"🔔 <b>PROMO REQUEST</b>\nCashier ID: <code>{update.message.from_user.id}</code>\nRoom: {tier} ETB\nRequested Players: {amount}\n\n"
            f"<i>Approve by tapping:</i>\n<code>/setghost {tier} {amount} {amount}</code>"
        )
        await context.bot.send_message(chat_id=BOSS_TG_ID, text=msg_to_boss, parse_mode="HTML")
        await update.message.reply_text("✅ Promo request sent to the Boss successfully!")
    except: await update.message.reply_text("⚠️ Usage: /requestpromo <room> <amount>")

async def cmd_pending(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.message.from_user.id): return
    txs = await get_pending_transactions()
    if not txs: return await update.message.reply_text("✅ No pending transactions!")
    msg = "📝 <b>PENDING:</b>\n"
    for tx in txs: msg += f"<b>ID:</b> <code>{tx.id}</code>\n<b>Type:</b> {tx.type}\n<b>Amount:</b> {tx.amount} ETB\n----------------\n"
    await update.message.reply_text(msg, parse_mode="HTML")

async def cmd_approve(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.message.from_user.id): return
    try:
        success, msg = await process_transaction(int(context.args[0]), "approved")
        await update.message.reply_text(f"✅ {msg}" if success else f"⚠️ {msg}")
    except: await update.message.reply_text("⚠️ Usage: /approve <tx_id>")

async def cmd_reject(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.message.from_user.id): return
    try:
        success, msg = await process_transaction(int(context.args[0]), "rejected")
        await update.message.reply_text(f"🚫 {msg}" if success else f"⚠️ {msg}")
    except: await update.message.reply_text("⚠️ Usage: /reject <tx_id>")

async def cmd_stats(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.message.from_user.id): return
    await update.message.reply_text(await get_casino_stats(), parse_mode="HTML")

# CHANGED: Now Cashiers CAN use this!
async def cmd_broadcast(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.message.from_user.id): return
    if not update.message.reply_to_message: return await update.message.reply_text("⚠️ You must REPLY to a message to broadcast.")
    target = update.message.reply_to_message
    tg_ids = await get_all_user_tg_ids()
    await update.message.reply_text(f"⏳ Sending to {len(tg_ids)} users...")
    sc = 0
    for tid in tg_ids:
        try: await context.bot.copy_message(chat_id=tid, from_chat_id=target.chat_id, message_id=target.message_id); sc += 1
        except: pass
    await update.message.reply_text(f"✅ Delivered to {sc} users!")

# CHANGED: Now Cashiers CAN use this!
async def cmd_housewin(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not is_admin(update.message.from_user.id): return
    try:
        tier = int(context.args[0])
        if tier not in [10, 20, 30, 40, 50, 100]: return await update.message.reply_text("⚠️ Invalid room!")
        cache.set(f'housewin_{tier}', True, timeout=120)
        await update.message.reply_text(f"💀 <b>BLOW REQUEST ACTIVATED!</b>\nRoom {tier} ETB will be terminated on the next ball.", parse_mode="HTML")
    except:
        await update.message.reply_text("⚠️ Usage: /housewin <room>")


# ==========================================
# 7. RUN BOT
# ==========================================
def run():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not token: return print("CRITICAL ERROR: TELEGRAM_BOT_TOKEN is missing!")
    app = Application.builder().token(token).post_init(lambda a: a.bot.delete_webhook(drop_pending_updates=True)).build()
    
    app.add_handler(CommandHandler("start", start))
    
    # Boss Only Commands
    app.add_handler(CommandHandler("setghost", cmd_setghost))
    app.add_handler(CommandHandler("addbal", cmd_addbal))
    app.add_handler(CommandHandler("subbal", cmd_subbal))
    app.add_handler(CommandHandler("addadmin", cmd_addadmin))
    app.add_handler(CommandHandler("removeadmin", cmd_removeadmin))
    app.add_handler(CommandHandler("forcewin", cmd_forcewin))
    app.add_handler(CommandHandler("setname", cmd_setname))

    # Cashier & Boss Commands
    app.add_handler(CommandHandler("requestpromo", cmd_requestpromo))
    app.add_handler(CommandHandler("pending", cmd_pending))
    app.add_handler(CommandHandler("approve", cmd_approve))
    app.add_handler(CommandHandler("reject", cmd_reject))
    app.add_handler(CommandHandler("stats", cmd_stats))
    app.add_handler(CommandHandler("broadcast", cmd_broadcast))
    app.add_handler(CommandHandler("housewin", cmd_housewin)) 
    
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    app.add_handler(MessageHandler(filters.CONTACT, handle_contact))
    app.add_handler(CallbackQueryHandler(handle_buttons))
    
    app.job_queue.run_repeating(broadcast_winners_task, interval=10, first=5)
    app.job_queue.run_repeating(daily_promo_task, interval=86400, first=60)
    
    print("🚀 BIGEST BINGO BOT & BROADCASTER ARE RUNNING...")
    app.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__": 
    run()