#!/bin/bash
#
# Copyright (c) 2014 Igor Pecovnik, igor.pecovnik@gma**.com
#
# www.igorpecovnik.com / images + support
#
# Image build functions


mount_debian_template (){
	#--------------------------------------------------------------------------------------------------------------------------------
	# Mount prepared root file-system
	#--------------------------------------------------------------------------------------------------------------------------------
	if [ ! -f "$DEST/kernel/"$CHOOSEN_KERNEL ]; then
		echo "Previously compiled kernel does not exits. Please choose compile=yes in configuration and run again!"
		exit
	fi
	mkdir -p $DEST/sdcard/
	gzip -dc < $DEST/rootfs/$RELEASE.raw.gz > $DEST/debian_rootfs.raw
	LOOP=$(losetup -f)
	losetup -o 1048576 $LOOP $DEST/debian_rootfs.raw
	mount -t ext4 $LOOP $DEST/sdcard/

	# relabel
	e2label $LOOP "$BOARD"
	# set fstab
	echo "/dev/mmcblk0p1  /           ext4    defaults,noatime,nodiratime,data=writeback,commit=600,errors=remount-ro        0       0" > $DEST/sdcard/etc/fstab

	# mount proc, sys and dev
	mount -t proc chproc $DEST/sdcard/proc
	mount -t sysfs chsys $DEST/sdcard/sys
	mount -t devtmpfs chdev $DEST/sdcard/dev || mount --bind /dev $DEST/sdcard/dev
	mount -t devpts chpts $DEST/sdcard/dev/pts
}


install_board_specific (){
	#--------------------------------------------------------------------------------------------------------------------------------
	# Install board specific applications
	#--------------------------------------------------------------------------------------------------------------------------------
	clear
	echo "------ Install board specific applications"

	chroot $DEST/sdcard /bin/bash -c "apt-get -y -qq remove alsa-base && apt-get -y -qq autoremove"

	# add irq to second core - rc.local
	head -n -1 $DEST/sdcard/etc/rc.local > /tmp/out
	echo 'echo 2 > /proc/irq/$(cat /proc/interrupts | grep eth0 | cut -f 1 -d ":" | tr -d " ")/smp_affinity' >> /tmp/out

	if [[ $TMESLOGGER_INSTALL == "yes" ]]; then
		echo 'echo ds1307 0x68 > /sys/class/i2c-adapter/i2c-2/new_device' >> /tmp/out
		echo 'hwclock -s' >> /tmp/out
		echo 'echo none > /sys/class/leds/green\:ph2\:led1/trigger' >> /tmp/out
		echo 'echo 255 > /sys/class/leds/green\:ph2\:led1/brightness' >> /tmp/out
	fi

	echo 'exit 0' >> /tmp/out
	mv /tmp/out $DEST/sdcard/etc/rc.local
	chroot $DEST/sdcard /bin/bash -c "chmod +x /etc/rc.local"

	# add sunxi tools
	cp $DEST/sunxi-tools/fex2bin $DEST/sunxi-tools/bin2fex $DEST/sdcard/usr/bin/
	
	echo "------ done."
}


install_kernel (){
	#--------------------------------------------------------------------------------------------------------------------------------
	# Install kernel to prepared root file-system
	#--------------------------------------------------------------------------------------------------------------------------------
	echo "------ Install kernel"

	# configure MIN / MAX Speed for cpufrequtils
	sed -e "s/MIN_SPEED=\"0\"/MIN_SPEED=\"$CPUMIN\"/g" -i $DEST/sdcard/etc/init.d/cpufrequtils
	sed -e "s/MAX_SPEED=\"0\"/MAX_SPEED=\"$CPUMAX\"/g" -i $DEST/sdcard/etc/init.d/cpufrequtils
	sed -e 's/ondemand/interactive/g' -i $DEST/sdcard/etc/init.d/cpufrequtils

	# set hostname
	echo $HOST > $DEST/sdcard/etc/hostname

	# set hostname in hosts file
cat > $DEST/sdcard/etc/hosts <<EOT
127.0.0.1   localhost
127.0.1.1   $HOST
EOT

#cat > $DEST/sdcard/etc/hosts <<EOT
#127.0.0.1   localhost
#127.0.1.1   $HOST
#::1         localhost $HOST ip6-localhost ip6-loopback
#fe00::0     ip6-localnet
#ff00::0     ip6-mcastprefix
#ff02::1     ip6-allnodes
#ff02::2     ip6-allrouters
#EOT

	# create modules file
	if [[ $BRANCH == *next* ]];then
		for word in $MODULES_NEXT; do echo $word >> $DEST/sdcard/etc/modules; done
	else
		for word in $MODULES; do echo $word >> $DEST/sdcard/etc/modules; done
	fi
	
	# script to install to SATA
	cp $SRC/Lime2-Debian-Builder/scripts/sata-install.sh $DEST/sdcard/root
	chroot $DEST/sdcard /bin/bash -c "chmod +x /root/sata-install.sh"

	# copy and create symlink to default interfaces configuration
	/bin/cp -f $SRC/Lime2-Debian-Builder/config/interfaces $DEST/sdcard/etc/network/
	
	ln -sf interfaces.default $DEST/sdcard/etc/network/interfaces

	# install kernel
	rm -rf /tmp/kernel && mkdir -p /tmp/kernel && cd /tmp/kernel
	tar -xPf $DEST"/kernel/"$CHOOSEN_KERNEL
	mount --bind /tmp/kernel/ $DEST/sdcard/tmp
	chroot $DEST/sdcard /bin/bash -c "dpkg -i /tmp/*image*.deb"
	chroot $DEST/sdcard /bin/bash -c "dpkg -i /tmp/*headers*.deb"

	# name of archive is also kernel name
	CHOOSEN_KERNEL="${CHOOSEN_KERNEL//-$BRANCH.tar/}"

	echo "------ Compile headers scripts"
	# recompile headers scripts
	chroot $DEST/sdcard /bin/bash -c "cd /usr/src/linux-headers-$CHOOSEN_KERNEL && make scripts"

	# recreate boot.scr if using kernel for different board. Mainline only
	if [[ $BRANCH == *next* ]];then
		# remove .old on new image
		rm -rf $DEST/sdcard/boot/dtb/$CHOOSEN_KERNEL.old
		
		# copy boot script and change it acordingly
		cp $SRC/Lime2-Debian-Builder/config/boot-next.cmd $DEST/sdcard/boot/boot-next.cmd
		sed -e "s/zImage/vmlinuz-$CHOOSEN_KERNEL/g" -i $DEST/sdcard/boot/boot-next.cmd
		sed -e "s/dtb/dtb\/$CHOOSEN_KERNEL/g" -i $DEST/sdcard/boot/boot-next.cmd
		
		# compile boot script
		mkimage -C none -A arm -T script -d $DEST/sdcard/boot/boot-next.cmd $DEST/sdcard/boot/boot.scr >> /dev/null
	elif [[ $LINUXCONFIG == *sunxi* ]]; then
		fex2bin $SRC/Lime2-Debian-Builder/config/$BOARD.fex $DEST/sdcard/boot/$BOARD.bin
		cp $SRC/Lime2-Debian-Builder/config/boot.cmd $DEST/sdcard/boot/boot.cmd
		sed -e "s/zImage/vmlinuz-$CHOOSEN_KERNEL/g" -i $DEST/sdcard/boot/boot.cmd
		sed -e "s/script.bin/$BOARD.bin/g" -i $DEST/sdcard/boot/boot.cmd
		
		# compile boot script
		mkimage -C none -A arm -T script -d $DEST/sdcard/boot/boot.cmd $DEST/sdcard/boot/boot.scr >> /dev/null
	else
		# make symlink to kernel and uImage
		mkimage -A arm -O linux -T kernel -C none -a "0x40008000" -e "0x10008000" -n "Linux kernel" -d $DEST/sdcard/boot/vmlinuz-$CHOOSEN_KERNEL $DEST/sdcard/boot/uImage
		chroot $DEST/sdcard /bin/bash -c "ln -s /boot/vmlinuz-$CHOOSEN_KERNEL /boot/zImage"
	fi

	# add linux firmwares to output image
	unzip $SRC/Lime2-Debian-Builder/bin/linux-firmware.zip -d $DEST/sdcard/lib/firmware
}


