def check_win(board, called_numbers):
    called_set = set(called_numbers)
    # Checks for Full House (All numbers called)
    for col in board:
        for cell in col:
            if cell == "FREE": continue
            if cell not in called_set:
                return False
    return True
