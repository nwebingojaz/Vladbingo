#!/usr/bin/env python
import os, sys
from pathlib import Path

# Anchor: Add the current folder to the Python path
current_path = Path(__file__).resolve().parent
sys.path.append(str(current_path))

if __name__ == "__main__":
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "vlad_bingo.settings")
    from django.core.management import execute_from_command_line
    execute_from_command_line(sys.argv)