download_host_packages (){
	#--------------------------------------------------------------------------------------------------------------------------------
	# Download packages for host - Ubuntu 14.04 recommended
	#--------------------------------------------------------------------------------------------------------------------------------
	apt-get -y -qq install debconf-utils
	
	debconf-apt-progress -- apt-get -y install pv bc lzop zip binfmt-support bison build-essential ccache debootstrap flex gawk
	debconf-apt-progress -- apt-get -y install gcc-arm-linux-gnueabihf lvm2 qemu-user-static u-boot-tools uuid-dev zlib1g-dev unzip
	debconf-apt-progress -- apt-get -y install libusb-1.0-0 libusb-1.0-0-dev parted pkg-config expect gcc-arm-linux-gnueabi libncurses5-dev
}


grab_kernel_version (){
	#--------------------------------------------------------------------------------------------------------------------------------
	# grab linux kernel version from Makefile
	#--------------------------------------------------------------------------------------------------------------------------------
	VER=$(cat $DEST/$LINUXSOURCE/Makefile | grep VERSION | head -1 | awk '{print $(NF)}')
	VER=$VER.$(cat $DEST/$LINUXSOURCE/Makefile | grep PATCHLEVEL | head -1 | awk '{print $(NF)}')
	VER=$VER.$(cat $DEST/$LINUXSOURCE/Makefile | grep SUBLEVEL | head -1 | awk '{print $(NF)}')
	EXTRAVERSION=$(cat $DEST/$LINUXSOURCE/Makefile | grep EXTRAVERSION | head -1 | awk '{print $(NF)}')
	if [ "$EXTRAVERSION" != "=" ]; then VER=$VER$EXTRAVERSION; fi
}


fetch_from_github (){
	#--------------------------------------------------------------------------------------------------------------------------------
	# Download sources from Github
	#--------------------------------------------------------------------------------------------------------------------------------
	echo "------ Downloading $2."
	if [ -d "$DEST/$2" ]; then
		cd $DEST/$2
		if [[ $1 == "https://github.com/dz0ny/rt8192cu" ]]; then
			git checkout master;
		fi
		git pull
		cd $SRC
	else
		git clone $1 $DEST/$2
	fi
}


