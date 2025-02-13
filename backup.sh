#!/bin/bash

CONFIG_FILE="backup_config"

run() {
    if [ -f $CONFIG_FILE ]; then
        source $CONFIG_FILE
        printf "Load previous backup configuration\n"
    else
        printf "No previous backup configuration found"
        read -p $'\nWould you like your choices to be saved? (y/n) ' save_config

        case $save_config in
            y|Y)
                touch $CONFIG_FILE
                printf "Your choices will be saved in %s\n" $CONFIG_FILE
                ;;
            n|N) ;;
            *)
                echo "Invalid choice: $save_config"
                exit 1
                ;;
        esac

        printf "\nChoose a backup option:\n"
        echo "1) One-time backup"
        echo "2) Schedule the backup via cron"
        echo "3) Exit"
    fi

    if [ -z "$backup_option" ]; then
        read -p "Enter your choice (1-3): " backup_option
    fi

    case $backup_option in
        1)  save_config_option "backup_option" "$backup_option"
            backup_files
            ;;
        2)  save_config_option "backup_option" "1"
            schedule_cronjob
            ;;
        3) echo "Exiting...";;
        *) echo "Invalid choice. Please choose between 1-3.";;
    esac
}

backup_files() {
    if [ -z "$backup_dir" ]; then
        backup_dir=$(get_backup_directory)
        save_config_option "backup_dir" "$backup_dir"
    fi

    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir"
        printf "✅ Created backup directory: %s\n\n" $backup_dir
    else
        printf "\nBackup directory %s already exists\n" $backup_dir
    fi


    mount_backup_directory "$backup_dir"

    local selected_files=()

    echo "Select the data you want to back up (separate options with spaces):"
    echo "1) SSH keys (~/.ssh)"
    echo "2) System passwords (/etc/shadow, /etc/passwd)"
    echo "3) Shell configs (~/.bashrc, ~/.zshrc)"
    echo "4) Git config (~/.gitconfig)"
    echo "5) Network settings (/etc/hosts, /etc/resolv.conf)"
    echo "6) Secure app configs (~/.config, ~/.mozilla, ~/.google-chrome)"
    echo "7) Logs & history (~/.bash_history, /var/log/auth.log)"
    echo "8) SSL & GPG keys (/etc/ssl/private, ~/.gnupg)"
    echo "9) Systemd services (/etc/systemd/system, /lib/systemd/system, ~/.config/systemd/user)"
    echo "10) Init.d services (/etc/init.d, /etc/rc*.d)"
    echo "11) Everything above including services"


    if [ -z "$data_options" ]; then
        read -p $'\nEnter your choices (e.g., 1 3 5): ' data_options
    fi

    for option in $data_options; do
        case $option in
            1)  selected_files+=("$HOME/.ssh") ;;
            2)  selected_files+=("/etc/shadow" "/etc/passwd") ;;
            3)  selected_files+=("$HOME/.bashrc" "$HOME/.zshrc") ;;
            4)  selected_files+=("$HOME/.gitconfig") ;;
            5)  selected_files+=("/etc/hosts" "/etc/resolv.conf") ;;
            6)  selected_files+=("$HOME/.config" "$HOME/.mozilla" "$HOME/.google-chrome") ;;
            7)  selected_files+=("$HOME/.bash_history" "/var/log/auth.log") ;;
            8)  selected_files+=("/etc/ssl/private" "$HOME/.gnupg") ;;
            9)  selected_files+=("/etc/systemd/system" "/lib/systemd/system" "$HOME/.config/systemd/user") ;;
            9)  selected_files+=("$HOME/.ssh" "/etc/shadow" "/etc/passwd" "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.gitconfig" "/etc/hosts" "/etc/resolv.conf" "$HOME/.config" "$HOME/.mozilla" "$HOME/.google-chrome" "$HOME/.bash_history" "/var/log/auth.log" "/etc/ssl/private" "$HOME/.gnupg") ;;
            10) selected_files+=("/etc/init.d" "/etc/rc*.d") ;;
            11) selected_files+=(
                    "$HOME/.ssh" "/etc/shadow" "/etc/passwd"
                    "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.gitconfig"
                    "/etc/hosts" "/etc/resolv.conf" "$HOME/.config"
                    "$HOME/.mozilla" "$HOME/.google-chrome"
                    "$HOME/.bash_history" "/var/log/auth.log"
                    "/etc/ssl/private" "$HOME/.gnupg"
                    "/etc/systemd/system" "/lib/systemd/system" "$HOME/.config/systemd/user"
                    "/etc/init.d" "/etc/rc*.d"
                ) ;;
            *) echo "Invalid choice: $option" ;;
        esac
    done

    save_config_option "data_options" "$data_options"

    if [ ${#selected_files[@]} -eq 0 ]; then
        echo "No valid selections. Exiting..."
        exit 1
    fi

    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_tar="$backup_dir/backup_$timestamp.tar.gz"

    create_backup_archive "$backup_tar" "${selected_files[@]}"
    encrypt_backup "$backup_tar"
}

schedule_cronjob() {
    if [ -z "$cron_frequency" ]; then
        read -p "Enter cronjob frequency (daily/weekly/monthly): " cron_frequency
    fi

    case $cron_frequency in
        daily) cron_time="0 2 * * *"  # Every day at 2 AM
            ;;
        weekly) cron_time="0 2 * * 0"  # Every Sunday at 2 AM
            ;;
        monthly) cron_time="0 2 1 * *"  # Every 1st of the month at 2 AM
            ;;
        *)
            echo "Invalid frequency: $cron_frequency"
            exit 1
            ;;
    esac

    save_config_option "cron_frequency" "$cron_frequency"
    printf "Cron job frequency set to: %s\n" $cron_frequency

    script_path="$HOME/backup.sh/backup.sh"
    cron_command="bash $script_path > /var/log/backup_$(date +"%Y%m%d_%H%M%S").log"
    cron_job="$cron_time $cron_command"

    (crontab -l; echo "$cron_job") | crontab -
    echo "✅ Cron job scheduled: $cron_job"

    if [[ "$encrypt_option" == "y" || "$encrypt_option" == "Y" ]]; then
        cron_mount_check="mount | grep -q '$backup_dir' || mount /dev/sdb1 '$backup_dir'"
        (crontab -l; echo "$cron_time $cron_mount_check &-& $cron_command") | crontab -
        echo "✅ Cron job updated to include mount check."
    fi
}

