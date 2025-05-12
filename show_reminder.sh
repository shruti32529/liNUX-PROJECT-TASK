#!/bin/bash

TASK_TITLE="$1"
MINUTES="$2"

# Add a log to check if the script is being triggered
echo "$(date) - Reminder for $TASK_TITLE due in $MINUTES minutes" >> ~/reminder_log.txt

notify-send -u critical "Task Reminder!" "Your task \"$TASK_TITLE\" is due in $MINUTES minutes" -i appointment
zenity --warning --title="⏰ Task Reminder" --text="Your task \"$TASK_TITLE\" is due in $MINUTES minutes!" --width=300

