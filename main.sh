#!/bin/bash
#
# Based on the original work of Igor Pecovnik:
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# Portions Copyright (c) 2015 Jan Henrik Sawatzki, info@tm**.de
#

#
# Main
#


# Abort on error
set -e


#--------------------------------------------------------------------------------------------------------------------------------
# currently there is no option to create an image without root
# you can compile a kernel but you can complete the whole process
# if you find a way, please submit code corrections. Thanks.
#--------------------------------------------------------------------------------------------------------------------------------
if [ "$UID" -ne 0 ]
	then echo "Please run as root"
	exit
fi


# sources
SOURCES=$SRC/sources
mkdir -p $SOURCES

# output
DEST=$SRC/output
mkdir -p $DEST

# output sdcard
SDCARD=$DEST/sdcard
mkdir -p $SDCARD

# output rootfs
ROOTFS=$DEST/rootfs
mkdir -p $ROOTFS

# output u-boot
BOOTDEST=$DEST/u-boot
mkdir -p $BOOTDEST

#output kernel
KERNELDEST=$DEST/kernel
mkdir -p $KERNELDEST

# source tmeslogger
SRCTMESLOGGER=$SRC/tmeslogger
if [ ! -d "$SRCTMESLOGGER" ]; then
	echo "TMESLogger source code not available!"
	exit
fi

# source tmeslogger scripts
SRCTMESLOGGERSCRIPTS=$SRC/tmeslogger/scripts


#--------------------------------------------------------------------------------------------------------------------------------
# Get your PGP key signing password
#--------------------------------------------------------------------------------------------------------------------------------
if [ "$GPG_PASS" == "" ]; then
	GPG_PASS=$(whiptail --passwordbox "\nPlease enter your GPG signing password or leave blank for none. \n\nEnd users - ignore - leave blank. " 14 50 --title "Package signing" 3>&1 1>&2 2>&3)
	exitstatus=$?
	if [ $exitstatus != 0 ]; then
		exit;
	fi
fi


#--------------------------------------------------------------------------------------------------------------------------------
# common for default allwinner kernel-source
#--------------------------------------------------------------------------------------------------------------------------------
#BOOTLOADER_REPOSITORY="https://github.com/RobertCNelson/u-boot.git"
BOOTLOADER="git://git.denx.de/u-boot.git"
BOOTSOURCE="u-boot"
BOOTCONFIG="A20-OLinuXino-Lime2_defconfig"


TOOLS_REPOSITORY="https://github.com/linux-sunxi/sunxi-tools.git"
TOOLSSOURCE="sunxi-tools"


EXODRIVER_REPOSITORY="https://github.com/labjack/exodriver.git"
EXODRIVERSOURCE="exodriver"


LABJACK_REPOSITORY="https://github.com/labjack/LabJackPython.git"
LABJACKSOURCE="LabJackPython"


PYA20LIME2S_REPOSITORY="https://pypi.python.org/packages/source/p/pyA20Lime2/pyA20Lime2-0.2.0.tar.gz"
PYA20LIME2SOURCE="pyA20Lime2-0.2.0"


CHILKAT_REPOSITORY="https://www.chilkatsoft.com/download/9.5.0.48/chilkat-9.5.0-python-2.7-armv7a-hardfp-linux.tar.gz"
CHILKATSOURCE="chilkat-9.5.0-python-2.7-armv7a-hardfp-linux"


#--------------------------------------------------------------------------------------------------------------------------------
# common for mainline kernel-source
#--------------------------------------------------------------------------------------------------------------------------------
if [[ $KERNELBRANCH == "mainline" ]]; then
	# All next compilations are using mainline u-boot & kernel
	LINUXKERNEL_REPOSITORY="git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git"
	LINUXSOURCE="linux-mainline"
	LINUXCONFIG="linux-sunxi-next"
else
	LINUXKERNEL_REPOSITORY="https://github.com/dan-and/linux-sunxi"
	LINUXSOURCE="linux-sunxi"
	LINUXCONFIG="linux-sunxi"
fi


#--------------------------------------------------------------------------------------------------------------------------------
# Load libraries
#--------------------------------------------------------------------------------------------------------------------------------
source $BUILDER/common.sh


#--------------------------------------------------------------------------------------------------------------------------------
# The name of the job
#--------------------------------------------------------------------------------------------------------------------------------
VERSION="lime2 Debian $REVISION wheezy $KERNELBRANCH"
if [[ $U6PRO == "yes" ]]; then
	VERSION=$VERSION" U6Pro"
