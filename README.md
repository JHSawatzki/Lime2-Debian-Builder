Based on [https://github.com/igorpecovnik/lib](https://github.com/igorpecovnik/lib) by Igor Pecovnik

1. SDK for ARM 
2. Use proven sources and configurations
3. Create SD image for Olimex Lime 2
4. Well documented, maintained & easy to use
5. Boot loaders and kernel images are compiled and cached.

```bash
sudo su -

#!/bin/bash
# 
# Edit and execute this script - Ubuntu 14.04 x86/64 recommended
#

BOARD="lime2"								# lime (512Mb), lime2 (1024Mb), micro (1024Mb)
DISTRIBUTION="Debian"						# Debian or Ubuntu
RELEASE="wheezy"							# jessie or wheezy
BRANCH="3.4.x"								# default=3.4.x, mainline=next
HOST="tmeslogger"							# hostname

# numbers
SDSIZE="1200"								# SD image size in MB
REVISION="1.1"								# image release version

# method
SOURCE_COMPILE="yes"						# force source compilation: yes / no
KERNEL_CONFIGURE="yes"						# want to change my default configuration
KERNEL_CLEAN="yes"							# run MAKE clean before kernel compilation
USEALLCORES="yes"							# Use all CPU cores for compiling
   
# user 
DEST_LANG="en_US.UTF-8"						# en_US.UTF-8
TZDATA="UTC"								# Timezone
ROOTPWD="****"								# Must be changed @first login
MAINTAINER="JH Sawatzki"					# deb signature
MAINTAINERMAIL="info@****.de"				# deb signature
    
# advanced
KERNELTAG="v3.19"							# which kernel version - valid only for mainline

#tmeslogger
TMESLOGGER_INSTALL="yes"
U6PRO="yes"

#---------------------------------------------------------------------------------------

# source is where we start the script
SRC=$(pwd)

# destination
DEST=$(pwd)/output

# get updates of the main build libraries
if [ -d "$SRC/Lime2-Debian-Builder" ]; then
	cd $SRC/Lime2-Debian-Builder
	git pull
else
	# download SDK
	apt-get -y -qq install git
	git clone https://github.com/JHSawatzki/Lime2-Debian-Builder
fi

source $SRC/Lime2-Debian-Builder/main.sh
#---------------------------------------------------------------------------------------
```