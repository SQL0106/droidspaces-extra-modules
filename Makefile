# SPDX-License-Identifier: GPL-2.0-only
# Build one module at a time: make TARGET=macvlan
# KDIR is provided by the DDK image (/opt/ddk/kdir/android14-6.1).

TARGET ?= macvlan

obj-m := $(TARGET).o
$(TARGET)-objs := modules/$(TARGET)/$(TARGET).o

ccflags-y += -Wno-declaration-after-statement

ifeq ($(TARGET),macvlan)
# The header uses IS_ENABLED(CONFIG_MACVLAN); tell it this is a module build.
ccflags-y += -DCONFIG_MACVLAN_MODULE=1
endif

KDIR ?= /opt/ddk/kdir/android14-6.1
MDIR := $(realpath $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

.PHONY: all clean
all:
	$(MAKE) -C $(KDIR) M=$(MDIR) TARGET=$(TARGET) modules

clean:
	$(MAKE) -C $(KDIR) M=$(MDIR) TARGET=$(TARGET) clean
