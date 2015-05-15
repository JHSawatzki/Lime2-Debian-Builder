#!/bin/bash
#
# Copyright (c) 2015 Jan Henrik Sawatzki, info@tm**.de
#
# Install libs for tmeslogger
#
# Should work with: Lime2
#
set -e

echo "Installing Labjack Exodriver..."
cd /root/exodriver
/bin/bash ./install.sh
cd /
rm -r /root/exodriver

echo "Installing Labjack python library..."
cd /root/LabJackPython
python setup.py install
cd /
rm -r /root/LabJackPython

echo "Installing pyA20Lime2..."
cd /root/pyA20Lime2-0.2.0
python setup.py install
cd /
rm -r /root/pyA20Lime2-0.2.0

rm /etc/adjtime

echo "Generating stronger Diffie-Hellman parameter..."
openssl dhparam -out /etc/nginx/dhparam.pem 4096

echo "Generating SSL cert..."
echo -e "DE\nNRW\nWuelfrath\nTMES UG\nIT\ninfo@tmes.de\n" | openssl req -x509 -newkey rsa:2048 -keyout /etc/nginx/nginx.ssl.key -out /etc/nginx/nginx.ssl.crt -days 3650 -nodes

echo "Generating cookie secret..."
SLIM_SECRET=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-32};echo;)
sed -e "/secret/c\                'secret' => '$SLIM_SECRET'," -i /usr/share/nginx/www/index.php

#Cron battery checker
echo '* *     * * *   root    /usr/local/tmeslogger/scripts/batteryChecker.sh' >> /etc/crontab

update-rc.d tmeslogger defaults >/dev/null 2>&1
update-rc.d ftppush defaults >/dev/null 2>&1