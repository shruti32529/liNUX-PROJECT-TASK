#!/bin/bash

TASK_FILE="$HOME/.task_scheduler_tasks.txt"
CRON_FILE="$HOME/.task_scheduler_cron.txt"

add_task() {
    task_title=$(zenity --entry --title="Add New Task" --text="Enter task title:")
    if [[ -z "$task_title" ]]; then
        zenity --error --text="Task title cannot be empty."
        return
    fi

    task_description=$(zenity --entry --title="Task Description" --text="Enter task description (Optional):")
    not_date=$(zenity --calendar --title="Select Deadline Date" --date-format="%Y-%m-%d")
    if [[ -z "$not_date" ]]; then
        zenity --error --text="Deadline date must be selected."
        return
    fi

    not_time=$(zenity --entry --title="Deadline Time" --text="Enter deadline time (24-hour format HH:MM):" --entry-text="09:00")
    if ! [[ "$not_time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        zenity --error --text="Invalid time format. Please use HH:MM (24-hour)."
        return
    fi

    task_priority=$(zenity --list --title="Task Priority" --text="Select Task Priority" --radiolist --column="Select" --column="Priority" TRUE "Low" FALSE "Medium" FALSE "High")

    case "$task_priority" in
        "High") remind_min=30 ;;
        "Medium") remind_min=15 ;;
        "Low") remind_min=5 ;;
        *) remind_min=10 ;;
    esac

    deadline_epoch=$(date -d "$not_date $not_time" +%s)
    reminder_epoch=$((deadline_epoch - remind_min*60))
    now_epoch=$(date +%s)

    if (( reminder_epoch <= now_epoch )); then
        zenity --error --text="Reminder time is in the past."
        return
    fi

    reminder_date=$(date -d "@$reminder_epoch" "+%Y-%m-%d")
    reminder_time=$(date -d "@$reminder_epoch" "+%H:%M")

    task_id=$(date +%s%N | sha256sum | head -c 10)

    echo "$task_id | $task_title | $task_description | $not_date $not_time | $task_priority | Reminder $remind_min min before" >> "$TASK_FILE"

    # ✅ Save to tasks.txt (user's file)
    echo "$task_title | $task_description | $not_date $not_time | $task_priority" >> "$HOME/tasks.txt"

    schedule_notification "$task_id" "$task_title" "$reminder_date" "$reminder_time" "$remind_min"
    zenity --info --text="✅ Task added!"
}

schedule_notification() {
    task_id=$1
    task_title=$2
    not_date=$3
    not_time=$4
    remind_min=$5

    minute=$(echo "$not_time" | cut -d':' -f2)
    hour=$(echo "$not_time" | cut -d':' -f1)
    day=$(echo "$not_date" | cut -d'-' -f3)
    month=$(echo "$not_date" | cut -d'-' -f2)

    script_path="$HOME/show_reminder.sh"
    if [[ ! -x "$script_path" ]]; then
        zenity --error --text="Reminder script not found or not executable at $script_path"
        return
    fi

    safe_title=$(echo "$task_title" | sed 's/"/\\"/g')
    cron_command="$minute $hour $day $month * export DISPLAY=:0; export XDG_RUNTIME_DIR=/run/user/$(id -u); $script_path \"$safe_title\" \"$remind_min\" #$task_id"

    echo "$task_id | $cron_command" >> "$CRON_FILE"
    (crontab -l 2>/dev/null; echo "$cron_command") | crontab -

    if crontab -l | grep -q "$task_id"; then
        zenity --info --text="✅ Reminder scheduled for $not_date at $not_time"
    else
        zenity --error --text="❌ Failed to schedule reminder. Check permissions."
    fi
}

view_tasks() {
    if [[ -f "$TASK_FILE" && -s "$TASK_FILE" ]]; then
        task_list=$(awk -F' \\| ' '{print "ID: "$1"\nTask: "$2"\nDescription: "$3"\nDeadline: "$4"\nPriority: "$5"\n"($6 ? $6 : "")"\n------------------"}' "$TASK_FILE")
        zenity --text-info --title="📋 Your Tasks" --width=600 --height=400 --editable --filename=<(echo "$task_list")
    else
        zenity --info --text="📭 No tasks found."
    fi
}

search_task() {
    search_term=$(zenity --entry --title="Search Tasks" --text="Enter task title or description to search:")
    if [[ -z "$search_term" ]]; then
        zenity --error --text="Please enter a search term."
        return
    fi
    if [[ -f "$TASK_FILE" && -s "$TASK_FILE" ]]; then
        search_results=$(grep -i "$search_term" "$TASK_FILE")
        if [[ -z "$search_results" ]]; then
            zenity --info --text="🔍 No tasks found matching '$search_term'."
        else
            zenity --text-info --title="🔍 Search Results" --width=600 --height=400 --editable --filename=<(echo "$search_results")
        fi
    else
        zenity --info --text="📭 No tasks found."
    fi
}