patching_sources(){
	#--------------------------------------------------------------------------------------------------------------------------------
	# Patching sources
	#--------------------------------------------------------------------------------------------------------------------------------
	# kernel

	cd $DEST/$LINUXSOURCE

	# mainline
	if [[ $BRANCH == *next* ]]; then
		# Fix Kernel Tag
		if [[ KERNELTAG == "" ]]; then
			git checkout master
		else
			git checkout $KERNELTAG
		fi
		
		if [[ $TMESLOGGER_INSTALL == "yes" ]]; then
			# install custom dts for lime2
			if [ "$(patch --dry-run -t -p1 < $SRC/Lime2-Debian-Builder/patch/sun7i-a20-olinuxino-lime2.dts.patch | grep previ)" == "" ]; then
				patch -p1 < $SRC/Lime2-Debian-Builder/sun7i-a20-olinuxino-lime2.dts.patch
			fi
		fi
		
		# install device tree blobs in linux-image package
		if [ "$(patch --dry-run -t -p1 < $SRC/Lime2-Debian-Builder/patch/dtb_to_deb.patch | grep previ)" == "" ]; then
			patch -p1 < $SRC/Lime2-Debian-Builder/patch/dtb_to_deb.patch
		fi
	fi

	# sunxi 3.4
	if [[ $LINUXSOURCE == "linux-sunxi" ]]; then
		# if the source is already patched for banana, do reverse GMAC patch
		if [ "$(cat arch/arm/kernel/setup.c | grep BANANAPI)" != "" ]; then
			echo "Reversing Banana patch"
			patch --batch -t -p1 < $SRC/Lime2-Debian-Builder/patch/bananagmac.patch
		fi
		
		# deb packaging patch
		if [ "$(patch --dry-run -t -p1 < $SRC/Lime2-Debian-Builder/patch/packaging.patch | grep previ)" == "" ]; then
			patch --batch -f -p1 < $SRC/Lime2-Debian-Builder/patch/packaging.patch
		fi
		
		# gpio patch
		if [ "$(patch --dry-run -t -p1 < $SRC/Lime2-Debian-Builder/patch/gpio.patch | grep previ)" == "" ]; then
			patch --batch -f -p1 < $SRC/Lime2-Debian-Builder/patch/gpio.patch
		fi
		
		if [[ $BOARD == "lime2" ]]; then
			# I2C functionality for lime2; needed for other boards too?
			if [ "$(patch --dry-run -t -p1 < $SRC/Lime2-Debian-Builder/patch/sunxi-i2c.patch | grep previ)" == "" ]; then
				patch --batch -f -p1 < $SRC/Lime2-Debian-Builder/patch/sunxi-i2c.patch
			fi
		fi
		
		# SPI functionality
		if [ "$(patch --dry-run -t -p1 < $SRC/Lime2-Debian-Builder/patch/spi-sun7i.patch | grep previ)" == "" ]; then
			patch --batch -f -p1 < $SRC/Lime2-Debian-Builder/patch/spi-sun7i.patch
		fi
	fi
	
	# compile sunxi tools
	compile_sunxi_tools

	# compiler reverse patch. It has already been fixed.
	if [ "$(patch --dry-run -t -p1 < $SRC/Lime2-Debian-Builder/patch/compiler.patch | grep Reversed)" != "" ]; then
		patch --batch -t -p1 < $SRC/Lime2-Debian-Builder/patch/compiler.patch
	fi

	# u-boot
	cd $DEST/$BOOTSOURCE
}


compile_uboot (){
	#--------------------------------------------------------------------------------------------------------------------------------
	# Compile uboot
	#--------------------------------------------------------------------------------------------------------------------------------
	echo "------ Compiling universal boot loader"
	if [ -d "$DEST/$BOOTSOURCE" ]; then
		cd $DEST/$BOOTSOURCE
		make -s CONFIG_WATCHDOG=y CROSS_COMPILE=arm-linux-gnueabihf- clean
		
		# there are two methods of compilation
		make $CTHREADS $BOOTCONFIG CONFIG_WATCHDOG=y CROSS_COMPILE=arm-linux-gnueabihf-
		if [[ $BOOTCONFIG == *config* ]]; then
			if [[ $BRANCH != *next* && $LINUXCONFIG == *sunxi* ]]; then
				## patch mainline uboot configuration to boot with old kernels
				echo "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" >> $DEST/$BOOTSOURCE/.config
				echo "CONFIG_ARMV7_BOOT_SEC_DEFAULT=y" >> $DEST/$BOOTSOURCE/spl/.config
				echo "CONFIG_OLD_SUNXI_KERNEL_COMPAT=y" >> $DEST/$BOOTSOURCE/.config
				echo "CONFIG_OLD_SUNXI_KERNEL_COMPAT=y"	>> $DEST/$BOOTSOURCE/spl/.config
			fi
			make $CTHREADS CONFIG_WATCHDOG=y CROSS_COMPILE=arm-linux-gnueabihf-
		fi
		# create package
		mkdir -p $DEST/u-boot-image
		#
		CHOOSEN_UBOOT="$BOARD"_"$BRANCH"_u-boot_"$VER".tgz
		tar cPfz $DEST"/u-boot-image/$CHOOSEN_UBOOT" u-boot-sunxi-with-spl.bin
		#
	else
		echo "ERROR: Source file $1 does not exists. Check fetch_from_github configuration."
		exit
	fi
}


compile_sunxi_tools (){
	#--------------------------------------------------------------------------------------------------------------------------------
	# Compile sunxi_tools
	#--------------------------------------------------------------------------------------------------------------------------------
	echo "------ Compiling sunxi tools"
	cd $DEST/sunxi-tools
	# for host
	make -s clean && make -s fex2bin && make -s bin2fex
	cp fex2bin bin2fex /usr/local/bin/
	# for destination
	make -s clean && make $CTHREADS 'fex2bin' CC=arm-linux-gnueabihf-gcc && make $CTHREADS 'bin2fex' CC=arm-linux-gnueabihf-gcc
}


