Application specific Debian Wheezy builder with custom kernel for Olimex A20 Lime2 board

Based on [https://github.com/igorpecovnik/lib](https://github.com/igorpecovnik/lib) by Igor Pecovnik

Partial code and inspiration from [https://github.com/pullmoll/lib](https://github.com/pullmoll/lib) by Jürgen Buchmüller

License: GPLv2

1. SDK for ARM 
2. Use proven sources and configurations
3. Create SD image for Olimex Olinuxino Lime 2
4. Well documented, maintained & easy to use
5. Boot loaders and kernel images are compiled and cached.

```bash
sudo su -
mkdir -p tmeslogger-linux
cd tmeslogger-linux
touch build.sh
chmod +x build.sh
```

Add content to build.sh:

```bash
#!/bin/bash
#
# Edit and execute this script - Ubuntu 14.10 x64 recommended
#

MAINTAINER="Jan Henrik Sawatzki"			# deb signature
MAINTAINER_MAIL="info@tm**.de"				# deb signature
GPG_PASS=""

# numbers
SDSIZE="2048"								# SD image size in MB
REVISION="1.2"								# image release version
USEALLCORES="yes"							# Use all CPU cores for compiling

# kernel
KERNELBRANCH="sunxi"						# sunxi, mainline
KERNEL_TAG="v4.0.3"							# which kernel version - valid only for mainline
KERNEL_COMPILE="yes"						# force source compilation: yes / no
KERNEL_CONFIGURE="yes"						# want to change my default configuration
KERNEL_CLEAN="yes"							# run MAKE clean before kernel compilation
MODULES_SUNXI=""
MODULES_MAINLINE=""
KERNEL_ONLY="yes"							# only compile kernel and do nothing else

# u-boot
BOOT_COMPILE="yes"							# force source compilation: yes / no

# sunxi-tools
TOOLS_COMPILE="yes"							# force source compilation: yes / no

CREATE_ROOTFS="yes"							# force root fs creation

#tmeslogger
U6PRO="yes"

# user
DEST_LANG="en_US.UTF-8"						# en_US.UTF-8
TZDATA="UTC"								# Timezone
HOST="tmeslogger"							# hostname
ROOTPWD="tmeslogger"						# root password
MOTD_MSG="Welcome to TMESLogger!"


#---------------------------------------------------------------------------------------

# SRC is where we start the script
SRC=$(pwd)

# BUILDER is where the library is located
BUILDER=$SRC/Lime2-Debian-Builder

# get updates of the main build libraries
if [ -d "$BUILDER" ]; then
	# update builder
	cd $BUILDER
	git pull
	cd $SRC
else
	# download builder
	apt-get -y -qq install git
	git clone https://github.com/JHSawatzki/Lime2-Debian-Builder
fi

# execute builder
source $BUILDER/main.sh
#---------------------------------------------------------------------------------------
```

./build.sh