#!/bin/bash
#
# Based on the original work of Igor Pecovnik:
# Copyright (c) 2014 Igor Pecovnik, igor.pecovnik@gma**.com
#
# Portions Copyright (c) 2015 Jan Henrik Sawatzki, info@tm**.de
#
# Image build functions
#

#--------------------------------------------------------------------------------------------------------------------------------
# Execute a command in the SDCARD chroot
#--------------------------------------------------------------------------------------------------------------------------------
chroot_sdcard () {
	chroot $SDCARD /bin/bash -c "$@"
}

#--------------------------------------------------------------------------------------------------------------------------------
# Execute a command in the SDCARD chroot avoid locale issues
#--------------------------------------------------------------------------------------------------------------------------------
chroot_sdcard_lang () {
	LC_ALL=C LANG=C LANGUAGE=C chroot $SDCARD /bin/bash -c "$@"
}


#--------------------------------------------------------------------------------------------------------------------------------
# Download packages for host - Ubuntu 14.10 recommended
#--------------------------------------------------------------------------------------------------------------------------------
download_host_packages () {
	apt-get -y -qq install debconf-utils

	debconf-apt-progress -- apt-get -y install pv bc lzop zip binfmt-support bison build-essential ccache debootstrap flex gawk
	debconf-apt-progress -- apt-get -y install gcc-arm-linux-gnueabihf lvm2 qemu-user-static u-boot-tools uuid-dev zlib1g-dev unzip
	debconf-apt-progress -- apt-get -y install libusb-1.0-0 libusb-1.0-0-dev parted pkg-config expect gcc-arm-linux-gnueabi libncurses5-dev sqlite3
}


#--------------------------------------------------------------------------------------------------------------------------------
# Download sources from Github
#--------------------------------------------------------------------------------------------------------------------------------
fetch_from_github () {
	echo "------ Downloading $2."
	if [ -d "$SOURCES/$2" ]; then
		cd $SOURCES/$2
		git pull
		cd $SRC
	else
		git clone $1 $SOURCES/$2
	fi
}


#--------------------------------------------------------------------------------------------------------------------------------
# Patching sources
#--------------------------------------------------------------------------------------------------------------------------------
patching_sources() {
	# kernel
	cd $SOURCES/$LINUXSOURCE

	# mainline
	if [[ $KERNEL_BRANCH == "mainline" ]]; then
		# Fix Kernel Tag
		if [[ $KERNEL_TAG == "" ]]; then
			git checkout master
		else
			git checkout $KERNEL_TAG
		fi

		# install custom dts for lime2
		if [ "$(patch --dry-run -t -p1 < $BUILDER/patch/sun7i-a20-olinuxino-lime2.dts.patch | grep previ)" == "" ]; then
			patch -p1 < $BUILDER/patch/sun7i-a20-olinuxino-lime2.dts.patch
		fi

		# install device tree blobs in linux-image package
		if [ "$(patch --dry-run -t -p1 < $BUILDER/patch/packaging-next.patch | grep previ)" == "" ]; then
			patch -p1 < $BUILDER/patch/packaging-next.patch
		fi
	#sunxi
	else
		# if the source is already patched for banana, do reverse GMAC patch
		if [ "$(cat arch/arm/kernel/setup.c | grep BANANAPI)" != "" ]; then
			echo "Reversing Banana patch"
			patch --batch -t -p1 < $BUILDER/patch/bananagmac.patch
		fi

		# deb packaging patch
		if [ "$(patch --dry-run -t -p1 < $BUILDER/patch/packaging.patch | grep previ)" == "" ]; then
			patch --batch -f -p1 < $BUILDER/patch/packaging.patch
		fi

		# gpio patch
		if [ "$(patch --dry-run -t -p1 < $BUILDER/patch/gpio.patch | grep previ)" == "" ]; then
			patch --batch -f -p1 < $BUILDER/patch/gpio.patch
		fi

		# I2C functionality for lime2
		if [ "$(patch --dry-run -t -p1 < $BUILDER/patch/i2c.patch | grep previ)" == "" ]; then
			patch --batch -f -p1 < $BUILDER/patch/i2c.patch
		fi

		# Temperature reading from A20 chip
		if [ "$(patch --dry-run -t -p1 < $BUILDER/patch/a20-temp.patch | grep previ)" == "" ]; then
			patch --batch -f -p1 < $BUILDER/patch/a20-temp.patch
		fi

		# SPI functionality
		if [ "$(patch --dry-run -t -p1 < $BUILDER/patch/spi.patch | grep previ)" == "" ]; then
			patch --batch -f -p1 < $BUILDER/patch/spi.patch
		fi
	fi

	# compiler reverse patch. It has already been fixed.
	if [ "$(patch --dry-run -t -p1 < $BUILDER/patch/compiler.patch | grep Reversed)" != "" ]; then
		patch --batch -t -p1 < $BUILDER/patch/compiler.patch
	fi

	cd $SRC
}


