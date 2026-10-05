#!/bin/bash
# Pop a system folder-selection dialog and print the chosen absolute path to
# stdout (nothing on cancel). Used by the stash LocalSend "choose location"
# button for a one-off download destination override.
# Usage: localsend_pickdir.sh [start-dir]

START="${1:-$HOME}"

if command -v zenity >/dev/null 2>&1; then
    zenity --file-selection --directory --title="Save received files to…" \
           --filename="$START/"
elif command -v kdialog >/dev/null 2>&1; then
    kdialog --getexistingdirectory "$START"
elif command -v qarma >/dev/null 2>&1; then
    qarma --file-selection --directory --title="Save received files to…" \
          --filename="$START/"
elif command -v yad >/dev/null 2>&1; then
    yad --file --directory --title="Save received files to…" \
        --filename="$START/"
else
    exit 1
fi
