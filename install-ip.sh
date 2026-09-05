#!/bin/bash

# WizWiz IP Installer (no domain / no SSL / no webhook)
# IDEMPOTENT: safe to re-run. On re-run it:
#   - updates the bot files (git pull)
#   - reuses the existing database & baseInfo.php (or lets you reset)
#   - re-creates and restarts the poller service
#   - reuses the same web panel directory

# >>> If you have a personalized version (e.g. your own branding),
# >>> push it to your own GitHub repo and set REPO_URL below.
# >>> Leave it as the default to use the original wizwiz repo.
REPO_URL="https://github.com/wizwizdev/wizwizxui-timebot.git"

BOT_DIR="/var/www/html/wizwizxui-timebot"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "\033[33mPlease run as root\033[0m"
    exit
fi

echo -e "\e[32m
██     ██ ██ ███████ ██     ██ ██ ███████     ██   ██ ██    ██ ██
██     ██ ██    ███  ██     ██ ██    ███       ██ ██  ██    ██ ██
██  █  ██ ██   ███   ██  █  ██ ██   ███         ███   ██    ██ ██
██ ███ ██ ██  ███    ██ ███ ██ ██  ███         ██ ██  ██    ██ ██
 ███ ███  ██ ███████  ███ ███  ██ ███████     ██   ██  ██████  ██
