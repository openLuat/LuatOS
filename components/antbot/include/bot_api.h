/**
 * @file bot_api.h
 * @brief blockchain of things core api
 * @copyright Copyright (C) 2015-2022 Ant Group Holding Limited
 */
#ifndef __BOT_API_H__
#define __BOT_API_H__

#if defined(__cplusplus)
extern "C" {
#endif

#include "bot_typedef.h"

/** @def BOT_CONFIG_BUF_MIN_LEN
    @brief the minimum length of the @ref bot_config_get buf
*/
#define BOT_CONFIG_BUF_MIN_LEN (128)

///bot msg notify type
typedef enum {
    /**
     * @brief initial invalid value
     */
    BOT_MSG_UNAVAILABLE = 0,
    /**
     * @brief asset initialization fails, please follow the steps below to check:
     * 1. check if the network is connected
     * 2. check if imei number is provided to ant
     */
    BOT_MSG_INIT_FAILED,
    /**
     * @brief asset initialization succeeded, please use the API as follows:
     * 1. call @ref bot_asset_status_get to query the registration status
     * 2. if status is not equal to 1, call @ref bot_asset_register for asset registration
     */
    BOT_MSG_INIT_SUCESS,
    /**
     * @brief Asset registration failed, please follow the steps below to troubleshoot:
     * 1. check asset_id format
     * 2. check asset_type format
     * 3. check asset_dataver format
     * 4. provide error codes to ant to assist in troubleshooting
     */
    BOT_MSG_REG_FAILED,
    /**
     * @brief asset registration is successful, now you can call @ref bot_data_publish to send data
     */
    BOT_MSG_REG_SUCESS,
    /**
    * @brief bot_data_publish failed to report, asynchronous callback result
    */
    BOT_MSG_PUB_FAILED,
    /**
     * @brief bot_data_publish reported successfully, asynchronous callback result
     */
    BOT_MSG_PUB_SUCESS,
    /**
     * @brief internal use
     */
    BOT_MSG_DATA_VERIFY_FAILED
} bot_msg_type_e;



/** @typedef void (*bot_msg_notify_callback_t)(bot_msg_type_e, void *)
 *
 *  @brief message notification callback function pointer
 *
 *  @param[in] bot_msg_type_e msg notefy type, for more information please refer to @ref bot_msg_type_e
 *  @param[in] void*  reserve
*/
typedef void (*bot_msg_notify_callback_t)(bot_msg_type_e, void *);


/**
 * @brief init bot(blockchain of things) service
 *
 * @return int
 * @retval 0 success
 * @retval otherwise failed see @ref bot_errno.h
 */
int bot_init(void);

/**
 * @brief register message notify callback
 *
 * @param[in]  notify  the type of register message callback.
 * @param[in]  args    the reserved arg
 *
 * @return int
 * @retval 0 success
 * @retval otherwise failed see @ref bot_errno.h
 */
int bot_msg_notify_callback_register(bot_msg_notify_callback_t notify, void *args);

/**
 * @brief get bot(blockchain of things) sdk version
 *
 * @return const char*
 * @retval NULL get sdk version fail
 * @return otherwise sdk version
 */
const char *bot_version_get(void);

/**
 * @brief start bot(blockchain of things) asset registration
 *
 * @param[in]  asset_id asset ID,must to be unique, the length is greater than 0 and less than 64 bytes,
 * and can only contain uppercase and lowercase letters, numbers, and symbols "_", ".", "-"
 * @param[in]  asset_type device type, the format is "xxxx-yyyy"
 *                        xxxx: equipment type code, refer to the project information table
 *                        yyyy: device model, a user-defined character string,
 *                              which can only contain uppercase and lowercase letters, numbers, and symbols "_", "."
 * @param[in]  asset_dataver data version of asset to register. the default value is "ADV1.0"
 *
 * @return int
 * @retval >=0 success
 * @retval otherwise failed see @ref bot_errno.h
 */
int bot_asset_register(char *asset_id, char *asset_type, char *asset_dataver);

/**
 * @brief publish data to the bot(blockchain of things)
 *
 * @param[in]  data  data to publish, it must be cjson format in string.
 * @param[in]  len   the data length must be less than 1024
 *
 * @return int
 * @retval >=0 success, >0 indicates msg_id
 * @retval otherwise failed see @ref bot_errno.h
 */
int bot_data_publish(uint8_t *data, int len);

/**
 * @brief query device connection status
 *
 * @return int
 * @retval 0 disconnect, channel enabled
 * @retval 1 connect, channel enabled
 * @retval 2 disconnect, channel disabled
 * @retval 3 invalid
 */
int bot_device_status_get(void);

/**
 * @brief query asset registration status
 *
 * @param[in]  asset_id ID of the asset to register,asset_id must to be unique
 *
 * @return int
 * @retval 0 - Module not activated, asset not registered
 * @retval 1 - Module activated, asset registered,
 * @retval 2 - Module activated, asset not registered
 * @retval other value means error see @ref bot_errno.h
 *
 */
int bot_asset_status_get(char *asset_id);

/**
 * @brief bot(blockchain of things) channel switch
 *
 * @param[in]  cmd  command for channel switch, 0 to off, 1 to on
 *
 * @return int
 * @retval 0 success
 * @retval otherwise failed see @ref bot_errno.h
 */
int bot_channel_switch(int cmd);

/**
 * @brief set product information
 *
 * @param[in]  config  obtained in the project information sheet
 *
 * @return int
 * @retval 0 success
 * @retval otherwise failed see @ref bot_errno.h
 */
int bot_config_set(const char *config);

/**
 * @brief get product information
 *
 * @param[in]   buf_len the length of the config array, must be greater than @ref BOT_CONFIG_BUF_MIN_LEN
 * @param[out]  config  get product information
 *
 * @return int
 * @retval 0 success
 * @retval otherwise failed see @ref bot_errno.h
 */
int bot_config_get(char *config, int buf_len);

/**
 * @brief pac data of the bot(blockchain of things)
 *
 * @param[in]      format    1:JSON, 0: Binary
 * @param[in]      data_in   data to be packed
 * @param[in]      inlen     the length of input data
 * @param[out]     data_out  data after packing
 * @param[in out]  outlen    in: the length of the output buffer. out: the real length of the data.
 *
 * @return int
 * @retval 0 success
 * @retval otherwise failed see @ref bot_errno.h
 */
int bot_data_pac(int format, uint8_t *data_in, int inlen, uint8_t *data_out, int *outlen);

#if defined(__cplusplus)
}
#endif

#endif /* __BOT_API_H__ */
