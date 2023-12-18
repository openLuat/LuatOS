/**
 * @file bot_vendor.h
 * @brief Standard Mode Adaptation Interface
 *
 * @copyright Copyright (C) 2015-2022 Ant Group Holding Limited
 */
#ifndef __BOT_VENDOR_H__
#define __BOT_VENDOR_H__

#include "bot_network.h"

#if defined(__cplusplus)
extern "C" {
#endif


/**
 * @brief get network register mode.
 * @return netctrl status
 * @retval 0 manual mode
 * @retval 1 auto mode
 */
int bot_network_netctrl_status_get(void);

/**
 * @brief set network register mode.
 * @param[in] status 1: auto mode, 0: manual mode.
 * @return set result
 * @retval 0 success
 * @retval others failed
 */
int bot_network_netctrl_status_set(int status);

/**
 * @brief get network status.
 * @return see @ref bot_net_status_e
 */
bot_net_status_e bot_network_status_get(void);

/**
 * @brief set maas channel sim id and cid, must be called before @ref bot_maas_init
 * @note  maas channel default sim id is 0, cid is 3
 *  users can set their own cid, but do not conflict with the existing cid
 *
 * @param[in] sim sim card index
 * @param[in] cid PDP channel index
 *
 * @return set result
 * @retval 0 success
 * @retval others failed
 *
 */
int bot_network_sim_cid_set(int sim, int cid);

/**
 * @brief get maas channel sim id and cid
 *
 * @param[out] sim sim card index
 * @param[out] cid PDP channel index
 *
 * @return set result
 * @retval 0 success
 * @retval others failed
 *
 */
int bot_network_sim_cid_get(int *sim, int *cid);

/**
 * @brief Format the input error code to string
 *
 * @param[in] error_code error code number
 * @param[out] errno_buff: buffer to store the formatted string, buffer length is not less than 12
 * @param[in] len length of errno_buff
 *
 * @return format result
 * @retval 0 success
 * @retval -1 failed
 */
int bot_errno_fmt(int error_code, char *errno_buff, unsigned int len);

/**
 * @brief Get the test cmd return of AT command
 *
 * @param[in] cmd_str AT command (example: AT+MAASREGSTATUS)
 * @return test string (example: +MAASREGSTATUS: 64)
 * @retval NULL failed
 * @retval others string pointer
 */
const char *bot_at_test_cmd_get(const char *cmd_str);

/**
 * @brief MaaS debug set/get
 *
 * @param[in] para_in input para, string format
 * @param[out] para_out address to store output para, at least 512 Bytes
 * @param[in/out] out_len: [in] the length of address; [out] the length of the output para;

 * @return command execution result On success, return 0
 * @retval 0 success
 * @retval others failed
 */
int bot_maas_debug(const char *para_in, char *para_out, unsigned int *out_len);

#if defined(__cplusplus)
}
#endif

#endif