fi


#--------------------------------------------------------------------------------------------------------------------------------
# optimize build time with 100% CPU usage
#--------------------------------------------------------------------------------------------------------------------------------
CPUS=$(grep -c 'processor' /proc/cpuinfo)
if [ "$USEALLCORES" = "yes" ]; then
	CTHREADS="-j$(($CPUS + $CPUS/2))";
else
	CTHREADS="-j${CPUS}";
fi


#--------------------------------------------------------------------------------------------------------------------------------
# to display build time at the end
#--------------------------------------------------------------------------------------------------------------------------------
start=`date +%s`


#--------------------------------------------------------------------------------------------------------------------------------
# display what we are doing
#--------------------------------------------------------------------------------------------------------------------------------
clear
echo "Building $VERSION."


#--------------------------------------------------------------------------------------------------------------------------------
# download packages for host
#--------------------------------------------------------------------------------------------------------------------------------
download_host_packages


#--------------------------------------------------------------------------------------------------------------------------------
# display what we are doing
#--------------------------------------------------------------------------------------------------------------------------------
clear
echo "Building $VERSION."


#--------------------------------------------------------------------------------------------------------------------------------
# fetch_from_github [repository, sub directory]
#--------------------------------------------------------------------------------------------------------------------------------
fetch_from_github "$BOOTLOADER_REPOSITORY" "$BOOTSOURCE"
fetch_from_github "$LINUXKERNEL_REPOSITORY" "$LINUXSOURCE"
fetch_from_github "$TOOLS_REPOSITORY" "$TOOLSSOURCE"
fetch_from_github "$EXODRIVER_REPOSITORY" "$EXODRIVERSOURCE"
fetch_from_github "$LABJACK_REPOSITORY" "$LABJACKSOURCE"


#--------------------------------------------------------------------------------------------------------------------------------
# Patching sources
#--------------------------------------------------------------------------------------------------------------------------------
#
patching_sources


#--------------------------------------------------------------------------------------------------------------------------------
# Compile source or choose already packed kernel
#--------------------------------------------------------------------------------------------------------------------------------
if [[ $KERNEL_COMPILE == "yes" ]]; then
	# compile kernel and create archives
	compile_kernel
else
	# choose kernel from ready made
	choosing_kernel
	if [ ! -f "$KERNELDEST/$CHOOSEN_KERNEL" ]; then
		# compile kernel and create archives
		compile_kernel
	fi
fi

if [ "$KERNEL_ONLY" == "yes" ]; then
	echo "Kernel building done."
	echo "Target directory: $DEST/output/kernel"
	echo "File name: $CHOOSEN_KERNEL"
	exit
fi

if [[ $BOOT_COMPILE == "yes" ]]; then
	# compile u-boot
	compile_uboot
else
	# choose u-boot
	choosing_uboot
	if [ ! -f "$BOOTDEST/$CHOOSEN_UBOOT" ]; then
		# compile u-boot
		compile_uboot
	fi
fi

if [[ $TOOLS_COMPILE == "yes" ]]; then
	# compile sunxi tools
	compile_sunxi_tools
else
	if [ ! -f "$DEST/fex2bin" ] || [ ! -f "$DEST/bin2fex" ]; then
		# compile sunxi tools
		compile_sunxi_tools
	fi
fi

if [[ $CREATE_ROOTFS == "yes" ]]; then
	if [ -f "$ROOTFS/wheezy.raw.gz" ]; then
		rm $ROOTFS/wheezy.raw.gz
	fi
fi


#--------------------------------------------------------------------------------------------------------------------------------
# create or use prepared root file-system
#--------------------------------------------------------------------------------------------------------------------------------
create_image_template

mount_existing_image


#--------------------------------------------------------------------------------------------------------------------------------
# add kernel to the image
#--------------------------------------------------------------------------------------------------------------------------------
install_kernel


#--------------------------------------------------------------------------------------------------------------------------------
# add some summary to the image
#--------------------------------------------------------------------------------------------------------------------------------
fingerprint_image "$SDCARD/root/readme.txt"


#--------------------------------------------------------------------------------------------------------------------------------
# closing image
#--------------------------------------------------------------------------------------------------------------------------------
closing_image


end=`date +%s`
runtime=$(((end-start)/60))
echo "Runtime $runtime min."