view_schedule() {
    if [[ -f "$CRON_FILE" && -s "$CRON_FILE" ]]; then
        cron_list=$(awk -F' \\| ' '{print "ID: "$1"\nCron: "$2"\n------------------"}' "$CRON_FILE")
        zenity --text-info --title="🔔 Your Scheduled Reminders" --width=600 --height=400 --editable --filename=<(echo "$cron_list")
    else
        zenity --info --text="🔕 No reminders scheduled."
    fi
}

delete_task() {
    if [[ -f "$TASK_FILE" && -s "$TASK_FILE" ]]; then
        task_list=$(awk -F' \\| ' '{print $1 "|" $2}' "$TASK_FILE")
        selected=$(echo "$task_list" | zenity --list --title="Delete Task" --text="Select task:" --column="ID" --column="Task" --width=600 --height=300)

        if [[ -n "$selected" ]]; then
            grep -v "^$selected" "$TASK_FILE" > temp_tasks.txt && mv temp_tasks.txt "$TASK_FILE"
            if [[ -f "$CRON_FILE" ]]; then
                grep -v "^$selected" "$CRON_FILE" > temp_cron.txt && mv temp_cron.txt "$CRON_FILE"
                current_crontab=$(crontab -l 2>/dev/null | grep -v "$selected")
                echo "$current_crontab" | crontab -
            fi
            zenity --info --text="✅ Task deleted!"
        fi
    else
        zenity --info --text="📭 No tasks found."
    fi
}

delete_all_tasks() {
    zenity --question --text="⚠ Delete all tasks and reminders?"
    if [[ $? -eq 0 ]]; then
        > "$TASK_FILE"
        > "$CRON_FILE"
        > "$HOME/tasks.txt"
        current_crontab=$(crontab -l 2>/dev/null | grep -v "show_reminder.sh")
        echo "$current_crontab" | crontab -
        zenity --info --text="🗑 All tasks deleted!"
    fi
}

complete_task() {
    if [[ -f "$TASK_FILE" && -s "$TASK_FILE" ]]; then
        task_list=$(grep -v "^COMPLETED" "$TASK_FILE" | awk -F' \\| ' '{print $1 "|" $2}')
        if [[ -z "$task_list" ]]; then
            zenity --info --text="🎉 No pending tasks."
            return
        fi

        selected=$(echo "$task_list" | zenity --list --title="Complete Task" --text="Mark as complete:" --column="ID" --column="Task" --width=600 --height=300)
        if [[ -n "$selected" ]]; then
            task_line=$(grep "^$selected" "$TASK_FILE")
            grep -v "^$selected" "$TASK_FILE" > temp_tasks.txt
            echo "COMPLETED: $task_line ✓" >> temp_tasks.txt
            mv temp_tasks.txt "$TASK_FILE"

            if [[ -f "$CRON_FILE" ]]; then
                grep -v "^$selected" "$CRON_FILE" > temp_cron.txt && mv temp_cron.txt "$CRON_FILE"
                current_crontab=$(crontab -l 2>/dev/null | grep -v "$selected")
                echo "$current_crontab" | crontab -
            fi

            zenity --info --text="🎉 Task marked completed!"
        fi
    else
        zenity --info --text="📭 No tasks found."
    fi
}

create_reminder_script() {
    script_path="$HOME/show_reminder.sh"
    if [[ ! -f "$script_path" ]]; then
        cat > "$script_path" << 'EOL'
#!/bin/bash

TASK_TITLE="$1"
MINUTES="$2"

notify-send -u critical "Task Reminder!" "Your task \"$TASK_TITLE\" is due in $MINUTES minutes" -i appointment

zenity --warning --title="⏰ Task Reminder" --text="Your task \"$TASK_TITLE\" is due in $MINUTES minutes!" --width=300
EOL
        chmod +x "$script_path"
        zenity --info --text="✅ Created reminder script at $script_path"
    fi
}

main_menu() {
    create_reminder_script
    while true; do
        choice=$(zenity --list --title="🗂 Task Scheduler" --text="Choose an option:" \
            --column="Option" --column="Action" \
            "1" "Add Task" \
            "2" "View Tasks" \
            "3" "Search Task" \
            "4" "Update Task" \
            "5" "Complete Task" \
            "6" "Delete Task" \
            "7" "Delete All Tasks" \
            "8" "View Scheduled Reminders" \
            "9" "Exit" \
            --width=400 --height=450)

        case "$choice" in
            "1") add_task ;;
            "2") view_tasks ;;
            "3") search_task ;;
            "4") update_task ;;
            "5") complete_task ;;
            "6") delete_task ;;
            "7") delete_all_tasks ;;
            "8") view_schedule ;;
            "9") break ;;
            *) break ;;
        esac
    done
}

main_menu

