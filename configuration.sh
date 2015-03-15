#!/bin/bash
#
# Copyright (c) 2014 Igor Pecovnik, igor.pecovnik@gma**.com
#
# www.igorpecovnik.com / images + support
#
# Board definitions
#


#--------------------------------------------------------------------------------------------------------------------------------
# common for default allwinner kernel-source
#--------------------------------------------------------------------------------------------------------------------------------
BOOTLOADER="https://github.com/RobertCNelson/u-boot"
BOOTSOURCE="u-boot"


LINUXKERNEL="https://github.com/dan-and/linux-sunxi"
LINUXSOURCE="linux-sunxi"
LINUXCONFIG="linux-sunxi"

FIRMWARE="bin/ap6210.zip"


CPUMIN="480000"
CPUMAX="1010000"


MISC1="https://github.com/linux-sunxi/sunxi-tools.git"
MISC1_DIR="sunxi-tools"


MISC2="https://github.com/dz0ny/rt8192cu"
MISC2_DIR="rt8192cu"


#MISC3=""
#MISC3_DIR=""


#--------------------------------------------------------------------------------------------------------------------------------
# common for mainline kernel-source
#--------------------------------------------------------------------------------------------------------------------------------
if [[ $BRANCH == *next* ]]; then
	# All next compilations are using mainline u-boot & kernel
	LINUXKERNEL="git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git"
	LINUXSOURCE="linux-mainline"
	LINUXCONFIG="linux-sunxi-next"

	FIRMWARE=""
fi


#--------------------------------------------------------------------------------------------------------------------------------
# Olimex Lime 2
#--------------------------------------------------------------------------------------------------------------------------------
BOOTCONFIG="A20-OLinuXino-Lime2_defconfig"
MODULES="gpio_sunxi spi_sun7i"
MODULES_NEXT=""
