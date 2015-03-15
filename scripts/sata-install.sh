#!/bin/bash
#
# Copyright (c) 2014 Igor Pecovnik, igor.pecovnik@gma**.com
# Copyright (c) 2015 JH Sawatzki, info@ib-msawa.....de
#
# www.igorpecovnik.com / images + support
#
# SATA and USB ARM rootfs install
#
# Should work with: Lime2
#


#--------------------------------------------------------------------------------------------------------------------------------
# we don't need to copy all files. This is the exclusion list
#--------------------------------------------------------------------------------------------------------------------------------
cat > .install-exclude <<EOF
/dev/*
/proc/*
/sys/*
/media/*
/mnt/*
/run/*
/tmp/*
/boot/*
/root/*
EOF


#--------------------------------------------------------------------------------------------------------------------------------
# Let's see where we are running from ?
#--------------------------------------------------------------------------------------------------------------------------------
SOURCE=$(dmesg |grep root)
SOURCE=${SOURCE#"${SOURCE%%root=*}"}
SOURCE=`echo $SOURCE| cut -d' ' -f 1`
SOURCE="${SOURCE//root=/}"


#--------------------------------------------------------------------------------------------------------------------------------
# Which kernel and bin do we run
#--------------------------------------------------------------------------------------------------------------------------------
if [ -f /boot/boot.cmd ]; then
	KERNEL=$(cat /boot/boot.cmd |grep vmlinuz |awk '{print $NF}')
	BINFILE=$(cat /boot/boot.cmd |grep .bin |awk '{print $NF}')
fi


#--------------------------------------------------------------------------------------------------------------------------------
# How much space do we use?
#--------------------------------------------------------------------------------------------------------------------------------
USAGE=$(df -BM | grep ^/dev | head -1 | awk '{print $3}')
USAGE=${USAGE%?}


#--------------------------------------------------------------------------------------------------------------------------------
# What are our possible destinations?
#--------------------------------------------------------------------------------------------------------------------------------
# SATA

SDA_ROOT_PART=""

if [ "$(grep sda /proc/partitions)" != "" ]; then
	# We have something as sd, check size
	SDA_SIZE=$(awk 'BEGIN { printf "%.0f\n", '$(grep sda /proc/partitions | awk '{print $3}' | head -1)'/1024 }')
	# Check which type is this drive - SATA or USB
	SDA_TYPE=$(udevadm info --query=all --name=sda | grep ID_BUS=)
	SDA_TYPE=${SDA_TYPE#*=}
	SDA_NAME=$(udevadm info --query=all --name=sda | grep ID_MODEL=)
	SDA_NAME=${SDA_NAME#*=}
	SDA_ROOT_PART=/dev/sda1
fi


#--------------------------------------------------------------------------------------------------------------------------------
# Prepare main selection
#--------------------------------------------------------------------------------------------------------------------------------

# exit if none avaliable
if [ "$SDA_ROOT_PART" == "" ]; then echo "No target available"; exit; fi

# partition if target not partitioned
if [[ -z $(cat /proc/partitions | grep sda1) ]]; then
	echo "Partition device /dev/sda";
	echo -e "o\nn\np\n1\n\n\nw" | fdisk /dev/sda
fi


#--------------------------------------------------------------------------------------------------------------------------------
# SATA install can be done in one step
#--------------------------------------------------------------------------------------------------------------------------------
clear
whiptail --title "SATA & USB install" --infobox "Formatting and optimizing $SDA_TYPE rootfs ..." 7 60
mkfs.ext4 /dev/sda1 > /dev/null 2>&1
mount /dev/sda1 /mnt
sync
sleep 2
whiptail --title "$SDA_TYPE install" --infobox "Checking and counting files." 7 60
TODO=$(rsync -avrltD --delete --stats --human-readable --dry-run --exclude-from=.install-exclude  /  /mnt |grep "^Number of files:"|awk '{print $4}')
TODO="${TODO//./}"
TODO="${TODO//,/}"
whiptail --title "$SDA_TYPE install" --infobox "Copy / creating rootfs on $SDA_TYPE: $TODO files." 7 60
rsync -avrltD --delete --stats --human-readable --exclude-from=.install-exclude  /  /mnt | pv -l -e -p -s "$TODO" >/dev/null
if [[ $SOURCE == *nand*  ]]; then
	# change fstab
	sed -e 's/nand2/sda1/g' -i /mnt/etc/fstab
else
	if [[ $KERNEL == *"3.4"*  ]]; then
		sed -e 's,root=\/dev\/mmcblk0p1,root=/dev/sda1,g' -i /boot/boot.cmd
		mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
	else
		sed -e 's,root=\/dev\/mmcblk0p1,root=/dev/sda1,g' -i /boot/boot-next.cmd
		if [ -f /boot/boot-next.cmd ]; then
			mkimage -C none -A arm -T script -d /boot/boot-next.cmd /boot/boot.scr
		fi
	fi
	# change fstab
	sed -e 's/mmcblk0p1/sda1/g' -i /mnt/etc/fstab
	sed -i "s/data=writeback,//" /mnt/etc/fstab
	mkdir -p /mnt/media/mmc
	echo "/dev/mmcblk0p1        /media/mmc   ext4    defaults        0       0" >> /mnt/etc/fstab
	echo "/media/mmc/boot   /boot   none    bind        0       0" >> /mnt/etc/fstab
fi