#--------------------------------------------------------------------------------------------------------------------------------
# Compile uboot
#--------------------------------------------------------------------------------------------------------------------------------
compile_uboot () {
	echo "------ Compiling universal boot loader"
	cd $SOURCES/$BOOTSOURCE
	make -s CONFIG_WATCHDOG=y CROSS_COMPILE=arm-linux-gnueabihf- clean

	# there are two methods of compilation
	make $CTHREADS $BOOTCONFIG CONFIG_WATCHDOG=y CROSS_COMPILE=arm-linux-gnueabihf-

	if [[ $KERNEL_BRANCH == "sunxi" ]]; then
		## patch mainline uboot configuration to boot with old kernels
		echo "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" >> $SOURCES/$BOOTSOURCE/.config
		echo "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" >> $SOURCES/$BOOTSOURCE/spl/.config
		echo "CONFIG_OLD_SUNXI_KERNEL_COMPAT=y" >> $SOURCES/$BOOTSOURCE/.config
		echo "CONFIG_OLD_SUNXI_KERNEL_COMPAT=y"	>> $SOURCES/$BOOTSOURCE/spl/.config
	fi

	make $CTHREADS CONFIG_WATCHDOG=y CROSS_COMPILE=arm-linux-gnueabihf-
	# create package
	CHOOSEN_UBOOT=lime2_"$KERNEL_BRANCH"_u-boot_"$VER".tgz
	if [ -f "$BOOTDEST/$CHOOSEN_UBOOT" ]; then
		rm $BOOTDEST"/"$CHOOSEN_UBOOT
	fi
	tar cPfz $BOOTDEST"/"$CHOOSEN_UBOOT u-boot-sunxi-with-spl.bin

	cd $SRC
}

#--------------------------------------------------------------------------------------------------------------------------------
# Choose which bootloader to use
#--------------------------------------------------------------------------------------------------------------------------------
choosing_uboot () {
	cd $BOOTDEST
	if [[ $KERNEL_BRANCH == "mainline" ]]; then
		MYLIST=`for x in $(ls -1 *mainline*.tgz); do echo $x " -"; done`
	else
		MYLIST=`for x in $(ls -1 *.tgz | grep -v mainline); do echo $x " -"; done`
	fi
	WC=`echo $MYLIST | wc -l`
	if [[ $WC -ne 0 ]]; then
		whiptail --title "Choose u-boot archive" --backtitle "Which bootloader do you want to use?" --menu "" 12 60 4 $MYLIST 2>results
	fi
	CHOOSEN_UBOOT=$(<results)
	rm results
	cd $SRC
}


#--------------------------------------------------------------------------------------------------------------------------------
# Compile sunxi_tools
#--------------------------------------------------------------------------------------------------------------------------------
compile_sunxi_tools () {
	echo "------ Compiling sunxi tools"
	cd $SOURCES/$TOOLSSOURCE
	if [ -f "/usr/local/bin/fex2bin" ]; then
		rm /usr/local/bin/fex2bin
	fi
	if [ -f "/usr/local/bin/bin2fex" ]; then
		rm /usr/local/bin/bin2fex
	fi
	if [ -f "$DEST/fex2bin" ]; then
		rm $DEST/fex2bin
	fi
	if [ -f "$DEST/bin2fex" ]; then
		rm $DEST/bin2fex
	fi
	# for host
	make -s clean && make -s fex2bin && make -s bin2fex
	cp fex2bin bin2fex /usr/local/bin/
	# for destination
	make -s clean && make $CTHREADS fex2bin CC=arm-linux-gnueabihf-gcc && make $CTHREADS bin2fex CC=arm-linux-gnueabihf-gcccd
	
	cp fex2bin $DEST/
	cp bin2fex $DEST/
	cd $SRC
}


#--------------------------------------------------------------------------------------------------------------------------------
# Compile kernel
#--------------------------------------------------------------------------------------------------------------------------------
compile_kernel () {
	echo "------ Compiling kernel"
	cd $SOURCES/$LINUXSOURCE

	# get kernel version
	VER=$(cat $SOURCES/$LINUXSOURCE/Makefile | grep VERSION | head -1 | awk '{print $(NF)}')
	VER=$VER.$(cat $SOURCES/$LINUXSOURCE/Makefile | grep PATCHLEVEL | head -1 | awk '{print $(NF)}')
	VER=$VER.$(cat $SOURCES/$LINUXSOURCE/Makefile | grep SUBLEVEL | head -1 | awk '{print $(NF)}')
	EXTRAVERSION=$(cat $SOURCES/$LINUXSOURCE/Makefile | grep EXTRAVERSION | head -1 | awk '{print $(NF)}')
	if [ "$EXTRAVERSION" != "=" ]; then VER=$VER$EXTRAVERSION; fi

	# delete previous creations
	if [ "$KERNEL_CLEAN" = "yes" ]; then
		make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean;
	fi

	# use proven config
	cp $BUILDER/config/$LINUXCONFIG.config $SOURCES/$LINUXSOURCE/.config
	if [ "$KERNEL_CONFIGURE" = "yes" ]; then
		make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig;
	fi

	# this way of compilation is much faster. We can use multi threading here but not later
	make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- all zImage

	# produce deb packages: image, headers, firmware, libc
	make -j1 deb-pkg KDEB_PKGVERSION=$REVISION LOCALVERSION="-lime2" KBUILD_DEBARCH=armhf ARCH=arm DEBFULLNAME="$MAINTAINER" DEBEMAIL="$MAINTAINER_MAIL" CROSS_COMPILE=arm-linux-gnueabihf-

	# we need a name
	CHOOSEN_KERNEL=$VER"-"$CONFIG_LOCALVERSION"lime2-"$KERNEL_BRANCH".tar"
	if [ -f "$KERNELDEST/$CHOOSEN_KERNEL" ]; then
		rm $KERNELDEST"/"$CHOOSEN_KERNEL
	fi

	# create tar archive of all deb files
	cd ..
	tar -cPf $KERNELDEST"/"$CHOOSEN_KERNEL *.deb
	rm *.deb

	cd $SRC
	sync
}


