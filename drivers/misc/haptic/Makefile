# SPDX-License-Identifier: GPL-2.0
#
# Makefile for the input core drivers.
#

# Each configuration option enables a list of files.

obj-$(CONFIG_ICS_HAPTIC_DRV) += hapticdrv.o

hapticdrv-objs := haptic_drv.o rt6010.o haptic_util.o sfdc_drv.o

ifeq ($(CONFIG_ICS_HAPTIC_DRV_RICHTAP),y)
hapticdrv-objs += richtap_drv.o
endif
