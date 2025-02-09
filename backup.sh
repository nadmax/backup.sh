#!/bin/bash

CONFIG_FILE="backup_config"

run() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo "Loaded previous backup configuration."
    else
        echo "No previous configuration found."
    fi

    echo "Choose a backup option:"
    echo "1) One-time backup"
    echo "2) Schedule the backup via cron"
    echo "3) Exit"

    if [ -z "$backup_choice"] || [ $backup_choice -eq 3 ]; then
        read -p "Enter your choice (1-3): " backup_choice
    fi

    case $backup_choice in
        1) backup_files;;
        2) schedule_cronjob;;
        3) echo "Exiting...";;
        *) echo "Invalid option. Please choose between 1-3.";;
    esac
}

backup_files() {
    source "$CONFIG_FILE" 2>/dev/null

    if [ -z "$backup_dir" ]; then
        backup_dir=$(get_backup_directory)
        echo "backup_dir=\"$backup_dir\"" >> "$CONFIG_FILE"
    fi

    mount_backup_destination "$backup_dir"

    local selected_files=($(get_file_selection))

    if [ ${#selected_files[@]} -eq 0 ]; then
        echo "No valid selections. Exiting..."
        exit 1
    fi

    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir"
        echo "Created backup directory: $backup_dir"
    fi

    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_tar="$backup_dir/backup_$timestamp.tar.gz"

    create_backup_archive "$backup_tar" "${selected_files[@]}"
    encrypt_backup "$backup_tar"
}

schedule_cronjob() {
    if [ -z "$cron_time" ]; then
        backup_files
        read -p "Enter cronjob frequency (daily/weekly/monthly): " frequency

        case $frequency in
            daily) cron_time="0 2 * * *"  # Every day at 2 AM
                ;;
            weekly) cron_time="0 2 * * 0"  # Every Sunday at 2 AM
                ;;
            monthly) cron_time="0 2 1 * *"  # Every 1st of the month at 2 AM
                ;;
            *)
                echo "Invalid frequency: $frequency"
                exit 1
                ;;
        esac

        echo "cron_time=\"$cron_time\"" >> "$CONFIG_FILE"
    fi
    echo "Cron job frequency set to: $frequency"

    script_path=$(realpath "$0")
    cron_command="bash $script_path > /var/log/backup_$(date +"%Y%m%d_%H%M%S").log"
    cron_job="$cron_time $cron_command"

    (crontab -l; echo "$cron_job") | crontab -
    echo "✅ Cron job scheduled: $cron_job"

    if [[ "$encrypt_choice" == "y" || "$encrypt_choice" == "Y" ]]; then
        cron_mount_check="mount | grep -q '$backup_dir' || mount /dev/sdb1 '$backup_dir'"
        (crontab -l; echo "$cron_time $cron_mount_check && $cron_command") | crontab -
        echo "✅ Cron job updated to include mount check."
    fi
}

get_backup_directory() {
    read -p "Enter the backup directory: " backup_path

    echo "$backup_path"
}

mount_backup_destination() {
    local backup_dir="$1"

    while true; do 
        if ! mount | grep -q "$backup_dir"; then
            echo "Backup destination ($backup_dir) is not mounted."

            if [ -z $mount_choice ]; then
                read -p "Would you like to mount it? (y/n): " mount_choice
                echo "mount_choice=\"$mount_choice\"" >> "$CONFIG_FILE"
            fi

            case $mount_choice in
                y|Y)
                    echo "Available devices:"
                    lsblk -o NAME,SIZE,MOUNTPOINT | grep -v "MOUNTPOINT"

                    if [ -z $device ]; then
                        read -p "Enter the device you want to mount (e.g., /dev/sdb1): " device
                        echo "device=\"$device\"" >> "$CONFIG_FILE"
                    fi

                    if [ -b "$device" ]; then
                        if mount | grep -q "$device"; then
                            echo "$device is already mounted."
                            break
                        else
                            echo "Attempting to mount $device to $backup_dir..."
                            mount $device "$backup_dir"

                            if [ $? -ne 0 ]; then
                                echo "❌ Failed to mount $backup_dir. Exiting..."
                                exit 1
                            else
                                echo "✅ Mounted $device to $backup_dir successfully."
                            fi
                        fi
                    else
                        echo "❌ Invalid device: $device. Please try again."
                    fi
                    ;;
                n|N)
                    echo "No mounted backup destination selected. Backup will be done locally."
                    break
                    ;;
                *)
                    echo "Invalid option. Please enter 'y' for yes or 'n' for no."
                    exit 1
                    ;;
            esac
        else
            echo "✅ $backup_dir is already mounted."
            break
        fi
    done
}

