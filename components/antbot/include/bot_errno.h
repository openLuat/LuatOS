/**
 * @file bot_errno.h
 * @brief bot error number header file
 *
 * @copyright Copyright (C) 2015-2022 Ant Group Holding Limited
 */

#ifndef __BOT_ERRNO_H__
#define __BOT_ERRNO_H__

#include "bot_typedef.h"

#ifdef __cplusplus
extern "C" {
#endif

/* -------------- General Error Code --------------------------- */
#define BOT_EMAAS_OK      0    /**< There is no error */
#define BOT_EMAAS_ERROR   -1    /**< A generic error happens */
#define BOT_EMAAS_NOMEM   -2    /**< No memory */
#define BOT_EMAAS_INVAL   -3    /**< Invalid argument */
/* ------------------------------------------------------------  */


/* -------------- Components&Service Error Code -----------------*/
#define BOT_ETYPE_NORMAL (0x00U << 24)
#define BOT_ETYPE_WARN   (0x01U << 24)
#define BOT_ETYPE_ERROR  (0x02U << 24)
#define BOT_ETYPE_FATAL  (0x03U << 24)

/* The MID represent each module */
typedef enum {
    BOT_MID_COMP_AT          = 0x00, /* AT component. */
    BOT_MID_COMP_CRYPTO      = 0x01, /* Crypto component. */
    BOT_MID_COMP_GNSS        = 0x02, /* GNSS component. */
    BOT_MID_COMP_KV          = 0x03, /* KV component. */
    BOT_MID_COMP_LOG         = 0x04, /* LOG component. */
    BOT_MID_COMP_MEM         = 0x05, /* MEM component. */
    BOT_MID_COMP_NET         = 0x06, /* NET component. */
    BOT_MID_COMP_TLV         = 0x07, /* TLV component. */
    BOT_MID_COMP_UTILS       = 0x08, /* UTILS component. */
    BOT_MID_COMP_CHAIN       = 0x09, /* UTILS component. */

    BOT_MID_SRV_DTC          = 0x30, /* Service : Data to Cloud/Chain*/
    BOT_MID_SRV_NTP          = 0x31, /* Service : NTP*/
    BOT_MID_MAX
} bot_module_id;

/* ------ Coin Macros for three Comp&Service Error Code segments. -------*/
/* Define bot fatal error, 32-bit unsigned integer error code */
#define BOT_ERRNO_FATAL(MID, ERRNO) \
    (-(BOT_ETYPE_FATAL |  ((uint32_t)(MID) << 16) | ((uint32_t)(ERRNO))))

/* Define bot critical error, 32-bit unsigned integer error code */
#define BOT_ERRNO_ERROR(MID, ERRNO) \
    (-(BOT_ETYPE_ERROR | ((uint32_t)(MID) << 16) | ((uint32_t)(ERRNO))))

/* Define bot warn, 32-bit unsigned integer error code */
#define BOT_ERRNO_WARN(MID, ERRNO) \
    (-(BOT_ETYPE_WARN | ((uint32_t)(MID) << 16) | ((uint32_t)(ERRNO))))

/* Define bot info, 32-bit unsigned integer error code */
#define BOT_ERRNO_NORMAL(MID, ERRNO) \
    (-(BOT_ETYPE_NORMAL | ((uint32_t)(MID) << 16) | ((uint32_t)(ERRNO))))
/* -------------------------------------------------------------------- */

/* It's a helper macro for record log, post to clond, etc. */
#define __BOT_ERROR_HANDLER(para1, para2, func, line) \
    BOT_LOGE(" [Func: %s] [Line: %d] 0X%08X 0X%08X\r\n",func, line, para1, para2)

#define __BOT_ERROR_RET_INT(errno, para1, para2, func, line) \
do{ \
    __BOT_ERROR_HANDLER(para1, para2, func, line); \
    return errno; \
}while(0)

#define __BOT_ERROR_RET_VOID(para1, para2, func, line) \
do{ \
    __BOT_ERROR_HANDLER(para1, para2, func, line); \
    return;\
}while(0)

#define __BOT_ERROR_RECORD(para1, para2, func, line) \
do{ \
    __BOT_ERROR_HANDLER(para1, para2, func, line); \
}while(0)

/*
 * Error Handle Macros . Record and return errcode.
 * @errno: errcode. signed interger.
 * @para1: user's parameter, signed integer.
 * @para2: user's parameter, signed integer.
 */
#define BOT_ERROR_RET_INT(errno, para1, para2)   __BOT_ERROR_RET_INT(errno, para1, para2, __func__, __LINE__)

/*
 * Error Handle Macros . Record and return void.
 * @para1: user's parameter, signed integer.
 * @para2: user's parameter, signed integer.
 */
#define BOT_ERROR_RET_VOID(para1, para2)         __BOT_ERROR_RET_VOID(para1, para2, __func__, __LINE__)

/*
 * Error Handle Macros . Record only.
 * @para1: user's parameter, signed integer.
 * @para2: user's parameter, signed integer.
 */
#define BOT_ERROR_RECORD(para1, para2)           __BOT_ERROR_RECORD(para1, para2, __func__, __LINE__)

/*
 * Assert-like macro to check, record and return errcode (for example, interface's return-code).
 * @pred: predicate (for example, ret!=0, ret!=NULL, a>b, etc.)
 * @ret: the return-code of checked interface or other variables.
 * @para1: user's parameter, signed integer.
 * @para2: user's parameter, signed integer.
 */
#define BOT_ERROR_PARA_RETINT_ASSERT(pred, ret, para1, para2) \
if (pred){ \
    __BOT_ERROR_HANDLER(para1, para2, __func__, __LINE__); \
    return ret; \
}

/*
 * Assert-like macro to check, record and return void.
 * @pred: predicate (for example, ret!=0, ret!=NULL, a>b, etc.)
 * @para1: user's parameter, signed integer.
 * @para2: user's parameter, signed integer.
 */
#define BOT_ERROR_PARA_RETVOID_ASSERT(pred, para1, para2) \
if (pred) { \
    __BOT_ERROR_HANDLER(para1, para2, __func__, __LINE__); \
    return; \
}

/*
 * Assert-like macro to check, record but not return .
 * @pred: predicate (for example, ret!=0, ret!=NULL, a>b, etc.)
 * @para1: user's parameter, signed integer.
 * @para2: user's parameter, signed integer.
 */
#define BOT_ERROR_PARA_RECORD_ASSERT(pred, para1, para2) \
if (pred) { \
    __BOT_ERROR_HANDLER(para1, para2, __func__, __LINE__); \
}

/*
 * Example:
 * =======>
 *      ret = bot_device_register_adv_check(...);
 *      if (ret != BOT_EMAAS_OK){
 *          BOT_LOGE("bot_device_register_adv_check fail %d \r\n", ret);
            return ret;
 *      }
 * =======>
 *      ret = bot_device_register_adv_check(...);
 *      BOT_ERROR_STR_RETINT_ASSERT(ret, "bot_device_register_adv_check fail");
 */
/*
 * Assert-like macro to check, record and return errcode if "if statement" is true.
 * @ret: the return-code of checked interface or other variables.
 * @desc: the description of ret that is a errcode.
 */
#define BOT_ERROR_STR_RETINT_ASSERT(ret, desc) \
if (ret != BOT_EMAAS_OK){ \
    BOT_LOGE(" [Func: %s] [Line: %d] %s\r\n",__func__, __LINE__, desc); \
    return ret; \
}
/*
 * Assert-like macro to check, record and return void if "if statement" is true.
 * @ret: the return-code of checked interface or other variables.
 * @desc: the description of ret that is a errcode.
 */
#define BOT_ERROR_STR_RETVOID_ASSERT(ret, desc) \
if (ret != BOT_EMAAS_OK){ \
    BOT_LOGE("[Func: %s] [Line: %d] %s\r\n",__func__, __LINE__, desc); \
    return; \
}

/*
 * Assert-like macro to check, record but not return if "if statement" is true.
 * @ret: the return-code of checked interface or other variables.
 * @desc: the description of ret that is a errcode.
 */
#define BOT_ERROR_STR_RECORD_ASSERT(ret, desc) \
if (ret != BOT_EMAAS_OK){ \
    BOT_LOGE("[Func: %s] [Line: %d] %s\r\n",__func__, __LINE__, desc); \
}

/* -------------------------------------------------------------------------------*/

/*
 * Name Format: BOT_E<MODULE_NAME>_<ERRCODE_NAME> .
 */
/* -------------------------- AT Components Errcode ------------------------------*/
#define BOT_EAT_OK                          BOT_ERRNO_ERROR(BOT_MID_COMP_AT, 0X0000) /* -0x02000000 */
#define BOT_EAT_PARA_NULL                   BOT_ERRNO_ERROR(BOT_MID_COMP_AT, 0X0001) /* -0x02000001 */
#define BOT_EAT_NUM_INV                     BOT_ERRNO_ERROR(BOT_MID_COMP_AT, 0X0002) /* -0x02000002 */
#define BOT_EAT_CMD_INV                     BOT_ERRNO_ERROR(BOT_MID_COMP_AT, 0X0003) /* -0x02000003 */
#define BOT_EAT_UART_INIT                   BOT_ERRNO_ERROR(BOT_MID_COMP_AT, 0X0004) /* -0x02000004 */
#define BOT_EAT_UART_CB_REG                 BOT_ERRNO_ERROR(BOT_MID_COMP_AT, 0X0005) /* -0x02000005 */
#define BOT_EAT_CMD_CB_REG                  BOT_ERRNO_ERROR(BOT_MID_COMP_AT, 0X0006) /* -0x02000006 */
#define BOT_EAT_TASK_CRT_FAIL               BOT_ERRNO_ERROR(BOT_MID_COMP_AT, 0X0007) /* -0x02000007 */
#define BOT_EAT_RE_INITIALIZE               BOT_ERRNO_ERROR(BOT_MID_COMP_AT, 0X0008) /* -0x02000008 */
/* -------------------------------------------------------------------------------*/

/* ------------------------- CRYPTO Components Errcode -------------------------- */
/* The ECDSA key input parameters are not complete */
#define BOT_ECRYPTO_KEYGEN_NULL             BOT_ERRNO_ERROR(BOT_MID_COMP_CRYPTO, 0X0000) /* -0x02010000 */
/* Failed to generate the ECDSA key */
#define BOT_ECRYPTO_KEYGEN                  BOT_ERRNO_ERROR(BOT_MID_COMP_CRYPTO, 0X0001) /* -0x02010001 */
/* Failed to generate the ECDSA signature */
#define BOT_ECRYPTO_SIGNGEN                 BOT_ERRNO_ERROR(BOT_MID_COMP_CRYPTO, 0X0002) /* -0x02010002 */
/* The input type error which is not in keypair and signature */
#define BOT_ECRYPTO_DATA_TYPE               BOT_ERRNO_ERROR(BOT_MID_COMP_CRYPTO, 0X0003) /* -0x02010003 */
/* Failed to save keypair or signature file */
#define BOT_ECRYPTO_SAVE_FILE               BOT_ERRNO_ERROR(BOT_MID_COMP_CRYPTO, 0X0004) /* -0x02010004 */
/* Failed to read keypair or signature file */
#define BOT_ECRYPTO_READ_FILE               BOT_ERRNO_ERROR(BOT_MID_COMP_CRYPTO, 0X0005) /* -0x02010005 */
/* Output is NULL */
#define BOT_ECRYPTO_OUTPUT_NULL             BOT_ERRNO_ERROR(BOT_MID_COMP_CRYPTO, 0X0006) /* -0x02010006 */
/* -------------------------------------------------------------------------------*/

/* ------------------------- GNSS Components Errcode ---------------------------- */
//#define BOT_EGNSS_XX                      BOT_ERRNO_ERROR(BOT_MID_COMP_GNSS, 0X0001) /* -0x02020001 */
//#define BOT_EGNSS_YY                      BOT_ERRNO_ERROR(BOT_MID_COMP_GNSS, 0X0002) /* -0x02020002 */
/* -------------------------------------------------------------------------------*/

/* ------------------------- KV Components Errcode ------------------------------ */
/* The space is out of range */
#define BOT_EKV_NO_SPACE                    BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X0001) /* -0x02030001 */
/* The parameter is invalid */
#define BOT_EKV_INVALID_PARAM               BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X0002) /* -0x02030002 */
/* The os memory malloc error */
#define BOT_EKV_MALLOC_FAILED               BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X0003) /* -0x02030003 */
/* Could not found the item */
#define BOT_EKV_NOT_FOUND                   BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X0004) /* -0x02030004 */
/* The flash read operation error */
#define BOT_EKV_FLASH_READ                  BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X0005) /* -0x02030005 */
/* The flash write operation error */
#define BOT_EKV_FLASH_WRITE                 BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X0006) /* -0x02030006 */
/* The flash erase operation error */
#define BOT_EKV_FLASH_ERASE                 BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X0007) /* -0x02030007 */
/* The error related to os lock */
#define BOT_EKV_OS_LOCK                     BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X0008) /* -0x02030008 */
/* The error related to os semaphose */
#define BOT_EKV_OS_SEM                      BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X0009) /* -0x02030009 */

/* Data encryption error */
#define BOT_EKV_ENCRYPT                     BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X000A) /* -0x0203000A */
/* Data decryption error */
#define BOT_EKV_DECRYPT                     BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X000B) /* -0x0203000B */
/* The function is not support yet */
#define BOT_EKV_NOT_SUPPORT                 BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X000C) /* -0x0203000C */
/* File open fail */
#define BOT_EKV_FILE_OPEN                   BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X000D) /* -0x0203000D */
/* File read fail */
#define BOT_EKV_FILE_READ                   BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X000E) /* -0x0203000E */
/* File write fail */
#define BOT_EKV_FILE_WRITE                  BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X000F) /* -0x0203000F */
/* File seek fail */
#define BOT_EKV_FILE_SEEK                   BOT_ERRNO_ERROR(BOT_MID_COMP_KV, 0X0010) /* -0x02030010 */
/* ------------------------------------------------------------------------------ */

/* ------------------------- LOG Components Errcode ----------------------------- */
//#define BOT_ELOG_XX                       BOT_ERRNO_ERROR(BOT_MID_COMP_LOG, 0X0001) /* -0x02040001 */
//#define BOT_ELOG_YY                       BOT_ERRNO_ERROR(BOT_MID_COMP_LOG, 0X0002) /* -0x02040002 */
/* ------------------------------------------------------------------------------ */

/* ------------------------- MEM Components Errcode ----------------------------- */
/* mem module mem infomation get failed */
#define BOT_EMEM_INFO_GET                   BOT_ERRNO_ERROR(BOT_MID_COMP_MEM, 0X0001) /* -0x02050001 */
/* mem module infomation with invalid para */
#define BOT_EMEM_INFO_PARA                  BOT_ERRNO_ERROR(BOT_MID_COMP_MEM, 0X0002) /* -0x02050002 */
/* mem module init len invalid */
#define BOT_EMEM_INIT_LEN_INV               BOT_ERRNO_ERROR(BOT_MID_COMP_MEM, 0X0003) /* -0x02050003 */
/* mem module region add len invalid */
#define BOT_EMEM_REGION_ADD_LEN_INV         BOT_ERRNO_ERROR(BOT_MID_COMP_MEM, 0X0004) /* -0x02050004 */
/* mem module alloc size zero */
#define BOT_EMEM_ALLOC_SIZE_ZERO            BOT_ERRNO_ERROR(BOT_MID_COMP_MEM, 0X0005) /* -0x02050005 */
/* mem module alloc size invalid */
#define BOT_EMEM_ALLOC_SIZE_INV             BOT_ERRNO_ERROR(BOT_MID_COMP_MEM, 0X0006) /* -0x02050006 */
/* mem module partition head invalid */
#define BOT_EMEM_PT_HEAD_INV                BOT_ERRNO_ERROR(BOT_MID_COMP_MEM, 0X0007) /* -0x02050007 */
/* mem module no valid mem block */
#define BOT_EMEM_NO_VALID_BLK               BOT_ERRNO_ERROR(BOT_MID_COMP_MEM, 0X0008) /* -0x02050008 */
/* mem module free ptr is NULL */
#define BOT_EMEM_FREE_PTR_NULL              BOT_ERRNO_ERROR(BOT_MID_COMP_MEM, 0X0009) /* -0x02050009 */
/* mem module realloc size invalid */
#define BOT_EMEM_REALLOC_SIZE_INV           BOT_ERRNO_ERROR(BOT_MID_COMP_MEM, 0X000A) /* -0x0205000A */
/* ------------------------------------------------------------------------------ */

/* ------------------------- NET Componnets Errcode ----------------------------- */
/* network module imei id get failed */
#define BOT_ENET_MQTT_PARAMETER_ERR         BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X0001) /* -0x02060001 */
/* network module mqtt data model init failed */
#define BOT_ENET_MQTT_DM_INIT_ERR           BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X0002) /* -0x02060002 */
/* network module mqtt init failed */
#define BOT_ENET_MQTT_INIT_ERR              BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X0003) /* -0x02060003 */
/* network module mqtt connect failed */
#define BOT_ENET_MQTT_CONNECT_ERR           BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X0004) /* -0x02060004 */
/* network module mqtt disconnect failed */
#define BOT_ENET_MQTT_DISCONNECT_ERR        BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X0005) /* -0x02060005 */
/* network module mqtt send data failed */
#define BOT_ENET_MQTT_SEND_DATA_ERR         BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X0006) /* -0x02060006 */
/* network module json create failed */
#define BOT_ENET_JSON_CREATE_ERR            BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X0007) /* -0x02060007 */
/* network module json get failed */
#define BOT_ENET_JSON_GET_ERR               BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X0008) /* -0x02060008 */
/* network module json parse failed */
#define BOT_ENET_JSON_PARSE_ERR             BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X0009) /* -0x02060009 */

/* network module dynamic registration init failed */
#define BOT_ENET_DYNREG_INIT_ERR            BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X000A) /* -0x0206000A */
/* network module dynamic registration deinit failed */
#define BOT_ENET_DYNREG_DEINIT_ERR          BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X000B) /* -0x0206000B */
/* network module dynamic registration send failed */
#define BOT_ENET_DYNREG_SEND_ERR            BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X000C) /* -0x0206000C */
/* network module dynamic registration receive failed */
#define BOT_ENET_DYNREG_RECV_ERR            BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X000D) /* -0x0206000D */
/* network module dynamic registration already */
#define BOT_ENET_DYNREG_ALREADY_REG         BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X000E) /* -0x0206000E */

/* network module coap init failed */
#define BOT_ENET_COAP_INIT_ERR              BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X000F) /* -0x0205000F */
/* network module coap connect failed */
#define BOT_ENET_COAP_CONNECT_ERR           BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X0010) /* -0x02050010 */
/* network module coap disconnect failed */
#define BOT_ENET_COAP_DISCONNECT_ERR        BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X0011) /* -0x02050011 */
/* network module coap send data failed */
#define BOT_ENET_COAP_SEND_DATA_ERR         BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X0012) /* -0x02050012 */
/* network module coap request auth token filed */
#define BOT_ENET_COAP_AUTH_TOKEN_ERR        BOT_ERRNO_ERROR(BOT_MID_COMP_NET, 0X0013) /* -0x02050013 */
/* ------------------------------------------------------------------------------ */

/* ------------------------- TLV Components Errcode ----------------------------- */
/* TLV module put object failed */
#define BOT_ETLV_PUT_OBJ                    BOT_ERRNO_ERROR(BOT_MID_COMP_TLV, 0X0001) /* -0x02070001 */
/* TLV module key list add failed, key is already existed */
#define BOT_ETLV_KEY_LIST_ADD               BOT_ERRNO_ERROR(BOT_MID_COMP_TLV, 0X0002) /* -0x02070002 */
/* TLV module serialize failed */
#define BOT_ETLV_SERIALIZE                  BOT_ERRNO_ERROR(BOT_MID_COMP_TLV, 0X0003) /* -0x02070003 */
/* TLV module key node get failed, node is not found */
#define BOT_ETLV_KEY_LIST_NODE_GET          BOT_ERRNO_ERROR(BOT_MID_COMP_TLV, 0X0004) /* -0x02070004 */
/* TLV module get bytes failed */
#define BOT_ETLV_BOX_GET_BYTES              BOT_ERRNO_ERROR(BOT_MID_COMP_TLV, 0X0005) /* -0x02070005 */
/* TLV module get types failed */
#define BOT_ETLV_BOX_GET_TYPES              BOT_ERRNO_ERROR(BOT_MID_COMP_TLV, 0X0006) /* -0x02070006 */
/* TLV create failed */
#define BOT_ETLV_CREATE_ERR                 BOT_ERRNO_ERROR(BOT_MID_COMP_TLV, 0X0007) /* -0x02070007 */
/* ------------------------------------------------------------------------------ */

/* ------------------------- UTILS Components Errcode --------------------------- */
/* utils get current time fail */
#define BOT_EUTILS_CUR_TIME_GET             BOT_ERRNO_ERROR(BOT_MID_COMP_UTILS, 0X0001) /* -0x02080001 */
/* utils gmtime fail */
#define BOT_EUTILS_GMTIME                   BOT_ERRNO_ERROR(BOT_MID_COMP_UTILS, 0X0002) /* -0x02080002 */
/* ------------------------------------------------------------------------------ */

/* ------------------------- CHAIN Components Errcode --------------------------- */
/* chain module get ecc curve fail */
#define BOT_ECHAIN_ALG_TYPE_ERR             BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0003) /* -0x02080003 */
/* chain module sign with ecc fail */
#define BOT_ECHAIN_ECC_SIGN_ERR             BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0004) /* -0x02080004 */
/* chain module get random number fail */
#define BOT_ECHAIN_RAND_ERR                 BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0005) /* -0x02080005 */

/* chain module net connect fail */
#define BOT_ECHAIN_NET_CONNECT_ERR          BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0010) /* -0x02080010 */
/* chain module net send fail */
#define BOT_ECHAIN_NET_SEND_ERR             BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0011) /* -0x02080011 */
/* chain module net receive fail */
#define BOT_ECHAIN_NET_RECV_ERR             BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0012) /* -0x02080012 */
/* chain module packet head get fail */
#define BOT_ECHAIN_HEAD_RECV_ERR            BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0013) /* -0x02080013 */
/* chain module packet head verify fail */
#define BOT_ECHAIN_HEAD_VERIFY_ERR          BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0014) /* -0x02080014 */
/* chain module handshake fail */
#define BOT_ECHAIN_HANDSHAKE_ERR            BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0015) /* -0x02080015 */

/* chain module response return error */
#define BOT_ECHAIN_RESP_ERR                 BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0020) /* -0x02080020 */
/* chain module recepit return error */
#define BOT_ECHAIN_RECEPIT_ERR              BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0021) /* -0x02080021 */
/* chain module transaction response parse fail */
#define BOT_ECHAIN_TRANS_RESP_PARSE_ERR     BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0022) /* -0x02080022 */
/* chain module deposit data fail */
#define BOT_ECHAIN_DEPOSIT_DATA_ERR         BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0023) /* -0x02080023 */
/* chain module message not defined */
#define BOT_ECHAIN_NO_DEFINED_MSG           BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0024) /* -0x02080024 */
/* chain module transaction parse fail */
#define BOT_ECHAIN_TRANS_PARSE_ERR          BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0025) /* -0x02080025 */
/* chain module data to be deposited is too long*/
#define BOT_ECHAIN_TRANS_DATA_OVERSIZE      BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0026) /* -0x02080026 */
/* chain module rlp decode fail, too few itms */
#define BOT_ECHAIN_MISSING_ITEMS            BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0027) /* -0x02080027 */
/* chain module response type mimatch */
#define BOT_ECHAIN_RESP_TYPE_MISMATCH       BOT_ERRNO_ERROR(BOT_MID_COMP_CHAIN, 0X0028) /* -0x02080028 */
/* ------------------------------------------------------------------------------ */

/* ------------------------- DTC Service Errcode -------------------------------- */
/* zero config encryption flag bit is abnormal */
#define BOT_EDTC_CONFIG_FLAG                BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0200) /* -0x02300200 */
/* zero config disable */
#define BOT_EDTC_CONFIG_DISABLE             BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0201) /* -0x02300201 */
/* zero config handler not found */
#define BOT_EDTC_CONFIG_HANDLER             BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0202) /* -0x02300202 */
/* zero config invalid pk */
#define BOT_EDTC_CONFIG_PK                  BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0203) /* -0x02300203 */
/* zero config set pk fail */
#define BOT_EDTC_CONFIG_SET_PK              BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0204) /* -0x02300204 */
/* zero config invalid ps */
#define BOT_EDTC_CONFIG_PS                  BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0205) /* -0x02300205 */
/* zero config set ps fail */
#define BOT_EDTC_CONFIG_SET_PS              BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0206) /* -0x02300206 */
/* zero config get pk fail */
#define BOT_EDTC_CONFIG_GET_PK              BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0207) /* -0x02300207 */
/* zero config get ps fail */
#define BOT_EDTC_CONFIG_GET_PS              BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0208) /* -0x02300208 */
/* zero config get array size too small */
#define BOT_EDTC_CONFIG_GET_BUF             BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0209) /* -0x02300209 */
/* zero config invalid pn(product name) */
#define BOT_EDTC_CONFIG_PN                  BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X020A) /* -0x0230020A */
/* zero config set pn fail */
#define BOT_EDTC_CONFIG_SET_PN              BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X020B) /* -0x0230020B */
/* zero config get pn fail */
#define BOT_EDTC_CONFIG_GET_PN              BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X020C) /* -0x0230020C */
/* zero config repeat */
#define BOT_EDTC_CONFIG_REPEAT              BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X020D) /* -0x0230020D */
/* zero config decrypto fail */
#define BOT_EDTC_CONFIG_DECRYPTO            BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X020E) /* -0x0230020E */
/* zero config encrypto fail */
#define BOT_EDTC_CONFIG_ENCRYPTO            BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X020F) /* -0x0230020F */
/* zero config decode fail */
#define BOT_EDTC_CONFIG_DECODE              BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0210) /* -0x02300210 */
/* zero config encode fail */
#define BOT_EDTC_CONFIG_ENCODE              BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0211) /* -0x02300211 */
/* zero config encode fail */
#define BOT_EDTC_CONFIG_CRC_CHECK           BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0212) /* -0x02300212 */
/* zero config encode fail */
#define BOT_EDTC_CONFIG_SEM_CREAT           BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0213) /* -0x02300213 */
/* zero config device info init fail */
#define BOT_EDTC_CONFIG_DEV_INFO            BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0214) /* -0x02300214 */
/* zero config init fail */
#define BOT_EDTC_CONFIG_INIT                BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0215) /* -0x02300215 */
/* zero config invalid instance id */
#define BOT_EDTC_CONFIG_IID                 BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0216) /* -0x02300216 */
/* zero config set instance id fail */
#define BOT_EDTC_CONFIG_SET_IID             BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0217) /* -0x02300217 */
/* zero config get instance id fail */
#define BOT_EDTC_CONFIG_GET_IID             BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0218) /* -0x02300218 */

/* The asset ID format is incorrect */
#define BOT_EDTC_ASSET_ID                   BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0300) /* -0x02300300 */
/* The asset Type format is incorrect */
#define BOT_EDTC_ASSET_TYPE                 BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0301) /* -0x02300301 */
/* ADV format error */
#define BOT_EDTC_ADV                        BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0302) /* -0x02300302 */
/* Asset registration interval is too short */
#define BOT_EDTC_REG_BUSY                   BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0303) /* -0x02300303 */
/* Asset registration config invalid */
#define BOT_EDTC_REG_CONFIG_ERR             BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0304) /* -0x02300304 */

/* Network anomalies */
#define BOT_EDTC_NET                        BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0400) /* -0x02300400 */
/* The server is not connected */
#define BOT_EDTC_NOT_CONNECT                BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0401) /* -0x02300401 */
/* The key is invalid */
#define BOT_EDTC_SIGNATURE                  BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0402) /* -0x02300402 */
/* Abnormal dm_handle */
#define BOT_EDTC_DM                         BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0403) /* -0x02300403 */
/* Signature generation exception */
#define BOT_EDTC_GENERATE_SIG               BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0404) /* -0x02300404 */
/* Failed to set kv parameters */
#define BOT_EDTC_KV                         BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0405) /* -0x02300405 */
/* Device not registered */
#define BOT_EDTC_UNREGIST                   BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0406) /* -0x02300406 */
/* Json format error */
#define BOT_EDTC_JSON                       BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0407) /* -0x02300407 */
/* The uploaded data does not contain an assert ID */
#define BOT_EDTC_ASSERT_ID                  BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0408) /* -0x02300408 */
/* Abnormal deviceinfo_handle */
#define BOT_EDTC_DI                         BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0409) /* -0x02300409 */
/* Debug info decode error */
#define BOT_EDTC_DECODE_ERROR               BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0500) /* -0x02300500 */
/* Debug command error */
#define BOT_EDTC_DEBUG_CMD_INV              BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0501) /* -0x02300501 */
/* Fail to clear the device info */
#define BOT_EDTC_DEV_CLR_ERROR              BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0502) /* -0x02300502 */
/* Fail to clear the connect info */
#define BOT_EDTC_CONN_CLR_ERROR             BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0503) /* -0x02300503 */
/* Send queue is full, please try again later */
#define BOT_EDTC_BUSY                       BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0504) /* -0x02300504 */
/* Acknowledgment received timed out */
#define BOT_EDTC_ACK_TIMEOUT                BOT_ERRNO_ERROR(BOT_MID_SRV_DTC, 0X0505) /* -0x02300505 */
/* ------------------------------------------------------------------------------ */

/* ------------------------- NTP Service Errcode --------------------------- */
/* ntp service init fail */
#define BOT_ENTP_INIT                       BOT_ERRNO_ERROR(BOT_MID_SRV_NTP, 0X0001) /* -0x02310001 */
/* ntp service setopt fail */
#define BOT_ENTP_SET                        BOT_ERRNO_ERROR(BOT_MID_SRV_NTP, 0X0002) /* -0x02310002 */
/* ntp service send fail */
#define BOT_ENTP_SEND                       BOT_ERRNO_ERROR(BOT_MID_SRV_NTP, 0X0003) /* -0x02310003 */
/* ------------------------------------------------------------------------------ */

#ifdef __cplusplus
}
#endif

#endif /* __BOT_ERRNO_H__ */

