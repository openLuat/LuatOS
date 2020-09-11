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

#ifndef _TTS_CONFIG_H_
#define _TTS_CONFIG_H_

// Auto generated. Don't edit it manually!

#define LOG_TAG_TTS OSI_MAKE_LOG_TAG('T', 'T', 'S', ' ')

/**
 * Whether TTS player is supported
 */
#define CONFIG_TTS_ENABLE

/**
 * Wheth the dummy TTS engine is enabled.
 *
 * When a real TTS engine is used, it must be disabled.
 */
/* #undef CONFIG_TTS_DUMMY_SUPPORT */

/**
 * TTS thread stack size in bytes
 */
/* #undef CONFIG_TTS_STACK_SIZE */

/**
 * TTS output PCM sample rate
 */
/* #undef CONFIG_TTS_PCM_SAMPLE_RATE */

#endif
