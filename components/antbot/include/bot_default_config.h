/**
 * @file bot_default_config.h
 * @brief bot config header file
 * @details This header file defines the config of bot
 *
 * @copyright Copyright (C) 2015-2022 Ant Group Holding Limited
 */

#ifndef __BOT_DEFAULT_CONFIG_H__
#define __BOT_DEFAULT_CONFIG_H__

#include "bot_platform_user_config.h"

#ifdef __cplusplus
extern "C"
{
#endif

/* stimer config */
#ifndef  BOT_COMP_STIMER
#define  BOT_COMP_STIMER   1
#endif

/* LOG config */
#ifndef  BOT_COMP_LOG
#define  BOT_COMP_LOG   0
#endif

/* LOG macro config */
#if BOT_COMP_LOG == 1
#ifndef  BOT_LOG_USE
#define  BOT_LOG_USE   1
#endif
#endif

/* KV config */
#ifndef  BOT_COMP_KV
#define  BOT_COMP_KV    0
#endif

/* AT config */
#ifndef  BOT_COMP_AT
#define  BOT_COMP_AT    0
#endif

/* GNSS config */
#ifndef  BOT_COMP_GNSS
#define  BOT_COMP_GNSS  0
#endif

/* MEM config */
#ifndef  BOT_COMP_MEM
#define  BOT_COMP_MEM   0
#endif

#ifdef BOT_DEBUG
#define BOT_LOG_GLOBAL_LVL                LOG_DEBUG
#else
#define BOT_LOG_GLOBAL_LVL                LOG_INFO
#endif

#ifdef __cplusplus
}
#endif

#endif /* __BOT_CONFIG_H__ */