get_file_selection() {
    local selected_files=()

    echo "Select the data you want to back up (separate choices with spaces):"
    echo "1) SSH keys (~/.ssh)"
    echo "2) System passwords (/etc/shadow, /etc/passwd)"
    echo "3) Shell configs (~/.bashrc, ~/.zshrc)"
    echo "4) Git config (~/.gitconfig)"
    echo "5) Network settings (/etc/hosts, /etc/resolv.conf)"
    echo "6) Secure app configs (~/.config, ~/.mozilla, ~/.google-chrome)"
    echo "7) Logs & history (~/.bash_history, /var/log/auth.log)"
    echo "8) SSL & GPG keys (/etc/ssl/private, ~/.gnupg)"
    echo "9) Everything above"

    if [ -z "$data_choices" ]; then
        read -p "Enter your choices (e.g., 1 3 5): " data_choices
        echo "data_choices=\"$data_choices\"" >> "$CONFIG_FILE"
    fi

    for choice in $choices; do
        case $choice in
            1) selected_files+=("$HOME/.ssh") ;;
            2) selected_files+=("/etc/shadow" "/etc/passwd") ;;
            3) selected_files+=("$HOME/.bashrc" "$HOME/.zshrc") ;;
            4) selected_files+=("$HOME/.gitconfig") ;;
            5) selected_files+=("/etc/hosts" "/etc/resolv.conf") ;;
            6) selected_files+=("$HOME/.config" "$HOME/.mozilla" "$HOME/.google-chrome") ;;
            7) selected_files+=("$HOME/.bash_history" "/var/log/auth.log") ;;
            8) selected_files+=("/etc/ssl/private" "$HOME/.gnupg") ;;
            9) selected_files=("$HOME/.ssh" "/etc/shadow" "/etc/passwd" "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.gitconfig" "/etc/hosts" "/etc/resolv.conf" "$HOME/.config" "$HOME/.mozilla" "$HOME/.google-chrome" "$HOME/.bash_history" "/var/log/auth.log" "/etc/ssl/private" "$HOME/.gnupg") ;;
            *) echo "Invalid choice: $choice" ;;
        esac
    done

    echo "${selected_files[@]}"
}

create_backup_archive() {
    local backup_tar="$1"
    shift
    local files=("$@")

    echo "Creating backup archive..."
    tar -czf "$backup_tar" "${files[@]}" 2>/dev/null

    if [ -f "$backup_tar" ]; then
        echo "✅ Backup created: $backup_tar"
    else
        echo "❌ Backup failed!"
        exit 1
    fi
}

encrypt_backup() {
    local backup_tar="$1"
    local backup_encrypted="$1.gpg"

    if [ -z "$encrypt_choice" ]; then
        read -p "Do you want to encrypt the backup? (y/n): " encrypt_choice
        echo "encrypt_choice=\"$encrypt_choice\"" >> "$CONFIG_FILE"
    fi

    if [[ "$encrypt_choice" == "y" || "$encrypt_choice" == "Y" ]]; then
        echo "🔐 Encrypting backup..."
        gpg --symmetric --cipher-algo AES256 "$backup_tar"

        if [ -f "$backup_encrypted" ]; then
            echo "✅ Backup encrypted successfully: $backup_encrypted"
            rm -f "$backup_tar"
        else
            echo "❌ Encryption failed!"
        fi
    else
        echo "Backup created without encryption."
    fi
}

run