compile_kernel (){
	#--------------------------------------------------------------------------------------------------------------------------------
	# Compile kernel
	#--------------------------------------------------------------------------------------------------------------------------------
	echo "------ Compiling kernel"
	if [ -d "$DEST/$LINUXSOURCE" ]; then
		cd $DEST/$LINUXSOURCE

		# delete previous creations
		if [ "$KERNEL_CLEAN" = "yes" ]; then
			make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean;
		fi

		# adding custom firmware to kernel source
		if [[ -n "$FIRMWARE" ]]; then
			unzip -o $SRC/Lime2-Debian-Builder/$FIRMWARE -d $DEST/$LINUXSOURCE/firmware;
		fi

		# use proven config
		cp $SRC/Lime2-Debian-Builder/config/$LINUXCONFIG.config $DEST/$LINUXSOURCE/.config
		if [ "$KERNEL_CONFIGURE" = "yes" ]; then
			make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig;
		fi

		# this way of compilation is much faster. We can use multi threading here but not later
		make $CTHREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- all zImage modules_prepare

		# produce deb packages: image, headers, firmware, libc
		make -j1 deb-pkg KDEB_PKGVERSION=$REVISION LOCALVERSION="-"$BOARD KBUILD_DEBARCH=armhf ARCH=arm DEBFULLNAME="$MAINTAINER" DEBEMAIL="$MAINTAINERMAIL" CROSS_COMPILE=arm-linux-gnueabihf-

		# we need a name
		CHOOSEN_KERNEL=linux-image-"$VER"-"$CONFIG_LOCALVERSION$BOARD"_"$REVISION"_armhf.deb

		# create tar archive of all deb files
		mkdir -p $DEST/kernel
		cd ..
		tar -cPf $DEST"/kernel/"$VER"-"$CONFIG_LOCALVERSION$BOARD-$BRANCH".tar" *.deb
		rm *.deb
		CHOOSEN_KERNEL=$VER"-"$CONFIG_LOCALVERSION$BOARD-$BRANCH".tar"

		# go back and patch / unpatch
		cd $DEST/$LINUXSOURCE
	else
		echo "ERROR: Source file $1 does not exists. Check fetch_from_github configuration."
		exit
	fi
	sync
}


