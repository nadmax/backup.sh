![test](https://github.com/nadmax/backup.sh/actions/workflows/test.yml/badge.svg)

# backup.sh

This script give you two options to backup your sensitive files:  
1. One-time backup
2. By scheduling a cronjob  

A config file is created so you don't have to ask about backup options again.  
⚠️ This means that you have to delete the config file if you want to make another backup.  

To run the script:
```bash
./backup.sh
```

For system files like ``/etc/shadow``, run the script with root privileges:  
```bash
sudo ./backup.sh
```