get_backup_directory() {
    read -p $'\nEnter the backup directory: ' backup_path

    echo "$backup_path"
}

mount_backup_directory() {
    local backup_dir="$1"

    while true; do 
        if ! mount | grep -q "$backup_dir"; then
            printf "\nBackup directory (%s) is not mounted.\n" $backup_dir

            if [ -z $mount_option ]; then
                read -p "Would you like to mount it? (y/n): " mount_option
            fi

            case $mount_option in
                y|Y)
                    save_config_option "mount_option" "$mount_option"
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
                        sed -i '/device=/d' $CONFIG_FILE
                        exit 1
                    fi
                    ;;
                n|N)
                    save_config_option "mount_option" "$mount_option"
                    printf "No mounted backup directory option selected. Backup will be done locally.\n\n"
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

create_backup_archive() {
    local backup_tar="$1"
    shift
    local files=("$@")

    tar -czf "$backup_tar" "${files[@]}" 2>/dev/null

    if [ -f "$backup_tar" ]; then
        printf "✅ Backup created: %s\n" $backup_tar
    else
        echo "❌ Backup failed!"
        rm -f $CONFIG_FILE
        exit 1
    fi
}

encrypt_backup() {
    local backup_tar="$1"
    local backup_encrypted="$1.gpg"

    if [ -z "$encrypt_option" ]; then
        read -p $'\nWould you like to encrypt the backup? (y/n): ' encrypt_option
        save_config_option "encrypt_option" "$encrypt_option"
    fi

    if [[ "$encrypt_option" == "y" || "$encrypt_option" == "Y" ]]; then
        echo "🔐 Encrypting backup..."
        gpg --symmetric --cipher-algo AES256 "$backup_tar"

        if [ -f "$backup_encrypted" ]; then
            echo "✅ Backup encrypted successfully: $backup_encrypted"
            rm -f "$backup_tar"
        else
            echo "❌ Encryption failed!"
        fi
    else
        echo "✅ Backup created without encryption."
    fi
}

save_config_option() {
    local option_name="$1"
    local option_value="$2"

    if [ -f "$CONFIG_FILE" ] && ! grep -q "$option_name" "$CONFIG_FILE"; then
        echo "$option_name=$option_value" >> $CONFIG_FILE
    fi
}

run