create_debian_template (){
	#--------------------------------------------------------------------------------------------------------------------------------
	# Create Debian and Ubuntu image template if it does not exists
	#--------------------------------------------------------------------------------------------------------------------------------
	if [ ! -f "$DEST/rootfs/$RELEASE.raw.gz" ]; then
		echo "------ Debootstrap $RELEASE to image template"
		cd $DEST

		# create needed directories and mount image to next free loop device
		mkdir -p $DEST/rootfs $DEST/sdcard/ $DEST/kernel

		# create image file
		dd if=/dev/zero of=$DEST/rootfs/$RELEASE.raw bs=1M count=$SDSIZE status=noxfer

		# find first avaliable free device
		LOOP=$(losetup -f)

		# mount image as block device
		losetup $LOOP $DEST/rootfs/$RELEASE.raw

		sync

		# create one partition starting at 2048 which is default
		echo "------ Partitioning and mounting file-system."
		parted -s $LOOP -- mklabel msdos
		parted -s $LOOP -- mkpart primary ext4  2048s -1s
		partprobe $LOOP
		losetup -d $LOOP
		sleep 2

		# 2048 (start) x 512 (block size) = where to mount partition
		losetup -o 1048576 $LOOP $DEST/rootfs/$RELEASE.raw

		# create filesystem
		mkfs.ext4 $LOOP

		# tune filesystem
		tune2fs -o journal_data_writeback $LOOP

		# label it
		e2label $LOOP "$BOARD"

		# mount image to already prepared mount point
		mount -t ext4 $LOOP $DEST/sdcard/

		# debootstrap base system
		debootstrap --include=openssh-server,debconf-utils --arch=armhf --foreign $RELEASE $DEST/sdcard/

		# we need emulator for second stage
		cp /usr/bin/qemu-arm-static $DEST/sdcard/usr/bin/

		# enable arm binary format so that the cross-architecture chroot environment will work
		test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm

		# debootstrap second stage
		chroot $DEST/sdcard /bin/bash -c "/debootstrap/debootstrap --second-stage"

		# mount proc, sys and dev
		mount -t proc chproc $DEST/sdcard/proc
		mount -t sysfs chsys $DEST/sdcard/sys
		mount -t devtmpfs chdev $DEST/sdcard/dev || mount --bind /dev $DEST/sdcard/dev
		mount -t devpts chpts $DEST/sdcard/dev/pts

		# root-fs modifications
		echo "Welcome to TMESLogger!" > $DEST/sdcard/etc/motd

		# choose proper apt list
		cp $SRC/Lime2-Debian-Builder/config/sources.list $DEST/sdcard/etc/apt/sources.list

		# set up 'apt
cat <<END > $DEST/sdcard/etc/apt/apt.conf.d/71-no-recommends
APT::Install-Recommends "0";
APT::Install-Suggests "0";
END

		# update and upgrade
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/sdcard /bin/bash -c "apt-get -y update"
		
		# generate locales and install packets
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/sdcard /bin/bash -c "apt-get -y -qq install locales"
		sed -i "s/^# $DEST_LANG/$DEST_LANG/" $DEST/sdcard/etc/locale.gen
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/sdcard /bin/bash -c "locale-gen $DEST_LANG"
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/sdcard /bin/bash -c "export LANG=$DEST_LANG LANGUAGE=$DEST_LANG DEBIAN_FRONTEND=noninteractive"
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/sdcard /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=POSIX"
		

		# install aditional packages
		PAKETE="automake bash-completion bc build-essential cmake cpufrequtils curl e2fsprogs evtest figlet fping git git-core haveged hddtemp hdparm htop i2c-tools iperf iotop less libtool libusb-1.0-0 libwrap0-dev libfuse2 libssl-dev logrotate lsof makedev module-init-tools nano ntp parted pkg-config pciutils pv python-smbus rsync screen stress sudo sysfsutils toilet u-boot-tools unzip usbutils wget"
		chroot $DEST/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install $PAKETE"
		
		#TODO WIFI
		#PAKETEWIFI="hostapd iw rfkill wireless-tools wpasupplicant"
		#chroot $DEST/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install $PAKETEWIFI"
		
		if [[ $TMESLOGGER_INSTALL == "yes" ]]; then
			do_tmeslogger_cutom
		fi

		#Wheezy specific
		#--------------------------------------------------------------------------------------------------------------------------------
		# specifics packets
		LC_ALL=C LANGUAGE=C LANG=C chroot $DEST/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install libnl-dev"
		
		# add serial console, root auto login
		echo T0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100 >> $DEST/sdcard/etc/inittab
		#echo T0:2345:respawn:/sbin/getty -L -a root ttyS0 115200 vt100 >> $DEST/sdcard/etc/inittab
		
		# don't clear screen on boot console
		sed -e 's/1:2345:respawn:\/sbin\/getty 38400 tty1/1:2345:respawn:\/sbin\/getty --noclear 38400 tty1/g' -i $DEST/sdcard/etc/inittab
		
		# disable some getties
		sed -e 's/3:23:respawn/#3:23:respawn/g' -i $DEST/sdcard/etc/inittab
		sed -e 's/4:23:respawn/#4:23:respawn/g' -i $DEST/sdcard/etc/inittab
		sed -e 's/5:23:respawn/#5:23:respawn/g' -i $DEST/sdcard/etc/inittab
		sed -e 's/6:23:respawn/#6:23:respawn/g' -i $DEST/sdcard/etc/inittab
		#--------------------------------------------------------------------------------------------------------------------------------

		# remove what's not needed
		chroot $DEST/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y autoremove"

		# scripts for autoresize at first boot
		cp $SRC/Lime2-Debian-Builder/scripts/resize2fs $DEST/sdcard/etc/init.d
		cp $SRC/Lime2-Debian-Builder/scripts/firstrun $DEST/sdcard/etc/init.d
		chroot $DEST/sdcard /bin/bash -c "chmod +x /etc/init.d/firstrun"
		chroot $DEST/sdcard /bin/bash -c "chmod +x /etc/init.d/resize2fs"
		chroot $DEST/sdcard /bin/bash -c "insserv firstrun >> /dev/null"

		# install custom bashrc
		cat $SRC/Lime2-Debian-Builder/scripts/bashrc >> $DEST/sdcard/etc/bash.bashrc

		# install ramlog only on wheezy
		cp $SRC/Lime2-Debian-Builder/bin/ramlog_2.0.0_all.deb $DEST/sdcard/tmp
		chroot $DEST/sdcard /bin/bash -c "dpkg -i /tmp/ramlog_2.0.0_all.deb"
		rm $DEST/sdcard/tmp/ramlog_2.0.0_all.deb
		sed -e 's/TMPFS_RAMFS_SIZE=/TMPFS_RAMFS_SIZE=512m/g' -i $DEST/sdcard/etc/default/ramlog
		sed -e 's/# Required-Start:    $remote_fs $time/# Required-Start:    $remote_fs $time ramlog/g' -i $DEST/sdcard/etc/init.d/rsyslog
		sed -e 's/# Required-Stop:     umountnfs $time/# Required-Stop:     umountnfs $time ramlog/g' -i $DEST/sdcard/etc/init.d/rsyslog

		# set console
		chroot $DEST/sdcard /bin/bash -c "export TERM=linux"

		# change time zone data
		echo $TZDATA > $DEST/sdcard/etc/timezone
		chroot $DEST/sdcard /bin/bash -c "dpkg-reconfigure -f noninteractive tzdata"

		# set root password
		chroot $DEST/sdcard /bin/bash -c "(echo $ROOTPWD;echo $ROOTPWD;) | passwd root"

		# change default I/O scheduler, noop for flash media, deadline for SSD, cfq for mechanical drive
cat <<EOT >> $DEST/sdcard/etc/sysfs.conf
block/mmcblk0/queue/scheduler = noop
block/sda/queue/scheduler = deadline
EOT

		# add noatime to root FS
		echo "/dev/mmcblk0p1  /           ext4    defaults,noatime,nodiratime,data=writeback,commit=600,errors=remount-ro        0       0" >> $DEST/sdcard/etc/fstab

		# flash media tunning
		if [ -f "$DEST/sdcard/etc/default/tmpfs" ]; then
			sed -e 's/#RAMTMP=no/RAMTMP=yes/g' -i $DEST/sdcard/etc/default/tmpfs
			sed -e 's/#RUN_SIZE=10%/RUN_SIZE=128M/g' -i $DEST/sdcard/etc/default/tmpfs
			sed -e 's/#LOCK_SIZE=/LOCK_SIZE=/g' -i $DEST/sdcard/etc/default/tmpfs
			sed -e 's/#SHM_SIZE=/SHM_SIZE=128M/g' -i $DEST/sdcard/etc/default/tmpfs
			sed -e 's/#TMP_SIZE=/TMP_SIZE=1G/g' -i $DEST/sdcard/etc/default/tmpfs
		fi

		# clean deb cache
		chroot $DEST/sdcard /bin/bash -c "apt-get -y clean"

		echo "------ Closing image"
		chroot $DEST/sdcard /bin/bash -c "sync"
		sync
		sleep 3

		# unmount proc, sys and dev from chroot
		umount -l $DEST/sdcard/dev/pts
		umount -l $DEST/sdcard/dev
		umount -l $DEST/sdcard/proc
		umount -l $DEST/sdcard/sys

		# kill process inside
		KILLPROC=$(ps -uax | pgrep ntpd |        tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi
		KILLPROC=$(ps -uax | pgrep dbus-daemon | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi

		umount -l $DEST/sdcard/
		sleep 2
		losetup -d $LOOP
		rm -rf $DEST/sdcard/

		gzip $DEST/rootfs/$RELEASE.raw
	fi
	#
}


do_tmeslogger_cutom (){
	# install watchdog
	chroot $DEST/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install watchdog"
	/bin/cp -f $SRC/Lime2-Debian-Builder/config/watchdog.conf $DEST/sdcard/etc/watchdog.conf

	# install acpi
	chroot $DEST/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install acpid acpi-support-base"
	chroot $DEST/sdcard /bin/bash -c "service acpid stop"
	
	PAKETE_TMESLOGGER="ca-certificates dhcp3-client libusb-1.0-0-dev nginx php5-common php5-fpm php5-json php5-mcrypt php5-sqlite proftpd-basic python2.7 python2.7-dev python-sqlite resolvconf rsyslog sqlite3"
	chroot $DEST/sdcard /bin/bash -c "debconf-apt-progress -- apt-get -y install $PAKETE_TMESLOGGER"
	
	chroot $DEST/sdcard /bin/bash -c "service ssh stop"
	chroot $DEST/sdcard /bin/bash -c "service proftpd stop"
	chroot $DEST/sdcard /bin/bash -c "service nginx stop"
	chroot $DEST/sdcard /bin/bash -c "service php5-fpm stop"
	chroot $DEST/sdcard /bin/bash -c "service ntp stop"

	sed -e 's/^#Subsystem/Subsystem/g' -i $DEST/sdcard/etc/ssh/sshd_config
	
	cp $SRC/Lime2-Debian-Builder/config/if-up.d/ntp $DEST/sdcard/etc/network/if-up.d
	chroot $DEST/sdcard /bin/bash -c "chmod +x /etc/network/if-up.d/ntp"

	#Config user tmeslogger
	chroot $DEST/sdcard /bin/bash -c "adduser --system --home /usr/local/tmeslogger --group --disabled-password --disabled-login tmeslogger"
	chroot $DEST/sdcard /bin/bash -c "chmod 0770 /usr/local/tmeslogger"
	chroot $DEST/sdcard /bin/bash -c "usermod -a -G ftp tmeslogger"
	chroot $DEST/sdcard /bin/bash -c "usermod -a -G adm tmeslogger"
	chroot $DEST/sdcard /bin/bash -c "usermod -a -G tmeslogger ftp"
	chroot $DEST/sdcard /bin/bash -c "usermod -a -G tmeslogger www-data"
	chroot $DEST/sdcard /bin/bash -c "usermod -a -G sudo www-data"
	mkdir $DEST/sdcard/var/log/tmeslogger
	chroot $DEST/sdcard /bin/bash -c "chown tmeslogger:tmeslogger /var/log/tmeslogger/"
	
	cp $SRC/Lime2-Debian-Builder/scripts/dofstrim $DEST/sdcard/etc/cron.weekly/dofstrim
	chroot $DEST/sdcard /bin/bash -c "chmod +x /etc/cron.weekly/dofstrim"
	
	#Nginx Config
	/bin/cp -f $SRC/Lime2-Debian-Builder/config/nginx.conf $DEST/sdcard/etc/nginx/nginx.conf
	/bin/cp -f $SRC/Lime2-Debian-Builder/config/site-default $DEST/sdcard/etc/nginx/sites-available/default
	rm $DEST/sdcard/usr/share/nginx/www/50x.html
	rm $DEST/sdcard/usr/share/nginx/www/index.html
	cp $SRC/Lime2-Debian-Builder/config/if-up.d/nginx $DEST/sdcard/etc/network/if-up.d
	chroot $DEST/sdcard /bin/bash -c "chmod +x /etc/network/if-up.d/nginx"

	#PHP FPM Config
	/bin/cp -f $SRC/Lime2-Debian-Builder/config/php-fpm.conf $DEST/sdcard/etc/php5/fpm/php-fpm.conf
	/bin/cp -f $SRC/Lime2-Debian-Builder/config/php.ini $DEST/sdcard/etc/php5/fpm/php.ini
	

	#FTP Server
	/bin/cp -f $SRC/Lime2-Debian-Builder/config/proftpd.conf $DEST/sdcard/etc/proftpd/proftpd.conf
	/bin/cp -f $SRC/Lime2-Debian-Builder/config/modules.conf $DEST/sdcard/etc/proftpd/modules.conf
	rm $DEST/sdcard/srv/ftp/welcome.msg
	cp $SRC/Lime2-Debian-Builder/config/if-up.d/proftpd $DEST/sdcard/etc/network/if-up.d
	chroot $DEST/sdcard /bin/bash -c "chmod +x /etc/network/if-up.d/proftpd"
	chroot $DEST/sdcard /bin/bash -c "echo ftp:$ROOTPWD | chpasswd"
	chroot $DEST/sdcard /bin/bash -c "groupadd ftp"
	chroot $DEST/sdcard /bin/bash -c "usermod -g ftp ftp"
	chroot $DEST/sdcard /bin/bash -c "chown ftp:ftp /srv/ftp"
	chroot $DEST/sdcard /bin/bash -c "chmod 0770 /srv/ftp"

	#Logrotate
	/bin/cp -f $SRC/Lime2-Debian-Builder/config/logrotate.conf $DEST/sdcard/etc/logrotate.conf
	/bin/cp -f $SRC/Lime2-Debian-Builder/config/logrotate.d/rsyslog $DEST/sdcard/etc/logrotate.d/rsyslog
	/bin/cp -f $SRC/Lime2-Debian-Builder/config/logrotate.d/nginx $DEST/sdcard/etc/logrotate.d/nginx
	/bin/cp -f $SRC/Lime2-Debian-Builder/config/logrotate.d/proftpd-basic $DEST/sdcard/etc/logrotate.d/proftpd-basic
	/bin/cp -f $SRC/Lime2-Debian-Builder/config/logrotate.d/php5-fpm $DEST/sdcard/etc/logrotate.d/php5-fpm
	
	mkdir $DEST/sdcard/usr/local/tmeslogger/scripts
	chroot $DEST/sdcard /bin/bash -c "chown tmeslogger:tmeslogger /usr/local/tmeslogger/scripts"
	
	#Proprietary code
	if [[ $U6PRO == "yes" ]]; then
		cp $SRC/tmeslogger/tmeslogger_u6pro.sql $DEST/sdcard/usr/local/tmeslogger/tmeslogger.sql
	else
		cp $SRC/tmeslogger/tmeslogger.sql $DEST/sdcard/usr/local/tmeslogger/tmeslogger.sql
	fi

	#Setup db
	chroot $DEST/sdcard /bin/bash -c "sqlite3 /usr/local/tmeslogger/tmeslogger.db < /usr/local/tmeslogger/tmeslogger.sql"
	chroot $DEST/sdcard /bin/bash -c "chown tmeslogger:tmeslogger /usr/local/tmeslogger/tmeslogger.db"
	chroot $DEST/sdcard /bin/bash -c "chmod 0660 /usr/local/tmeslogger/tmeslogger.db"
	chroot $DEST/sdcard /bin/bash -c "rm /usr/local/tmeslogger/tmeslogger.sql"
	chroot $DEST/sdcard /bin/bash -c "sqlite3 /usr/local/tmeslogger/tmeslogger.db \"UPDATE loggerStatus SET tlvalue='$(date +%Y-%m-%d)' WHERE tlkey='currentDay'\""

	#Setup scripts
	cp $SRC/tmeslogger/scripts/batteryChecker.sh $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/changeInterface.awk $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/changeNTP.sh $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/changeSFTP.sh $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/disableService.sh $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/enableService.sh $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/factoryReset.sh $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/restartService.sh $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/servicestatus.sh $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/setDate.sh $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/setNetwork.sh $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/setPassword.sh $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/setTimezone.sh $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/startBlink.sh $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/stopBlink.sh $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/systemstatus.sh $DEST/sdcard/usr/local/tmeslogger/scripts
	cp $SRC/tmeslogger/scripts/toggleNetwork.sh $DEST/sdcard/usr/local/tmeslogger/scripts

	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/batteryChecker.sh"
	chroot $DEST/sdcard /bin/bash -c "chmod 0640 /usr/local/tmeslogger/scripts/changeInterface.awk"
	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/changeNTP.sh"
	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/changeSFTP.sh"
	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/disableService.sh"
	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/enableService.sh"
	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/factoryReset.sh"
	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/restartService.sh"
	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/servicestatus.sh"
	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/setDate.sh"
	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/setNetwork.sh"
	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/setPassword.sh"
	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/setTimezone.sh"
	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/startBlink.sh"
	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/stopBlink.sh"
	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/systemstatus.sh"
	chroot $DEST/sdcard /bin/bash -c "chmod 0750 /usr/local/tmeslogger/scripts/toggleNetwork.sh"

	#Setup sudo
	cp $SRC/tmeslogger/scripts/tmeslogger.sudo $DEST/sdcard/etc/sudoers.d/tmeslogger
	chroot $DEST/sdcard /bin/bash -c "chmod 0440 /etc/sudoers.d/tmeslogger"

	#Setup apps
	cp $SRC/tmeslogger/ftppush.py $DEST/sdcard/usr/local/tmeslogger/ftppush.py
	cp $SRC/tmeslogger/tmeslogger.py $DEST/sdcard/usr/local/tmeslogger/tmeslogger.py
	cp $SRC/tmeslogger/dbread.py $DEST/sdcard/usr/local/tmeslogger/dbread.py

	chroot $DEST/sdcard /bin/bash -c "chown tmeslogger:tmeslogger /usr/local/tmeslogger/ftppush.py"
	chroot $DEST/sdcard /bin/bash -c "chown tmeslogger:tmeslogger /usr/local/tmeslogger/tmeslogger.py"
	chroot $DEST/sdcard /bin/bash -c "chown tmeslogger:tmeslogger /usr/local/tmeslogger/dbread.py"

	chroot $DEST/sdcard /bin/bash -c "chmod +x /usr/local/tmeslogger/ftppush.py"
	chroot $DEST/sdcard /bin/bash -c "chmod +x /usr/local/tmeslogger/tmeslogger.py"
	chroot $DEST/sdcard /bin/bash -c "chmod 0550 /usr/local/tmeslogger/dbread.py"

	cp $SRC/tmeslogger/scripts/ftppush $DEST/sdcard/etc/init.d/ftppush
	cp $SRC/tmeslogger/scripts/tmeslogger $DEST/sdcard/etc/init.d/tmeslogger
	cp $SRC/tmeslogger/scripts/processRebootAndShutdown $DEST/sdcard/etc/init.d/processRebootAndShutdown

	chroot $DEST/sdcard /bin/bash -c "chmod +x /etc/init.d/ftppush"
	chroot $DEST/sdcard /bin/bash -c "chmod +x /etc/init.d/tmeslogger"
	chroot $DEST/sdcard /bin/bash -c "chmod +x /etc/init.d/processRebootAndShutdown"

	chroot $DEST/sdcard /bin/bash -c "update-rc.d ftppush defaults"
	chroot $DEST/sdcard /bin/bash -c "update-rc.d tmeslogger defaults"
	chroot $DEST/sdcard /bin/bash -c "update-rc.d processRebootAndShutdown defaults"

	#Web
	cp -r $SRC/tmeslogger/web/  $DEST/sdcard/usr/share/nginx/www/
	#chroot $DEST/sdcard /bin/bash -c "chown -cR www-data:www-data /usr/share/nginx/www"

	unzip $SRC/Lime2-Debian-Builder/bin/exodriver.zip -d $DEST/sdcard/root/
	unzip $SRC/Lime2-Debian-Builder/bin/LabJackPython.zip -d $DEST/sdcard/root/
	unzip $SRC/Lime2-Debian-Builder/bin/pyA20-0.2.0.zip -d $DEST/sdcard/root/

	#Install chilkat python library
	unzip $SRC/Lime2-Debian-Builder/bin/chilkat-9.5.0-python-2.7-armv7a-hardfp-linux.tar.gz $SRC/Lime2-Debian-Builder/bin/
	mv $SRC/Lime2-Debian-Builder/bin/chilkat-9.5.0-python-2.7-armv7a-hardfp-linux/_chilkat.so $DEST/sdcard/usr/local/lib/python2.7/dist-packages/
	mv $SRC/Lime2-Debian-Builder/bin/chilkat-9.5.0-python-2.7-armv7a-hardfp-linux/chilkat.py $DEST/sdcard/usr/local/lib/python2.7/dist-packages/
	rm -r $SRC/Lime2-Debian-Builder/bin/chilkat-9.5.0-python-2.7-armv7a-hardfp-linux

	#Cron battery checker
	echo '* *     * * *   root    /usr/local/tmeslogger/scripts/batteryChecker.sh' >> $DEST/sdcard/etc/crontab
}


choosing_kernel (){
	#--------------------------------------------------------------------------------------------------------------------------------
	# Choose which kernel to use
	#--------------------------------------------------------------------------------------------------------------------------------
	cd $DEST"/kernel/"
	if [[ $BRANCH == *next* ]]; then
		MYLIST=`for x in $(ls -1 *next*.tar); do echo $x " -"; done`
	else
		MYLIST=`for x in $(ls -1 *.tar | grep -v next); do echo $x " -"; done`
	fi
	WC=`echo $MYLIST | wc -l`
	if [[ $WC -ne 0 ]]; then
		whiptail --title "Choose kernel archive" --backtitle "Which kernel do you want to use?" --menu "" 12 60 4 $MYLIST 2>results
	fi
	CHOOSEN_KERNEL=$(<results)
	rm results
}


install_external_applications (){
	#--------------------------------------------------------------------------------------------------------------------------------
	# Install external applications
	#--------------------------------------------------------------------------------------------------------------------------------
	echo "------ Installing external applications"

	#TODO
	# some aditional stuff. Some driver as example
	if [[ -n "$MISC2_DIR" ]]; then
		# https://github.com/pvaret/rtl8192cu-fixes
		cd $DEST/$MISC2_DIR
		git checkout 0ea77e747df7d7e47e02638a2ee82ad3d1563199
		make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- clean && make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KSRC=$DEST/$LINUXSOURCE/
		cp *.ko $DEST/sdcard/usr/local/bin
		cp blacklist*.conf $DEST/sdcard/etc/modprobe.d/
	fi
}


fingerprint_image (){
	#--------------------------------------------------------------------------------------------------------------------------------
	# Saving build summary to the image
	#--------------------------------------------------------------------------------------------------------------------------------
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
	echo "Author:			$MAINTAINER , $MAINTAINERMAIL" >> $1
	echo "Sources:			https://github.com/JHSawatzki/Lime2-Debian-Builder/" >> $1
	echo "" >> $1
	echo "" >> $1
	echo "" >> $1
	echo "--------------------------------------------------------------------------------" >> $1
	echo "" >> $1
	cat $SRC/Lime2-Debian-Builder/LICENSE >> $1
	echo "" >> $1
	echo "--------------------------------------------------------------------------------" >> $1
}


closing_image (){
	#--------------------------------------------------------------------------------------------------------------------------------
	# Closing image and clean-up
	#--------------------------------------------------------------------------------------------------------------------------------
	echo "------ Closing image"

	rm $DEST/sdcard /usr/share/info/dir.old
	rm $DEST/sdcard/var/cache/debconf/*.dat-old
	rm $DEST/sdcard/var/log/{bootstrap,dpkg}.log
	rm $DEST/sdcard/var/log/*.?
	rm $DEST/sdcard/tmp/*
	for a in $DEST/sdcard/var/log/{*.log,apt/*.log,debug,dmesg,faillog,messages,syslog,wtmp} do > $a; done
	rm $DEST/sdcard/var/cache/apt/* 
	rm $DEST/sdcard/var/lib/apt/lists/*

	rm $DEST/sdcard/etc/adjtime

	chroot $DEST/sdcard /bin/bash -c "sync"
	sync
	sleep 3

	# unmount proc, sys and dev from chroot
	umount -l $DEST/sdcard/dev/pts
	umount -l $DEST/sdcard/dev
	umount -l $DEST/sdcard/proc
	umount -l $DEST/sdcard/sys
	umount -l $DEST/sdcard/tmp

	# let's create nice file name
	VERSION=$VERSION" "$VER
	VERSION="${VERSION// /_}"
	VERSION="${VERSION//$BRANCH/}"
	VERSION="${VERSION//__/_}"

	# kill process inside
	KILLPROC=$(ps -uax | pgrep ntpd |        tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi
	KILLPROC=$(ps -uax | pgrep dbus-daemon | tail -1); if [ -n "$KILLPROC" ]; then kill -9 $KILLPROC; fi

	# same info outside the image
	cp $DEST/sdcard/root/readme.txt $DEST/
	sleep 2
	rm $DEST/sdcard/usr/bin/qemu-arm-static
	umount -l $DEST/sdcard/
	sleep 2
	losetup -d $LOOP
	rm -rf $DEST/sdcard/

	# write bootloader
	LOOP=$(losetup -f)
	losetup $LOOP $DEST/debian_rootfs.raw
	cd /tmp
	tar xvfz $DEST"/u-boot-image/"$CHOOSEN_UBOOT
	dd if=u-boot-sunxi-with-spl.bin of=$LOOP bs=1024 seek=8 status=noxfer
	sync
	sleep 3
	losetup -d $LOOP
	sync
	sleep 2
	mv $DEST/debian_rootfs.raw $DEST/$VERSION.raw
	cd $DEST/
	
	# creating MD5 sum
	sync
	md5sum $VERSION.raw > $VERSION.md5
	cp $SRC/Lime2-Debian-Builder/bin/imagewriter.exe .
	md5sum imagewriter.exe > imagewriter.md5
	zip $VERSION.zip $VERSION.* readme.txt imagewriter.*
	rm $VERSION.raw $VERSION.md5 imagewriter.* readme.txt
}
