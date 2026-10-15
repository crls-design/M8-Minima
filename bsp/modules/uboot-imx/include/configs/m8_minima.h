/* SPDX-License-Identifier: GPL-2.0+ */
/*
 * Copyright 2019 NXP
 */

#ifndef __M8_MINIMA_H
#define __M8_MINIMA_H

#include <linux/sizes.h>
#include <linux/stringify.h>
#include <asm/arch/imx-regs.h>

#define UBOOT_ITB_OFFSET			0x57C00
#define FSPI_CONF_BLOCK_SIZE		0x1000
#define UBOOT_ITB_OFFSET_FSPI  \
	(UBOOT_ITB_OFFSET + FSPI_CONF_BLOCK_SIZE)
#ifdef CONFIG_FSPI_CONF_HEADER
#define CFG_SYS_UBOOT_BASE  \
	(QSPI0_AMBA_BASE + UBOOT_ITB_OFFSET_FSPI)
#else
#define CFG_SYS_UBOOT_BASE	\
	(QSPI0_AMBA_BASE + 0x300 * 512)
#endif

#ifdef CONFIG_XPL_BUILD
/* malloc f used before GD_FLG_FULL_MALLOC_INIT set */
#define CFG_MALLOC_F_ADDR		0x930000
/* For RAW image gives a error info not panic */

#endif

/* Link Definitions */

#define CFG_SYS_INIT_RAM_ADDR        0x40000000
#define CFG_SYS_INIT_RAM_SIZE        0x200000

#define CFG_SYS_SDRAM_BASE           0x40000000
#define PHYS_SDRAM                      0x40000000
/* 4GB LPDDR4: 3GB below the 4GB boundary, remaining 1GB above it */
#define PHYS_SDRAM_SIZE			0xC0000000
#define PHYS_SDRAM_2			0x100000000
#define PHYS_SDRAM_2_SIZE		0x40000000

#define CFG_FEC_MXC_PHYADDR          1

#define CFG_MXC_UART_BASE		UART_BASE_ADDR(2)

#define CFG_SYS_FSL_USDHC_NUM	2
#define CFG_SYS_FSL_ESDHC_ADDR	0

#define CFG_SYS_NAND_BASE           0x20000000

#ifdef CONFIG_IMX_MATTER_TRUSTY
#define NS_ARCH_ARM64 1
#endif

#ifdef CONFIG_IMX_MATTER_TRUSTY
#define NS_ARCH_ARM64 1
#endif

#ifdef CONFIG_ANDROID_SUPPORT
#include "imx8mm_evk_android.h"
#endif

#endif