#--------------------------------------------------------------------------------------------------------------------------------
# Choose which kernel to use
#--------------------------------------------------------------------------------------------------------------------------------
choosing_kernel () {
	cd $KERNELDEST
	if [[ $KERNEL_BRANCH == "mainline" ]]; then
		MYLIST=`for x in $(ls -1 *mainline*.tar); do echo $x " -"; done`
	else
		MYLIST=`for x in $(ls -1 *.tar | grep -v mainline); do echo $x " -"; done`
	fi
	WC=`echo $MYLIST | wc -l`
	if [[ $WC -ne 0 ]]; then
		whiptail --title "Choose kernel archive" --backtitle "Which kernel do you want to use?" --menu "" 12 60 4 $MYLIST 2>results
	fi
	CHOOSEN_KERNEL=$(<results)
	rm results
	VER=$(echo $CHOOSEN_KERNEL | awk 'BEGIN { FS = "-" } ; { print $1 }')
	cd $SRC
}


#--------------------------------------------------------------------------------------------------------------------------------
# Install kernel to prepared root file-system
#--------------------------------------------------------------------------------------------------------------------------------
install_kernel () {
	echo "------ Install kernel"

	# create modules file
	if [[ $KERNEL_BRANCH == "mainline" ]]; then
		for word in $MODULES_MAINLINE; do echo $word >> $SDCARD/etc/modules; done
	else
		for word in $MODULES_SUNXI; do echo $word >> $SDCARD/etc/modules; done
	fi

	# install kernel
	rm -rf /tmp/kernel && mkdir -p /tmp/kernel && cd /tmp/kernel
	tar -xPf $KERNELDEST"/"$CHOOSEN_KERNEL
	mount --bind /tmp/kernel/ $SDCARD/tmp
	chroot_sdcard "dpkg -i /tmp/*image*.deb"
	chroot_sdcard "dpkg -i /tmp/*headers*.deb"
	if [[ $KERNEL_BRANCH == "mainline" ]]; then
		chroot_sdcard "dpkg -i /tmp/*dtb*.deb"
	fi

	# name of archive is also kernel name
	CHOOSEN_KERNEL="${CHOOSEN_KERNEL//-$KERNEL_BRANCH.tar/}"

	echo "------ Compile headers scripts"
	# patch scripts
	cd $SDCARD/usr/src/linux-headers-$CHOOSEN_KERNEL
	patch -p1 < $BUILDER/patch/headers-debian-byteshift.patch
	cd $SRC

	# recompile headers scripts
	chroot_sdcard_lang "cd /usr/src/linux-headers-$CHOOSEN_KERNEL && make headers_check; make headers_install ; make scripts"

	# recreate boot.scr if using kernel for different board. Mainline only
	if [[ $KERNEL_BRANCH == "mainline" ]]; then
		# remove .old on new image
		rm -rf $SDCARD/boot/dtb.old

		# copy boot script and change it acordingly
		cp $BUILDER/config/boot-next.cmd $SDCARD/boot/boot-next.cmd
		sed -e "s/zImage/vmlinuz-$CHOOSEN_KERNEL/g" -i $SDCARD/boot/boot-next.cmd
		sed -e "s/dtb/dtb\/$CHOOSEN_KERNEL/g" -i $SDCARD/boot/boot-next.cmd

		#TODO uEnv
		cp $BUILDER/config/uEnv.cubox-i $DEST/output/sdcard/boot/uEnv.txt
		cp $SOURCES/$LINUXSOURCE/arch/arm/boot/dts/*.dtb $DEST/output/sdcard/boot
		chroot_sdcard "chmod 755 /boot/uEnv.txt"

		# compile boot script
		mkimage -C none -A arm -T script -d $SDCARD/boot/boot-next.cmd $SDCARD/boot/boot.scr >> /dev/null
	else
		fex2bin $BUILDER/config/script.fex $SDCARD/boot/script.bin

		cp $BUILDER/config/boot.cmd $SDCARD/boot/boot.cmd
		sed -e "s/zImage/vmlinuz-$CHOOSEN_KERNEL/g" -i $SDCARD/boot/boot.cmd

		# compile boot script
		mkimage -C none -A arm -T script -d $SDCARD/boot/boot.cmd $SDCARD/boot/boot.scr >> /dev/null
	fi

	# add linux firmwares to output image
	#unzip $BUILDER/bin/linux-firmware.zip -d $SDCARD/lib/firmware

	#TODO custom, update, upgrade
	#chroot_sdcard_lang "DEBIAN_FRONTEND=noninteractive apt-get -y update"
	#chroot_sdcard_lang "DEBIAN_FRONTEND=noninteractive apt-get -y --force-yes upgrade"
	#rm $SDCARD/usr/share/nginx/www/50x.html
	#rm $SDCARD/usr/share/nginx/www/index.html
	# clean deb cache
	#chroot_sdcard "apt-get -y clean"
	if [[ $U6PRO == "yes" ]]; then
		sqlite3 $SDCARD/usr/local/tmeslogger/tmeslogger.db "UPDATE loggerStatus SET tlvalue='yes' WHERE tlkey='u6pro'"
		sqlite3 $SDCARD/usr/local/tmeslogger/tmeslogger.db "UPDATE loggerStatus SET tlvalue='9' WHERE tlkey='resolutionIndex'"
	fi

	sqlite3 $SDCARD/usr/local/tmeslogger/tmeslogger.db "UPDATE loggerStatus SET tlvalue='$(date +%Y-%m-%d)' WHERE tlkey='currentDay'"
}


#--------------------------------------------------------------------------------------------------------------------------------
# Create Debian and Ubuntu image template if it does not exists
#--------------------------------------------------------------------------------------------------------------------------------
create_image_template (){
	if [ ! -f "$ROOTFS/wheezy.raw.gz" ]; then
		echo "------ Create image template"

		# create image file
		dd if=/dev/zero of=$ROOTFS/wheezy.raw bs=1M count=$SDSIZE status=noxfer

		# find first avaliable free device
		LOOP=$(losetup -f)

		# mount image as block device
		losetup $LOOP $ROOTFS/wheezy.raw

		sync

		# create one partition starting at 2048 which is default
		echo "------ Partitioning and mounting file-system."
		parted -s $LOOP -- mklabel msdos
		parted -s $LOOP -- mkpart primary ext4  2048s -1s
		partprobe $LOOP
		losetup -d $LOOP
		sleep 2

		# 2048 (start) x 512 (block size) = where to mount partition
		losetup -o 1048576 $LOOP $ROOTFS/wheezy.raw

		# create filesystem
		mkfs.ext4 $LOOP

		# tune filesystem
		tune2fs -o journal_data_writeback $LOOP

		# label it
		e2label $LOOP "lime2"

		# mount image to already prepared mount point
		mount -t ext4 $LOOP $SDCARD/

		# debootstrap base system
		debootstrap --include=openssh-server,debconf-utils --arch=armhf --foreign wheezy $SDCARD/

		# we need emulator for second stage
		cp /usr/bin/qemu-arm-static $SDCARD/usr/bin/

		# add sunxi tools
		cp $DEST/fex2bin $DEST/bin2fex $SDCARD/usr/bin/

		# enable arm binary format so that the cross-architecture chroot environment will work
		test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm

		#TODO does not work
		# Install, if missing, the debian-archive-keyring.gpg
		if [ ! -f $SDCARD/usr/share/keyrings/debian-archive-keyring.gpg ]; then
			mkdir -pv $SDCARD/usr/share/keyrings
			cp $BUILDER/bin/debian-archive-keyring.gpg $SDCARD/usr/share/keyrings/debian-archive-keyring.gpg
			chmod 0400 $SDCARD/usr/share/keyrings/debian-archive-keyring.gpg
		fi

		# debootstrap second stage
		chroot_sdcard_lang "/debootstrap/debootstrap --second-stage"

		# mount proc, sys and dev
		mount -t proc chproc $SDCARD/proc
		mount -t sysfs chsys $SDCARD/sys
		mount -t devtmpfs chdev $SDCARD/dev || mount --bind /dev $SDCARD/dev
		mount -t devpts chpts $SDCARD/dev/pts

		# choose proper apt list
		cp $BUILDER/config/sources.list $SDCARD/etc/apt/sources.list

		# update and upgrade
		chroot_sdcard_lang "apt-get -y update"

		# generate locales and install packets
		chroot_sdcard_lang "apt-get -y -qq install locales"
		sed -i "s/^# $DEST_LANG/$DEST_LANG/" $SDCARD/etc/locale.gen
		chroot_sdcard_lang "locale-gen $DEST_LANG"
		chroot_sdcard_lang "export LC_ALL=POSIX LANG=$DEST_LANG LANGUAGE=$DEST_LANG DEBIAN_FRONTEND=noninteractive"
		chroot_sdcard_lang "update-locale LC_ALL=POSIX LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=POSIX"
		#TODO not needed?
		#chroot_sdcard_lang "dpkg-reconfigure locales"

		# install aditional packages
		PAKETE="automake bash-completion bc build-essential cmake cpufrequtils curl dosfstools e2fsprogs evtest figlet fping git git-core haveged hddtemp hdparm htop i2c-tools iperf iotop less libtool libusb-1.0-0 libwrap0-dev libfuse2 libssl-dev logrotate lsof makedev module-init-tools nano ntp parted pkg-config pciutils pv python-smbus rsync screen stress sudo sysfsutils toilet u-boot-tools unzip usbutils wget"
		chroot_sdcard_lang "debconf-apt-progress -- apt-get -y install $PAKETE"

		# install console setup separate
		chroot_sdcard_lang "DEBIAN_FRONTEND=noninteractive apt-get -y install console-setup console-data kbd console-common unicode-data"

		# install packages for wifi
		PAKETEWIFI="firmware-ralink hostapd iw rfkill wireless-tools wpasupplicant"
		chroot_sdcard_lang "debconf-apt-progress -- apt-get -y install $PAKETEWIFI"

		# install watchdog
		chroot_sdcard_lang "debconf-apt-progress -- apt-get -y install watchdog"
		/bin/cp -f $BUILDER/config/watchdog.conf $SDCARD/etc/watchdog.conf

		# install acpi
		chroot_sdcard_lang "debconf-apt-progress -- apt-get -y install acpid acpi-support-base"
		chroot_sdcard "service acpid stop"

		# install tmeslogger packages
		PAKETE_TMESLOGGER="ca-certificates dhcp3-client libusb-1.0-0-dev nginx php5-common php5-fpm php5-json php5-mcrypt php5-sqlite proftpd-basic python2.7 python2.7-dev python-sqlite resolvconf rsyslog sqlite3"
		chroot_sdcard_lang "debconf-apt-progress -- apt-get -y install $PAKETE_TMESLOGGER"

		# set up 'apt
cat <<END > $SDCARD/etc/apt/apt.conf.d/71-no-recommends
APT::Install-Recommends "0";
APT::Install-Suggests "0";
END

		chroot_sdcard_lang "service ssh stop"
		chroot_sdcard_lang "service proftpd stop"
		chroot_sdcard_lang "service nginx stop"
		chroot_sdcard_lang "service php5-fpm stop"
		chroot_sdcard_lang "service ntp stop"

		sed -e 's/^#Subsystem/Subsystem/g' -i $SDCARD/etc/ssh/sshd_config

		cp $BUILDER/config/if-up.d/ntp $SDCARD/etc/network/if-up.d
		chroot_sdcard "chmod +x /etc/network/if-up.d/ntp"

		cp $BUILDER/scripts/dofstrim $SDCARD/etc/cron.weekly/dofstrim
		chroot_sdcard "chmod +x /etc/cron.weekly/dofstrim"

		#Nginx Config
		/bin/cp -f $BUILDER/config/nginx.conf $SDCARD/etc/nginx/nginx.conf
		/bin/cp -f $BUILDER/config/site-default $SDCARD/etc/nginx/sites-available/default
		rm $SDCARD/usr/share/nginx/www/50x.html
		rm $SDCARD/usr/share/nginx/www/index.html
		cp $BUILDER/config/if-up.d/nginx $SDCARD/etc/network/if-up.d
		chroot_sdcard "chmod +x /etc/network/if-up.d/nginx"

		#PHP FPM Config
		/bin/cp -f $BUILDER/config/php-fpm.conf $SDCARD/etc/php5/fpm/php-fpm.conf
		/bin/cp -f $BUILDER/config/php.ini $SDCARD/etc/php5/fpm/php.ini

		#FTP Server
		/bin/cp -f $BUILDER/config/proftpd.conf $SDCARD/etc/proftpd/proftpd.conf
		/bin/cp -f $BUILDER/config/modules.conf $SDCARD/etc/proftpd/modules.conf
		rm $SDCARD/srv/ftp/welcome.msg
		cp $BUILDER/config/if-up.d/proftpd $SDCARD/etc/network/if-up.d
		chroot_sdcard "chmod +x /etc/network/if-up.d/proftpd"
		chroot_sdcard_lang "echo ftp:$ROOTPWD | chpasswd"
		chroot_sdcard_lang "groupadd ftp"
		chroot_sdcard_lang "usermod -g ftp ftp"
		chroot_sdcard "chown ftp:ftp /srv/ftp"
		chroot_sdcard "chmod 0770 /srv/ftp"

		#Config user tmeslogger
		chroot_sdcard_lang "adduser --system --home /usr/local/tmeslogger --group --disabled-password --disabled-login tmeslogger"
		chroot_sdcard "chmod 0770 /usr/local/tmeslogger"
		chroot_sdcard_lang "usermod -a -G ftp tmeslogger"
		chroot_sdcard_lang "usermod -a -G adm tmeslogger"
		chroot_sdcard_lang "usermod -a -G tmeslogger ftp"
		chroot_sdcard_lang "usermod -a -G tmeslogger www-data"
		chroot_sdcard_lang "usermod -a -G sudo www-data"
		mkdir $SDCARD/var/log/tmeslogger
		chroot_sdcard "chown tmeslogger:tmeslogger /var/log/tmeslogger/"
		
		#Logrotate
		/bin/cp -f $BUILDER/config/logrotate.conf $SDCARD/etc/logrotate.conf
		/bin/cp -f $BUILDER/config/logrotate.d/rsyslog $SDCARD/etc/logrotate.d/rsyslog
		/bin/cp -f $BUILDER/config/logrotate.d/nginx $SDCARD/etc/logrotate.d/nginx
		/bin/cp -f $BUILDER/config/logrotate.d/proftpd-basic $SDCARD/etc/logrotate.d/proftpd-basic
		/bin/cp -f $BUILDER/config/logrotate.d/php5-fpm $SDCARD/etc/logrotate.d/php5-fpm

		mkdir $SDCARD/usr/local/tmeslogger/scripts
		chroot_sdcard "chown tmeslogger:tmeslogger /usr/local/tmeslogger/scripts"

		#Proprietary code
		cp $SRCTMESLOGGER/tmeslogger.sql $SDCARD/usr/local/tmeslogger/tmeslogger.sql

		#Setup db
		chroot_sdcard "sqlite3 /usr/local/tmeslogger/tmeslogger.db < /usr/local/tmeslogger/tmeslogger.sql"
		chroot_sdcard "chown tmeslogger:tmeslogger /usr/local/tmeslogger/tmeslogger.db"
		chroot_sdcard "chmod 0660 /usr/local/tmeslogger/tmeslogger.db"
		rm $SDCARD/usr/local/tmeslogger/tmeslogger.sql

		#Setup scripts
		cp $SRCTMESLOGGERSCRIPTS/batteryChecker.sh $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/changeInterface.awk $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/changeNTP.sh $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/changeSFTP.sh $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/disableService.sh $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/enableService.sh $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/factoryReset.sh $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/restartService.sh $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/servicestatus.sh $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/setDate.sh $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/setNetwork.sh $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/setPassword.sh $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/setTimezone.sh $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/startBlink.sh $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/stopBlink.sh $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/systemstatus.sh $SDCARD/usr/local/tmeslogger/scripts
		cp $SRCTMESLOGGERSCRIPTS/toggleNetwork.sh $SDCARD/usr/local/tmeslogger/scripts

		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/batteryChecker.sh"
		chroot_sdcard "chmod 0640 /usr/local/tmeslogger/scripts/changeInterface.awk"
		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/changeNTP.sh"
		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/changeSFTP.sh"
		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/disableService.sh"
		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/enableService.sh"
		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/factoryReset.sh"
		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/restartService.sh"
		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/servicestatus.sh"
		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/setDate.sh"
		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/setNetwork.sh"
		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/setPassword.sh"
		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/setTimezone.sh"
		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/startBlink.sh"
		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/stopBlink.sh"
		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/systemstatus.sh"
		chroot_sdcard "chmod 0750 /usr/local/tmeslogger/scripts/toggleNetwork.sh"

		#Setup sudo
		cp $SRCTMESLOGGERSCRIPTS/tmeslogger.sudo $SDCARD/etc/sudoers.d/tmeslogger
		chroot_sdcard "chmod 0440 /etc/sudoers.d/tmeslogger"

		#Setup apps
		cp $SRCTMESLOGGER/ftppush.py $SDCARD/usr/local/tmeslogger/ftppush.py
		cp $SRCTMESLOGGER/tmeslogger.py $SDCARD/usr/local/tmeslogger/tmeslogger.py
		cp $SRCTMESLOGGER/dbread.py $SDCARD/usr/local/tmeslogger/dbread.py

		chroot_sdcard "chown tmeslogger:tmeslogger /usr/local/tmeslogger/ftppush.py"
		chroot_sdcard "chown tmeslogger:tmeslogger /usr/local/tmeslogger/tmeslogger.py"
		chroot_sdcard "chown tmeslogger:tmeslogger /usr/local/tmeslogger/dbread.py"

		chroot_sdcard "chmod +x /usr/local/tmeslogger/ftppush.py"
		chroot_sdcard "chmod +x /usr/local/tmeslogger/tmeslogger.py"
		chroot_sdcard "chmod 0550 /usr/local/tmeslogger/dbread.py"

		cp $SRCTMESLOGGERSCRIPTS/ftppush $SDCARD/etc/init.d/ftppush
		cp $SRCTMESLOGGERSCRIPTS/tmeslogger $SDCARD/etc/init.d/tmeslogger
		cp $SRCTMESLOGGERSCRIPTS/processRebootAndShutdown $SDCARD/etc/init.d/processRebootAndShutdown

		chroot_sdcard "chmod +x /etc/init.d/ftppush"
		chroot_sdcard "chmod +x /etc/init.d/tmeslogger"
		chroot_sdcard "chmod +x /etc/init.d/processRebootAndShutdown"

		chroot_sdcard "insserv processRebootAndShutdown >> /dev/null"

		#Web
		cp -r $SRCTMESLOGGER/web/* $SDCARD/usr/share/nginx/www/

		#Copy Exodriver
		cp -r $SOURCES/$EXODRIVERSOURCE $SDCARD/root/

		#Copy LabJackPython
		cp -r $SOURCES/$LABJACKSOURCE $SDCARD/root/

		#Copy pyA20Lime2 library
		cd $SOURCES
		if [ ! -f "$SOURCES/$PYA20LIME2SOURCE.tar.gz" ]; then
			wget $PYA20LIME2S_REPOSITORY
		fi
		tar -zxvf $PYA20LIME2SOURCE.tar.gz
		cp -r $SOURCES/$PYA20LIME2SOURCE $SDCARD/root/
		rm -r $PYA20LIME2SOURCE
		cd $SRC

		#Copy chilkat python library
		cd $SOURCES
		if [ ! -f "$SOURCES/$CHILKATSOURCE.tar.gz" ]; then
			wget $CHILKAT_REPOSITORY
		fi
		tar -zxvf $CHILKATSOURCE.tar.gz
		mv $SOURCES/$CHILKATSOURCE/_chilkat.so $SDCARD/usr/local/lib/python2.7/dist-packages/
		mv $SOURCES/$CHILKATSOURCE/chilkat.py $SDCARD/usr/local/lib/python2.7/dist-packages/
		rm -r $CHILKATSOURCE
		cd $SRC

		#Wheezy specific
		#--------------------------------------------------------------------------------------------------------------------------------
		# specifics packets
		chroot_sdcard_lang "debconf-apt-progress -- apt-get -y install libnl-dev"

		# add serial console, root auto login
		echo T0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100 >> $SDCARD/etc/inittab
		#echo T0:2345:respawn:/sbin/getty -L -a root ttyS0 115200 vt100 >> $SDCARD/etc/inittab

		# don't clear screen on boot console
		sed -e 's/1:2345:respawn:\/sbin\/getty 38400 tty1/1:2345:respawn:\/sbin\/getty --noclear 38400 tty1/g' -i $SDCARD/etc/inittab

		# disable some getties
		sed -e 's/3:23:respawn/#3:23:respawn/g' -i $SDCARD/etc/inittab
		sed -e 's/4:23:respawn/#4:23:respawn/g' -i $SDCARD/etc/inittab
		sed -e 's/5:23:respawn/#5:23:respawn/g' -i $SDCARD/etc/inittab
		sed -e 's/6:23:respawn/#6:23:respawn/g' -i $SDCARD/etc/inittab
		#--------------------------------------------------------------------------------------------------------------------------------

		# remove what's not needed
		chroot_sdcard_lang "debconf-apt-progress -- apt-get -y autoremove"

		# scripts for autoresize at first boot
		cp $BUILDER/scripts/resize2fs $SDCARD/etc/init.d/
		cp $BUILDER/scripts/firstrun $SDCARD/etc/init.d/
		chroot_sdcard "chmod +x /etc/init.d/firstrun"
		chroot_sdcard "chmod +x /etc/init.d/resize2fs"
		chroot_sdcard "insserv firstrun >> /dev/null"

		# install custom bashrc
		cat $BUILDER/scripts/bashrc >> $SDCARD/etc/bash.bashrc

		# install ramlog only on wheezy
		cp $BUILDER/bin/ramlog_2.0.0_all.deb $SDCARD/tmp/
		chroot_sdcard_lang "dpkg -i /tmp/ramlog_2.0.0_all.deb"
		rm $SDCARD/tmp/ramlog_2.0.0_all.deb
		sed -e 's/TMPFS_RAMFS_SIZE=/TMPFS_RAMFS_SIZE=512m/g' -i $SDCARD/etc/default/ramlog
		sed -e 's/# Required-Start:    $remote_fs $time/# Required-Start:    $remote_fs $time ramlog/g' -i $SDCARD/etc/init.d/rsyslog
		sed -e 's/# Required-Stop:     umountnfs $time/# Required-Stop:     umountnfs $time ramlog/g' -i $SDCARD/etc/init.d/rsyslog

		# set console
		chroot_sdcard "export TERM=linux"

		# change time zone data
		echo $TZDATA > $SDCARD/etc/timezone
		chroot_sdcard_lang "dpkg-reconfigure -f noninteractive tzdata"

		# set root password
		chroot_sdcard "(echo $ROOTPWD;echo $ROOTPWD;) | passwd root"

		# change default I/O scheduler, noop for flash media, deadline for SSD, cfq for mechanical drive
cat <<EOT >> $SDCARD/etc/sysfs.conf
block/mmcblk0/queue/scheduler = noop
block/sda/queue/scheduler = deadline
EOT

		# add noatime to root FS
		echo "/dev/mmcblk0p1  /           ext4    defaults,noatime,nodiratime,data=writeback,commit=600,errors=remount-ro        0       0" >> $SDCARD/etc/fstab

		# flash media tunning
		if [ -f "$SDCARD/etc/default/tmpfs" ]; then
			sed -e 's/#RAMTMP=no/RAMTMP=yes/g' -i $SDCARD/etc/default/tmpfs
			sed -e 's/#RUN_SIZE=10%/RUN_SIZE=128M/g' -i $SDCARD/etc/default/tmpfs
			sed -e 's/#LOCK_SIZE=/LOCK_SIZE=/g' -i $SDCARD/etc/default/tmpfs
			sed -e 's/#SHM_SIZE=/SHM_SIZE=128M/g' -i $SDCARD/etc/default/tmpfs
			sed -e 's/#TMP_SIZE=/TMP_SIZE=1G/g' -i $SDCARD/etc/default/tmpfs
		fi

		# clean deb cache
		chroot_sdcard "apt-get -y clean"

		# script to install to SATA
		cp $BUILDER/scripts/sata-install.sh $SDCARD/root/
		chroot_sdcard "chmod +x /root/sata-install.sh"

		# script to init tmeslogger
		cp $BUILDER/scripts/tmeslogger-init.sh $SDCARD/root/
		chroot_sdcard "chmod +x /root/tmeslogger-init.sh"

		# copy and create symlink to default interfaces configuration
		/bin/cp -f $BUILDER/config/interfaces $SDCARD/etc/network/

		chroot_sdcard_lang "apt-get -y -qq remove lirc alsa-utils alsa-base && apt-get -y -qq autoremove"

		# add irq to second core - rc.local
		head -n -1 $SDCARD/etc/rc.local > /tmp/out
		echo 'echo 2 > /proc/irq/$(cat /proc/interrupts | grep eth0 | cut -f 1 -d ":" | tr -d " ")/smp_affinity' >> /tmp/out
		echo 'echo ds1307 0x68 > /sys/class/i2c-adapter/i2c-2/new_device' >> /tmp/out
		echo 'hwclock -s' >> /tmp/out
		echo 'echo none > /sys/class/leds/green\:ph02\:led1/trigger' >> /tmp/out
		echo 'echo 255 > /sys/class/leds/green\:ph02\:led1/brightness' >> /tmp/out
		echo 'exit 0' >> /tmp/out
		mv /tmp/out $SDCARD/etc/rc.local
		chroot_sdcard "chmod +x /etc/rc.local"

		# configure MIN / MAX Speed for cpufrequtils
		sed -e "s/MIN_SPEED=\"0\"/MIN_SPEED=\"480000\"/g" -i $SDCARD/etc/init.d/cpufrequtils
		sed -e "s/MAX_SPEED=\"0\"/MAX_SPEED=\"1010000\"/g" -i $SDCARD/etc/init.d/cpufrequtils
		sed -e 's/ondemand/interactive/g' -i $SDCARD/etc/init.d/cpufrequtils

		# root-fs modifications
		echo $MOTD_MSG > $SDCARD/etc/motd

		# set hostname
		echo $HOST > $SDCARD/etc/hostname

		# set hostname in hosts file
cat > $SDCARD/etc/hosts <<EOT
127.0.0.1   localhost
127.0.1.1   $HOST
EOT

		echo "------ Closing image"
		chroot_sdcard "sync"
		chroot_sdcard "unset DEBIAN_FRONTEND"
		sync
		sleep 3

		# unmount proc, sys and dev from chroot
		umount -l $SDCARD/dev/pts
		umount -l $SDCARD/dev
		umount -l $SDCARD/proc
		umount -l $SDCARD/sys

		# kill process inside
		KILLPROC=$(ps -uax | pgrep ntpd |        tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi
		KILLPROC=$(ps -uax | pgrep dbus-daemon | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi

		umount -l $SDCARD/
		sleep 2
		losetup -d $LOOP
		rm -rf $SDCARD/

		gzip $ROOTFS/wheezy.raw
	fi
	#
}


#--------------------------------------------------------------------------------------------------------------------------------
# Mount prepared root file-system
#--------------------------------------------------------------------------------------------------------------------------------
mount_existing_image (){
	echo "------ Mount image"
	gzip -dc < $ROOTFS/wheezy.raw.gz > $DEST/debian_rootfs.raw

	# find first avaliable free device
	LOOP=$(losetup -f)

	# 2048 (start) x 512 (block size) = where to mount partition
	losetup -o 1048576 $LOOP $DEST/debian_rootfs.raw

	# relabel
	e2label $LOOP "lime2"

	# mount image to already prepared mount point
	mkdir -p $SDCARD
	mount -t ext4 $LOOP $SDCARD/

	# mount proc, sys and dev
	mount -t proc chproc $SDCARD/proc
	mount -t sysfs chsys $SDCARD/sys
	mount -t devtmpfs chdev $SDCARD/dev || mount --bind /dev $SDCARD/dev
	mount -t devpts chpts $SDCARD/dev/pts
}


#--------------------------------------------------------------------------------------------------------------------------------
# Saving build summary to the image
#--------------------------------------------------------------------------------------------------------------------------------
fingerprint_image (){
	echo "------ Saving build summary to the image"
	echo $1
	echo "--------------------------------------------------------------------------------" > $1
	echo "" >> $1
	echo "" >> $1
	echo "" >> $1
	echo "Title:			$VERSION (unofficial)" >> $1
	echo "Kernel:			Linux $VER" >> $1
	now="$(date +'%d.%m.%Y')" >> $1
	printf "Build date:		%s\n" "$now" >> $1
	echo "Author:			$MAINTAINER , $MAINTAINER_MAIL" >> $1
	echo "Sources:			https://github.com/JHSawatzki/Lime2-Debian-Builder/" >> $1
	echo "" >> $1
	echo "" >> $1
	echo "" >> $1
	echo "--------------------------------------------------------------------------------" >> $1
	echo "" >> $1
	cat $BUILDER/LICENSE >> $1
	echo "" >> $1
	echo "--------------------------------------------------------------------------------" >> $1
}


#--------------------------------------------------------------------------------------------------------------------------------
# Closing image and clean-up
#--------------------------------------------------------------------------------------------------------------------------------
closing_image (){
	echo "------ Closing image"

	set +e
	rm $SDCARD/usr/share/info/dir.old
	rm $SDCARD/var/cache/debconf/*.dat-old
	rm $SDCARD/var/log/{bootstrap,dpkg}.log
	rm $SDCARD/tmp/*
	for a in $SDCARD/var/log/{*.log,apt/*.log,debug,dmesg,faillog,messages,syslog,wtmp}; do echo -n > $a; done
	rm $SDCARD/var/cache/apt/*
	rm $SDCARD/var/lib/apt/lists/*
	set -e

	chroot_sdcard "unset DEBIAN_FRONTEND"
	chroot_sdcard "sync"
	sync
	sleep 3

	# unmount proc, sys and dev from chroot
	umount -l $SDCARD/dev/pts
	umount -l $SDCARD/dev
	umount -l $SDCARD/proc
	umount -l $SDCARD/sys
	umount -l $SDCARD/tmp

	# let's create nice file name
	VERSION=$VERSION" "$VER
	VERSION="${VERSION// /_}"
	VERSION="${VERSION//$KERNEL_BRANCH/}"
	VERSION="${VERSION//__/_}"

	# kill process inside
	KILLPROC=$(ps -uax | pgrep ntpd |        tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi
	KILLPROC=$(ps -uax | pgrep dbus-daemon | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi

	# same info outside the image
	cp $SDCARD/root/readme.txt $DEST/
	sleep 2
	rm $SDCARD/usr/bin/qemu-arm-static
	umount -l $SDCARD/
	sleep 2
	losetup -d $LOOP
	rm -rf $SDCARD/

	# write bootloader
	LOOP=$(losetup -f)
	losetup $LOOP $DEST/debian_rootfs.raw
	cd /tmp
	tar xvfz $BOOTDEST"/"$CHOOSEN_UBOOT
	dd if=u-boot-sunxi-with-spl.bin of=$LOOP bs=1024 seek=8 status=noxfer
	sync
	sleep 3
	losetup -d $LOOP
	sync
	sleep 2
	mv $DEST/debian_rootfs.raw $DEST/$VERSION.raw
	sync
	cd $DEST/
	# sign with PGP
	if [[ $GPG_PASS != "" ]]; then
		echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes $VERSION.raw
		echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes readme.txt
	fi
	zip $VERSION.zip $VERSION.* readme.*
	rm -f $VERSION.raw *.asc readme.txt
}
