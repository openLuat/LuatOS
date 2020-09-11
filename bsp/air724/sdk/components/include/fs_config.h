/* Copyright (C) 2018 RDA Technologies Limited and/or its affiliates("RDA").
 * All rights reserved.
 *
 * This software is supplied "AS IS" without any warranties.
 * RDA assumes no responsibility or liability for the use of the software,
 * conveys no license or title under any patent, copyright, or mask work
 * right to the product. RDA reserves the right to make changes in the
 * software without notification.  RDA also make no representation or
 * warranty that such application will be suitable for the specified use
 * without further testing or modification.
 */

#ifndef _FS_CONFIG_H_
#define _FS_CONFIG_H_

// Auto generated. Don't edit it manually!

/**
 * whether flash block device default to be v1
 *
 * It is known v1 is not power failure safe. Not to use it.
 */
/* #undef CONFIG_FS_FBDEV_DEFAULT_V1 */

/**
 * whether flash block device default to be v2
 */
#define CONFIG_FS_FBDEV_DEFAULT_V2

/**
 * whether flash block device v1 is supported
 */
/* #undef CONFIG_FS_FBDEV_V1_SUPPORTED */

/**
 * whether flash block device v2 is supported
 */
#define CONFIG_FS_FBDEV_V2_SUPPORTED

/**
 * whether to format on mounting flash file system failure
 *
 * It is highly recommended not to format on failure.
 */
/* #undef CONFIG_FS_FORMAT_FLASH_ON_MOUNT_FAIL */

/**
 * whether to mount sdcard
 */
#define CONFIG_FS_MOUNT_SDCARD

/**
 * whether to format on mounting sdcard file system failure
 */
#define CONFIG_FS_FORMAT_SDCARD_ON_MOUNT_FAIL

/**
 * sdcard file system mount point
 */
#define CONFIG_FS_SDCARD_MOUNT_POINT "/sdcard0"

#endif