\033[0m"
echo -e "    \e[31mWizWiz IP Installer (no domain needed) - re-runnable\033[0m\n"

echo -e "\e[32mInstalling WizWiz script ... \033[0m\n"
sleep 3

sudo apt update && apt upgrade -y
echo -e "\e[92mThe server was successfully updated ...\033[0m\n"

PKG=(
    lamp-server^
    libapache2-mod-php
    mysql-server
    apache2
    php-mbstring
    php-zip
    php-gd
    php-json
    php-curl
)

for i in "${PKG[@]}"
do
    dpkg -s $i &> /dev/null
    if [ $? -eq 0 ]; then
        echo "$i is already installed"
    else
        apt install $i -y
        if [ $? -ne 0 ]; then
            echo "Error installing $i"
            exit 1
        fi
    fi
done

echo -e "\n\e[92mPackages Installed Continuing ...\033[0m\n"

randomdbpasstxt69=$(openssl rand -base64 10 | tr -dc 'a-zA-Z0-9' | cut -c1-20)

echo 'phpmyadmin phpmyadmin/dbconfig-install boolean true' | debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password $randomdbpasstxt69" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/admin-pass password $randomdbpasstxt69" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password $randomdbpasstxt69" | debconf-set-selections
echo 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2' | debconf-set-selections
sudo apt-get install phpmyadmin -y
sudo ln -sf /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf
sudo a2enconf phpmyadmin.conf
sudo systemctl restart apache2

sudo apt-get install -y php-soap
sudo apt-get install libapache2-mod-php

sudo systemctl enable mysql.service
sudo systemctl start mysql.service
sudo systemctl enable apache2
sudo systemctl start apache2

echo -e "\n\e[92m Setting Up UFW...\033[0m\n"
ufw allow 'Apache'
sudo systemctl restart apache2

echo -e "\n\e[92mInstalling ...\033[0m\n"
sleep 1

sudo apt-get install -y git
sudo apt-get install -y wget
sudo apt-get install -y unzip
sudo apt install curl -y
sudo apt-get install -y php-ssh2
sudo apt-get install -y libssh2-1-dev libssh2-1

sudo systemctl restart apache2.service

# ============================================================
# Clone or UPDATE the bot
# ============================================================
if [ -d "$BOT_DIR/.git" ]; then
    echo -e "\e[92mUpdating existing bot files (git pull)...\033[0m"
    cd "$BOT_DIR" && git pull
    cd /
elif [ -d "$BOT_DIR" ]; then
    echo -e "\e[93mBot folder exists but is not a git repo. Re-cloning...\033[0m"
    rm -rf "$BOT_DIR"
    git clone "$REPO_URL" "$BOT_DIR"
else
    git clone "$REPO_URL" "$BOT_DIR"
fi
sudo chown -R www-data:www-data "$BOT_DIR/"
sudo chmod -R 755 "$BOT_DIR/"
echo -e "\n\033[33mWizWiz config and script have been installed successfully\033[0m"

# ============================================================
# Web panel (persist the random code so re-runs reuse the same dir)
# ============================================================
mkdir -p /root/confwizwiz
PANEL_CODE_FILE="/root/confwizwiz/panelcode.txt"
if [ -f "$PANEL_CODE_FILE" ] && [ -d "/var/www/html/$(cat "$PANEL_CODE_FILE")" ]; then
    RANDOM_CODE=$(cat "$PANEL_CODE_FILE")
    echo -e "\e[92mReusing existing web panel directory.\033[0m"
else
    RANDOM_CODE=$(LC_CTYPE=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 40)
    echo "$RANDOM_CODE" > "$PANEL_CODE_FILE"
    mkdir -p "/var/www/html/${RANDOM_CODE}"
    cd /var/www/html/
    wget -O wizwizpanel.zip https://github.com/wizwizdev/wizwizxui-timebot/releases/download/10.3.1/wizwizpanel.zip
    mv wizwizpanel.zip "/var/www/html/${RANDOM_CODE}/" && yes | unzip "/var/www/html/${RANDOM_CODE}/wizwizpanel.zip" -d "/var/www/html/${RANDOM_CODE}/" && rm "/var/www/html/${RANDOM_CODE}/wizwizpanel.zip"
    sudo chmod -R 755 "/var/www/html/${RANDOM_CODE}/"
    sudo chown -R www-data:www-data "/var/www/html/${RANDOM_CODE}/"
    cd /
fi

# ============================================================
# MySQL root password file
# ============================================================
if [ ! -d "/root/confwizwiz" ]; then
    sudo mkdir /root/confwizwiz
    sleep 1
    touch /root/confwizwiz/dbrootwizwiz.txt
    sudo chmod -R 777 /root/confwizwiz/dbrootwizwiz.txt
    sleep 1
    randomdbpasstxt=$(openssl rand -base64 10 | tr -dc 'a-zA-Z0-9' | cut -c1-30)
    ASAS="$"
    echo "${ASAS}user = 'root';" >> /root/confwizwiz/dbrootwizwiz.txt
    echo "${ASAS}pass = '${randomdbpasstxt}';" >> /root/confwizwiz/dbrootwizwiz.txt
    sleep 1
    passs=$(cat /root/confwizwiz/dbrootwizwiz.txt | grep '$pass' | cut -d"'" -f2)
    userrr=$(cat /root/confwizwiz/dbrootwizwiz.txt | grep '$user' | cut -d"'" -f2)
    sudo mysql -u $userrr -p$passs -e "alter user '$userrr'@'localhost' identified with mysql_native_password by '$passs';FLUSH PRIVILEGES;"
    echo "SELECT 1" | mysql -u$userrr -p$passs 2>/dev/null
    echo "Folder created successfully!"
else
    echo "Folder already exists."
fi

clear
echo " "
echo -e "\e[32m
██     ██ ██ ███████ ██     ██ ██ ███████     ███████ ███████ ██
██     ██ ██    ███  ██     ██ ██    ███      ██      ██      ██
██  █  ██ ██   ███   ██  █  ██ ██   ███       ███████ ███████ ██
██ ███ ██ ██  ███    ██ ███ ██ ██  ███        ██      ██      ██
 ███ ███  ██ ███████  ███ ███  ██ ███████     ███████ ███████ ██
\033[0m\n"

# Ask for the server IP (used for display; cron uses 127.0.0.1)
read -p "Enter your server IP (e.g. 1.2.3.4): " serverip
if [ "$serverip" = "" ]; then
    echo -e "\n\033[91mNo IP was entered. Aborting.\033[0m\n"
    exit
fi

# ============================================================
# Cron jobs (using http://127.0.0.1 - most reliable)
# ============================================================
(crontab -l 2>/dev/null; echo "* * * * * curl http://127.0.0.1/wizwizxui-timebot/settings/messagewizwiz.php >/dev/null 2>&1") | sort - | uniq - | crontab -
(crontab -l 2>/dev/null; echo "* * * * * curl http://127.0.0.1/wizwizxui-timebot/settings/rewardReport.php >/dev/null 2>&1") | sort - | uniq - | crontab -
(crontab -l 2>/dev/null; echo "* * * * * curl http://127.0.0.1/wizwizxui-timebot/settings/warnusers.php >/dev/null 2>&1") | sort - | uniq - | crontab -
(crontab -l 2>/dev/null; echo "* * * * * curl http://127.0.0.1/wizwizxui-timebot/settings/gift2all.php >/dev/null 2>&1") | sort - | uniq - | crontab -
(crontab -l 2>/dev/null; echo "*/3 * * * * curl http://127.0.0.1/wizwizxui-timebot/settings/tronChecker.php >/dev/null 2>&1") | sort - | uniq - | crontab -
(crontab -l 2>/dev/null; echo "* * * * * curl http://127.0.0.1/${RANDOM_CODE}/backupnutif.php >/dev/null 2>&1") | sort - | uniq - | crontab -

echo -e "\n\e[92m Setting Up Cron...\033[0m\n"

# Allow HTTP traffic (no SSL needed)
echo -e "\n\e[31mAllowing HTTP traffic...\033[0m\n"
sudo ufw allow 80
sudo ufw allow 443

wait

ROOT_PASSWORD=$(cat /root/confwizwiz/dbrootwizwiz.txt | grep '$pass' | cut -d"'" -f2)
ROOT_USER="root"
echo "SELECT 1" | mysql -u$ROOT_USER -p$ROOT_PASSWORD 2>/dev/null

if [ $? -eq 0 ]; then
    wait
    BASEINFO="$BOT_DIR/baseInfo.php"
    NEED_FRESH=0

    # --------------------------------------------------------
    # Re-install: try to reuse existing baseInfo.php
    # --------------------------------------------------------
    if [ -f "$BASEINFO" ]; then
        dbname=$(grep '\$dbName' "$BASEINFO" | cut -d"'" -f2)
        dbuser=$(grep '\$dbUserName' "$BASEINFO" | cut -d"'" -f2)
        dbpass=$(grep '\$dbPassword' "$BASEINFO" | cut -d"'" -f2)
        YOUR_BOT_TOKEN=$(grep '\$botToken' "$BASEINFO" | cut -d"'" -f2)
        YOUR_CHAT_ID=$(grep '\$admin' "$BASEINFO" | grep -o '[0-9]\+' | head -1)
        YOUR_IP=$(grep '\$botUrl' "$BASEINFO" | sed 's|.*http://||; s|/.*||')

        echo -e "\n\e[92mExisting configuration found - reusing it:\033[0m"
        echo -e "  Database : $dbname / $dbuser"
        echo -e "  Bot token: ${YOUR_BOT_TOKEN:0:12}..."
        echo -e "  Admin ID : $YOUR_CHAT_ID"
        echo -e "  Server IP: $YOUR_IP"
        read -p "Press Enter to continue, or type 'reset' to re-enter all values: " choice
        if [ "$choice" = "reset" ]; then
            rm -f "$BASEINFO"
            NEED_FRESH=1
        fi
    else
        NEED_FRESH=1
    fi

    # --------------------------------------------------------
    # Fresh setup (first install, or after 'reset')
    # --------------------------------------------------------
    if [ $NEED_FRESH -eq 1 ]; then
        randomdbpass=$(openssl rand -base64 10 | tr -dc 'a-zA-Z0-9' | cut -c1-22)
        randomdbdb=$(openssl rand -base64 10 | tr -dc 'a-zA-Z0-9' | cut -c1-22)
        dbname=wizwiz

        if [[ $(mysql -u root -p$ROOT_PASSWORD -e "SHOW DATABASES LIKE 'wizwiz'") ]]; then
            echo -e "\n\e[93mDatabase 'wizwiz' already exists - skipping creation.\033[0m"
            echo -e "\e[32mEnter the existing database username!\033[0m"
            read dbuser
            echo -e "\e[32mEnter the existing database password!\033[0m"
            read dbpass
            if [ "$dbuser" = "" ] || [ "$dbpass" = "" ]; then
                echo -e "\e[91mDatabase username and password are required. Aborting.\033[0m"
                exit
            fi
        else
            clear
            echo -e "\n\e[32mPlease enter the database username!\033[0m"
            printf "[+] Default user name is \e[91m${randomdbdb}\e[0m ( let it blank to use this user name ): "
            read dbuser
            if [ "$dbuser" = "" ]; then
            dbuser=$randomdbdb
            fi

            echo -e "\n\e[32mPlease enter the database password!\033[0m"
            printf "[+] Default password is \e[91m${randomdbpass}\e[0m ( let it blank to use this password ): "
            read dbpass
            if [ "$dbpass" = "" ]; then
            dbpass=$randomdbpass
            fi

            mysql -u root -p$ROOT_PASSWORD -e "CREATE DATABASE $dbname;" -e "CREATE USER '$dbuser'@'%' IDENTIFIED WITH mysql_native_password BY '$dbpass';GRANT ALL PRIVILEGES ON * . * TO '$dbuser'@'%';FLUSH PRIVILEGES;" -e "CREATE USER '$dbuser'@'localhost' IDENTIFIED WITH mysql_native_password BY '$dbpass';GRANT ALL PRIVILEGES ON * . * TO '$dbuser'@'localhost';FLUSH PRIVILEGES;"
            echo -e "\n\e[95mDatabase Created.\033[0m"
        fi

        wait
        printf "\n\e[33m[+] \e[36mBot Token: \033[0m"
        read YOUR_BOT_TOKEN
        printf "\e[33m[+] \e[36mChat id (admin): \033[0m"
        read YOUR_CHAT_ID
        printf "\e[33m[+] \e[36mServer IP (e.g. 1.2.3.4): \033[0m"
        read YOUR_IP
        echo " "
        if [ "$YOUR_BOT_TOKEN" = "" ] || [ "$YOUR_IP" = "" ] || [ "$YOUR_CHAT_ID" = "" ]; then
           echo -e "\e[91mAll fields are required. Aborting.\033[0m"
           exit
        fi
    fi

    ASAS="$"
    wait
    sleep 1

    # --------------------------------------------------------
    # Write baseInfo.php (always - so re-runs refresh it)
    # --------------------------------------------------------
    if [ -f "$BASEINFO" ]; then
      rm "$BASEINFO"
    fi
    echo -e "<?php" >> "$BASEINFO"
    echo -e "error_reporting(0);" >> "$BASEINFO"
    echo -e "${ASAS}botToken = '${YOUR_BOT_TOKEN}';" >> "$BASEINFO"
    echo -e "${ASAS}dbUserName = '${dbuser}';" >> "$BASEINFO"
    echo -e "${ASAS}dbPassword = '${dbpass}';" >> "$BASEINFO"
    echo -e "${ASAS}dbName = '${dbname}';" >> "$BASEINFO"
    echo -e "${ASAS}botUrl = 'http://${YOUR_IP}/wizwizxui-timebot/';" >> "$BASEINFO"
    echo -e "${ASAS}admin = ${YOUR_CHAT_ID};" >> "$BASEINFO"
    echo -e "?>" >> "$BASEINFO"
    sudo chown www-data:www-data "$BASEINFO"
    sudo chmod 644 "$BASEINFO"

    sleep 1

    # --------------------------------------------------------
    # Create the database tables (harmless if they already exist)
    # --------------------------------------------------------
    curl -s http://127.0.0.1/wizwizxui-timebot/createDB.php > /dev/null 2>&1

    sleep 1

    # --------------------------------------------------------
    # Create + (re)start the poller service (always)
    # --------------------------------------------------------
    cat > /etc/systemd/system/wizwiz-poller.service <<EOF
[Unit]
Description=WizWiz Telegram Bot Poller (IP mode)
After=network.target apache2.service

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/html/wizwizxui-timebot
ExecStart=/usr/bin/php /var/www/html/wizwizxui-timebot/poller.php
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable wizwiz-poller.service
    systemctl restart wizwiz-poller.service
    echo -e "\e[92mPoller service (re)started.\033[0m"

    # --------------------------------------------------------
    # Clean up install files (always)
    # --------------------------------------------------------
    sudo rm -r "$BOT_DIR/webpanel" 2>/dev/null
    sudo rm -r "$BOT_DIR/install" 2>/dev/null
    sudo rm -f "$BOT_DIR/createDB.php"
    rm -f "$BOT_DIR/updateShareConfig.php"
    rm -f "$BOT_DIR/README.md"
    rm -f "$BOT_DIR/README-fa.md"
    rm -f "$BOT_DIR/LICENSE"
    rm -f "$BOT_DIR/update.sh"
    rm -f "$BOT_DIR/wizwiz.sh"
    rm -f "$BOT_DIR/tempCookie.txt" 2>/dev/null
    rm -f "$BOT_DIR/settings/messagewizwiz.json" 2>/dev/null

    clear
    echo " "
    echo -e "\e[100mDatabase information:\033[0m"
    echo -e "\e[33mAddress: \e[36mhttp://${YOUR_IP}/phpmyadmin\033[0m"
    echo -e "\e[33mDatabase name: \e[36m${dbname}\033[0m"
    echo -e "\e[33mDatabase username: \e[36m${dbuser}\033[0m"
    echo -e "\e[33mDatabase password: \e[36m${dbpass}\033[0m"
    echo " "
    echo -e "\e[100mWizWiz panel:\033[0m"
    echo -e "\e[33mAddress: \e[36mhttp://${YOUR_IP}/${RANDOM_CODE}/login.php\033[0m"
    echo " "
    echo -e "\e[100mBot URL:\033[0m"
    echo -e "\e[33mhttp://${YOUR_IP}/wizwizxui-timebot/\033[0m"
    echo " "
    echo -e "\e[92m✅ Installation complete! The bot is now running in IP mode (no domain needed).\033[0m"
    echo -e "\e[94mCheck the poller status with: systemctl status wizwiz-poller\033[0m\n"
elif [ "$ROOT_PASSWORD" = "" ] || [ "$ROOT_USER" = "" ]; then
    echo -e "\n\e[36mThe password is empty.\033[0m\n"
else
    echo -e "\n\e[36mThe password is not correct.\033[0m\n"
fi
