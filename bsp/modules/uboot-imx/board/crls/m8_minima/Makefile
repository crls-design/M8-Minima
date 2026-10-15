#
# Copyright 2018 NXP
#
# SPDX-License-Identifier:      GPL-2.0+
#

obj-y += m8_minima.o
obj-y += ../../nxp/common/mmc.o

ifdef CONFIG_XPL_BUILD
obj-y += spl.o
ifdef CONFIG_IMX8M_4G_LPDDR4
obj-y += lpddr4_timing_4g.o
else
obj-$(CONFIG_IMX8M_LPDDR4) += lpddr4_timing.o
obj-$(CONFIG_IMX8M_DDR4) += ddr4_timing.o
endif
endif
