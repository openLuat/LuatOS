/**
 * Copyright (c) 2015-2022 QXSI. All rights reserved.
 *
 * @file qxwz_sdk.h
 * @brief header of SDK APIs
 * @version 1.0.0
 * @author Kong Yingjun
 * @date   2022-03-16
 *
 * CHANGELOG:
 * DATE             AUTHOR          REASON
 * 2022-03-16       Kong Yingjun    Init version;
 */
#ifndef QXWZ_SDK_H__
#define QXWZ_SDK_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "qxwz_types.h"

#if !defined(QXWZ_SDK_WINDOWS) && (defined(WIN32) || defined(WIN64) || defined(_MSC_VER) || defined(_WIN32))
#define QXWZ_SDK_WINDOWS
#endif

#ifdef QXWZ_SDK_WINDOWS

#ifdef QXWZ_WIN_DLL
#define QXWZ_SDK_STDCALL __stdcall
#if defined(QXWZ_EXPORT_SYMBOLS)
#define QXWZ_PUBLIC(type)    __declspec(dllexport) type QXWZ_SDK_STDCALL
//#define QXWZ_PUBLIC(type) type
#else
#define QXWZ_PUBLIC(type)   __declspec(dllimport) type QXWZ_SDK_STDCALL
//#define QXWZ_PUBLIC(type) type
#endif
#else
#define QXWZ_PUBLIC(type) type
#endif
#else /* !QXWZ_SDK_WINDOWS */
#if defined(__GNUC__)
#define QXWZ_PUBLIC(type) __attribute__((visibility("default"))) type
#define ATTRIBUTE_WEAK __attribute__((weak))
#else
#define QXWZ_PUBLIC(type) type
#endif
#endif
#ifndef ATTRIBUTE_WEAK
#define ATTRIBUTE_WEAK
#endif

/*******************************************************************************
 * SDK status Definitions
 *******************************************************************************/

/**********************************
 * status code, 1 - 999
 **********************************/

/*
 * interface related, 1 - 100
 */
#define QXWZ_SDK_STAT_OK                                    0   /* success */

/*
 * cap related, 101 - 200
 */
#define QXWZ_SDK_STAT_CAP_START_SUCC                        101 /* capability start successfully */
#define QXWZ_SDK_STAT_CAP_ACT_SUCC                          102 /* capability activate successfully */
#define QXWZ_SDK_STAT_CAP_RESTART_SUCC                      103 /* capability restart successfully */
#define QXWZ_SDK_STAT_CAP_CONFIG_UPDATE_SUCC                104

/*
 * auth related, 201 - 300
 */
#define QXWZ_SDK_STAT_AUTH_SUCC                             201 /* account authenticate successfully */
#define QXWZ_SDK_STAT_LOCAL_AUTH_SUCC                       202 /* account local authenticate successfully */

#define QXWZ_SDK_STAT_UPLOAD_FILE_COMP                      301 /* complete file uploading */
#define QXWZ_SDK_STAT_UPLOAD_FILE_IN_PROGRESS               302 /* file is uploading */


/**
 * define for enc conf callback
*/
#define QXWZ_SDK_STAT_ENC_CONF_ACCOUNT_CMD                  310 /* account request command */
#define QXWZ_SDK_STAT_ENC_CONF_ACCOUNT                      311 /* account info */
#define QXWZ_SDK_STAT_ENC_CONF_CAP_CMD                      312 /* cap request command */
#define QXWZ_SDK_STAT_ENC_CONF_LOCAL_CAP                    313 /* local cap info */
#define QXWZ_SDK_STAT_ENC_CONF_ONLINE_CAP                   314 /* online cap info */
#define QXWZ_SDK_STAT_ENC_CONF_NOTIFY                       315 /* status notify */

#define QXWZ_SDK_STAT_ENC_CONF_SET_ACCOUNT_OK               316 /* account has been set, go authenticating */
#define QXWZ_SDK_STAT_ENC_CONF_SET_CAP_OK                   317 /* cap has been set, go starting */
#define QXWZ_SDK_STAT_ENC_CONF_SET_NOTIFY                   318 /* remote status */

/**
 * define for resolve callback
 */
#define QXWZ_SDK_STAT_RESOLVE_TASK_SUBMIT_SUCC              400 /* resolve task submit successfully */
#define QXWZ_SDK_STAT_RESOLVE_QUERY_SUCC                    402 /* resolve task query successfully */

/**
 * define for download file callback
 */
#define QXWZ_SDK_STAT_DOWNLOAD_FILE_IN_RUNNING              501
#define QXWZ_SDK_STAT_DOWNLOAD_SUCC                         502

/**
 * define for query resource package callback
 */
#define QXWZ_SDK_STAT_RES_PACK_QUERY_SUCC                   601


/*
 * biz custom related, 901 - 990
 */

#define QXWZ_SDK_STAT_BDS3_FMT_SUCC                         902 /* set diff data bds3 format successfully */


/*
 * unknown status code
 */
#define QXWZ_SDK_STAT_UNKNOWN                               999 /* unknown status */


/**********************************
 * error code, from -1 to -999
 **********************************/

/*
 * interface related, -1 - -100
 */
#define QXWZ_SDK_ERR_FAIL                                   -1      /* sdk common error */
#define QXWZ_SDK_ERR_INVALID_PARAM                          -2      /* invalid parameter */
#define QXWZ_SDK_ERR_INVALID_CONFIG                         -3      /* invalid configuration */
#define QXWZ_SDK_ERR_NOT_INITED                             -4      /* sdk not initialized */
#define QXWZ_SDK_ERR_NOT_AUTHED                             -5      /* sdk account not authenticated */
#define QXWZ_SDK_ERR_NOT_STARTED                            -6      /* capability not started */
#define QXWZ_SDK_ERR_AUTHING                                -7      /* sdk account authenticate in progress */
#define QXWZ_SDK_ERR_STARTING                               -8      /* capability start in progress */
#define QXWZ_SDK_ERR_ALREADY_INITED                         -9      /* sdk already initialized */
#define QXWZ_SDK_ERR_ALREADY_AUTHED                         -10     /* sdk already authenticated */
#define QXWZ_SDK_ERR_ALREADY_STARTED                        -11     /* capability already started */
#define QXWZ_SDK_ERR_GETTING_COORD_SYS                      -12     /* sdk get coordinate frame in progress */
#define QXWZ_SDK_ERR_SETTING_COORD_SYS                      -13     /* sdk set coordinate frame in progress */
#define QXWZ_SDK_ERR_QUERYING_EXEC_STRATEGY                 -14     /* sdk query exec strategy in progress */
#define QXWZ_SDK_ERR_INVALID_SERV_CONF                      -15     /* invalid server configuration */
#define QXWZ_SDK_ERR_INVALID_OSS_CONF                       -16     /* invalid oss configuration */
#define QXWZ_SDK_ERR_INVALID_NOSR_DATA_FMT_CONF             -17     /* invalid diff data format configuration */
#define QXWZ_SDK_ERR_INVALID_BROADCAST_INTERVAL             -18     /* invalid diff data broadcast frequency configuration */
#define QXWZ_SDK_ERR_ACTIVATING                             -19     /* sdk activate in progress */
#define QXWZ_SDK_ERR_RESUMING_DSK                           -20     /* sdk resuming dsk in progress */
#define QXWZ_SDK_ERR_IN_PROGRESS                            -21     /* common error code for something is still in progress */
#define QXWZ_SDK_ERR_ONLY_AVAILABLE_IN_DSK_MODE             -22     /* current interface only availble in DSK mode, please init SDK with DSK */
#define QXWZ_SDK_ERR_ACCOUNT_ALREADY_SET                    -23     /* if key type is not QXWZ_SDK_KEY_TYPE_EXTERNAL or QXWZ_SDK_KEY_TYPE_EXTERNAL_KEY, then account is not allowed to set by qxwz_sdk_enc_config_ctl */
#define QXWZ_SDK_ERR_ACCOUNT_NOT_READY                      -24     /* if key type is not QXWZ_SDK_KEY_TYPE_AK or QXWZ_SDK_KEY_TYPE_DSK, it means the account is not set by qxwz_sdk_enc_config_ctl */

#define QXWZ_SDK_ERR_UPDATE_KEY_NOT_NEWEST                  -25     /* When using the qxwz_sdk_update_offline_cap_config interface to update the key type, the key is not newer than the previous one */

#define QXWZ_SDK_ERR_PERSIST_STORAGE_READ_FAIL              -26     /* qxwz_persist_storage_read read local capability config file fail*/
#define QXWZ_SDK_ERR_PERSIST_STORAGE_PARSE_FAIL             -27

#define QXWZ_SDK_ERR_API_CALLED_TOO_FAST                    -30     /* sdk api be called too frequently */

/*
 * network related, -101 - -200
 */
#define QXWZ_SDK_ERR_NETWORK_UNAVAILABLE                    -101    /* network exception or not available */

/*
 * cap related, -201 - -300
 */
#define QXWZ_SDK_ERR_GGA_OUT_OF_SERVICE_AREA                -201    /* the uploaded GGA is out of service area */
#define QXWZ_SDK_ERR_INVALID_GGA                            -202    /* the uploaded GGA is invalid */
#define QXWZ_SDK_ERR_CAP_START_FAIL                         -203    /* start capability failed */
#define QXWZ_SDK_ERR_CAP_GET_CONF_FAIL                      -204    /* get capability configuration failed */
#define QXWZ_SDK_ERR_CAP_NOT_FOUND                          -205    /* unsupported capability */
#define QXWZ_SDK_ERR_CAP_NOT_IN_SERVICE                     -206    /* generally error code for the capability which is not in service */
#define QXWZ_SDK_ERR_CAP_MANUAL_ACT_REQUIRED                -207    /* inactivated capability, manual activation is required */
#define QXWZ_SDK_ERR_CAP_ACT_ON_TERM_REQUIRED               -208    /* inactivated capability, terminal activation is required */
#define QXWZ_SDK_ERR_CAP_ALREADY_ACTIVATED                  -209    /* capability is already active */
#define QXWZ_SDK_ERR_CAP_CANNOT_ACT_ON_TERM                 -210    /* terminal activation is not allowed */
#define QXWZ_SDK_ERR_CAP_SYSTEM_ERROR                       -211    /* capability system error */
#define QXWZ_SDK_ERR_CAP_NOT_INCLUDE                        QXWZ_SDK_ERR_CAP_NOT_FOUND
#define QXWZ_SDK_ERR_CAP_PAUSE                              -213    /* suspended capability */
#define QXWZ_SDK_ERR_CAP_ACT_FAIL                           -214    /* terminal activate failed */
#define QXWZ_SDK_ERR_GGA_OUT_OF_CONTROL_AREA                -215    /* the uploaded GGA is out of control area, **** */
#define QXWZ_SDK_ERR_CAP_INACTIVE                           -216    /* generally error code for inactivated capability */
#define QXWZ_SDK_ERR_CAP_EXPIRED                            -217    /* expired capability */
#define QXWZ_SDK_ERR_CAP_DISABLED                           -218    /* disabled capability */
#define QXWZ_SDK_ERR_CAP_NEED_AUDIT_DSK                     -219    /* please do real name authentication firstly */
#define QXWZ_SDK_ERR_CAP_DATA_PENDING                       -220    /* capability data pending */
#define QXWZ_SDK_ERR_CAP_SERVER_ERROR                       -221    /* capability provider server error */
/*
 * auth related, -301 - -400
 */
#define QXWZ_SDK_ERR_AUTH_FAIL                              -301    /* account authentication fail */
#define QXWZ_SDK_ERR_NO_AVAIL_ACC                           -302    /* account not available */
#define QXWZ_SDK_ERR_MANUAL_BIND_REQUIRED                   -303    /* account need bind manually */
#define QXWZ_SDK_ERR_ACC_BEING_PROCESSED                    -304    /* account bind in progress */
#define QXWZ_SDK_ERR_UNMATCH_DID_DSK                        -305    /* account DSK not match Device ID */
#define QXWZ_SDK_ERR_ACC_NOT_BIND                           -307    /* account not bind */
#define QXWZ_SDK_ERR_ACC_EXPIRED                            -308    /* account expired */
#define QXWZ_SDK_ERR_ACC_NOT_ENOUGH                         -309    /* account not enough */
#define QXWZ_SDK_ERR_ACC_UNSUPPORT_OP                       -310    /* account operation not supported */
#define QXWZ_SDK_ERR_INVAL_KEY                              -311    /* common error code for invalid account */
#define QXWZ_SDK_ERR_ACC_INACTIVE                           -312    /* account not activated */
#define QXWZ_SDK_ERR_ACC_DUPLICATED                         -313    /* account login duplicated */
#define QXWZ_SDK_ERR_LOCAL_AUTH_FAIL                        -314    /* account local authentication fail */
#define QXWZ_SDK_ERR_INVAL_QID                              -315    /* invalid QID */
#define QXWZ_SDK_ERR_INVAL_ACCESS_TOKEN                     -316    /* invalid access token */
#define QXWZ_SDK_ERR_PARSE_KEY_FAIL                         -317    /* parsing key fail */
#define QXWZ_SDK_ERR_DSK_NOT_EXIST                          -318    /* account DSK not exist */

/*
 * openapi related, -401 - -500
 */
#define QXWZ_SDK_ERR_CALL_API_FAIL                          -401    /* calling openapi fail */
#define QXWZ_SDK_ERR_INVAL_API_RESP                         -402    /* invalid openapi response */



/*
 * system related, -501 - -600
 */
#define QXWZ_SDK_ERR_OUT_OF_MEMORY                          -501    /* memory allocation fail */
#define QXWZ_SDK_ERR_OUT_OF_STORAGE                         -502    /* storage space not enough */
#define QXWZ_SDK_ERR_FILE_NOT_FOUND                         -503    /* file not found */
#define QXWZ_SDK_ERR_FILE_NO_ACCESS                         -504    /* file no right to access */
#define QXWZ_SDK_ERR_INTERNAL_ERROR                         -505    /* sdk internal error */
#define QXWZ_SDK_ERR_SERV_FAULT                             -506    /* server error */
#define QXWZ_SDK_ERR_NOSR_SERVICE_STOP                      -507    /* NOSR service stop */
#define QXWZ_SDK_ERR_FILE_OPEN_FAIL                         -508    /* opening file fail */
#define QXWZ_SDK_ERR_FILE_SEEK_FAIL                         -509    /* seeking file fail */
#define QXWZ_SDK_ERR_CAP_DIFF_DATA_TIME_OUT                 -510    /* diff data not received in 1 minute */


/*
 * ssr decoder related, -601 - -700
 */
#define QXWZ_SDK_ERR_DEC_INIT_FAIL                          -601    /* decoder initialization fail */
#define QXWZ_SDK_ERR_DEC_INVALID_DATA                       -602    /* invalid data for decoder */
#define QXWZ_SDK_ERR_DEC_DECODE_FAIL                        -603    /* decoding data fail */
#define QXWZ_SDK_ERR_DEC_CRC_CHECK_FAIL                     -604    /* CRC check fail */
#define QXWZ_SDK_ERR_DEC_DECRYPT_FAIL                       -605    /* decrypting data fail */
#define QXWZ_SDK_ERR_DEC_XOR_CHECK_FAIL                     -606    /* xor check fail */
#define QXWZ_SDK_ERR_DEC_INTERNAL_ERR                       -607    /* decoder internal error */
#define QXWZ_SDK_ERR_DEC_INVALID_KEY                        -608    /* invalid key for decoder */
#define QXWZ_SDK_ERR_DEC_GET_KEY_FAIL                       -609    /* getting key fail */
#define QXWZ_SDK_ERR_DEC_UNSUPP_TYPE                        -610    /* unsupported data type, it may be unsubscribed, or unrecognized */
#define QXWZ_SDK_ERR_DEC_INCOMP_DATA                        -611    /* incomplete data, waiting for more data, that is not a fatal error */
#define QXWZ_SDK_ERR_DEC_UNKNOWN                            -700    /* unknown status for decoder */


/*
 * section charge related, -801 - -900
 */
#define QXWZ_SDK_ERR_NO_STRATEGY_FOUND                      -801    /* strategy not found */
#define QXWZ_SDK_ERR_DSK_CHECK_FAIL                         -802    /* DSK check fail */

/*
 * biz custom related, -901 - -990
 */

#define QXWZ_SDK_ERR_NOSR_DATA_FMT_TIMEOUT                  -921    /* set diff data BDS3 format timeout */
#define QXWZ_SDK_ERR_NOSR_DATA_FMT_NOT_SUPPORT              -922    /* diff data BDS3 format not support */
#define QXWZ_SDK_ERR_NOSR_DATA_FMT_SET_FAIL                 -923    /* seting diff data BDS3 format fail */

/*
 * unknown error code
 */
#define QXWZ_SDK_ERR_UNKNOWN                                -99999  /* sdk unknown status */

/**
 * Define the SDK status or error code for user.
*/
typedef enum {
    QXWZ_SDK_CODE_OK                                    = QXWZ_SDK_STAT_OK, /* OK */
    QXWZ_SDK_ERR_AUDIT_PASSED                           = QXWZ_SDK_STAT_OK, /* audit passed */
    QXWZ_SDK_ERR_AUDIT_INVALID_PARAM                    = -1000, /* invalid parameter */
    QXWZ_SDK_ERR_AUDIT_PERMISSION_ERR                   = -1001, /* permission error, please contact your administrator for more information */
    QXWZ_SDK_ERR_AUDIT_INTERNAL_ERR                     = -1002, /* service inernal error, please contact your administrator for more information */
    QXWZ_SDK_ERR_AUDIT_ID_AGE_ERR                       = -1003, /* the age of the ID number is illegal, please correct and retry */
    QXWZ_SDK_ERR_AUDIT_SERVICE_UNAVAILABLE              = -1004, /* the audit service is unavailable, please contact your administrator for more information */
    QXWZ_SDK_ERR_AUDIT_ID_CENTER_UNAVAILABLE            = -1005, /* the audit center is under maintenance, please contact your administrator for more information */
    QXWZ_SDK_ERR_AUDIT_AUDIT_FAILED                     = -1006, /* audit failed */
    QXWZ_SDK_ERR_AUDIT_NAME_ID_UNMATCH                  = -1007, /* the name is unmatch the ID number */
    QXWZ_SDK_ERR_AUDIT_ID_UNAVAILABLE                   = -1008, /* there is no related ID info in service center */
    QXWZ_SDK_ERR_AUDIT_USER_LOG_OFF                     = -1009, /* the user is log off */
    QXWZ_SDK_ERR_AUDIT_USER_NOT_EXIST                   = -1010, /* the user is not exist */
    QXWZ_SDK_ERR_AUDIT_ID_ALEADY_EXISTED                = -1011, /* the ID has been registered, please change another */
    QXWZ_SDK_ERR_AUDIT_ID_FORMAT_ERROR                  = -1012, /* the format of the ID error */
    QXWZ_SDK_ERR_AUDIT_NAME_FORMAT_ERROR                = -1013, /* the format of the name error */
    QXWZ_SDK_ERR_AUDIT_GETTING                          = QXWZ_SDK_ERR_IN_PROGRESS, /* requesting, please wait callback */

    QXWZ_SDK_ERR_ENC_CONF_DECODE_FAIL                   = -1100, /* encrypted configuration decoding fail */
    QXWZ_SDK_ERR_ENC_CONF_ENCODE_FAIL                   = -1101, /* encrypted configuration encoding fail */
    QXWZ_SDK_ERR_ENC_CONF_CHECK_FAIL                    = -1102, /* encrypted configuration check fail */
    QXWZ_SDK_ERR_ENC_CONF_ACCOUNT_NOT_SAME              = -1103, /* the account you received is not equal to the account you input */
    QXWZ_SDK_ERR_ENC_CONF_INVALID_OFFLINE_INFO_TYPE     = -1104, /* invalid data type while local authenticating */
    QXWZ_SDK_ERR_ENC_CONF_INVALID_OFFLINE_INFO_CONTENT  = -1105, /* invalid data content while local authenticating */

    QXWZ_SDK_ERR_UPLOADX_SERVER_ERROR                   = -1200, /* server ack error for uploading file */
    QXWZ_SDK_ERR_UPLOAD_FILE_FAIL                       = -1201,

    QXWZ_SDK_ERR_EPH_GET_INVALID_PARAM                  = -1300,  /* invalid parameter for get eph */


    QXWZ_SDK_ERR_RESOLVE_TASK_SUBMIT_ERR                 = -1401,
    QXWZ_SDK_ERR_RESOLVE_ILLEGAL_ARGS                    = -1402,
    QXWZ_SDK_ERR_RESOLVE_INTERNAL_SERVER_ERR             = -1403,
    QXWZ_SDK_ERR_DOWNLOAD_DECODE_FAIL                    = -1501,
    QXWZ_SDK_ERR_DOWNLOAD_FILE_ERR                       = -1502,
    QXWZ_SDK_ERR_DOWNLOAD_ILLEGAL_ARGS                   = -1503,
    QXWZ_SDK_ERR_DOWNLOAD_LIMIT_OUT_OF_LIMITS            = -1504,
    QXWZ_SDK_ERR_DOWNLOAD_OFFSET_OUT_OF_INDEX            = -1505,
    QXWZ_SDK_ERR_DOWNLOAD_FILEID_NOT_FOUND               = -1506,
    QXWZ_SDK_ERR_DOWNLOAD_INTERNAL_SERVER_ERR            = -1507,
    QXWZ_SDK_ERR_DOWNLOAD_SERVER_UNAVAILABLE_ERR         = -1508,

    QXWZ_SDK_DC_NO_DEVICE_CALLBACK                       = -1600,
    QXWZ_SDK_UPLOAD_DEVICE_INFO_FAIL                     = -1601,
    QXWZ_SDK_APPLY_ACC_ENHANCEMENT_FAIL                  = -1602,
    QXWZ_SDK_UPLOAD_OBSSERVATION_INFO_FAIL               = -1603,
    QXWZ_SDK_UPLOAD_RESOLVE_INFO_FAIL                    = -1604,
    QXWZ_SDK_OBSSERVATION_INFO_ERROR                     = -1605,

    QXWZ_SDK_ERR_QUERYING_DEMO                           = -1700, /* rtk demo query in progress*/
    QXWZ_SDK_ERR_NOTIFYING_DEMO_STARTUP                  = -1701, /* rtk demo notify demo startup in progress*/
    QXWZ_SDK_ERR_RTK_DEMO_REUSE_TRY                      = -1702, /* The demo function is already in use */
    QXWZ_SDK_ERR_RTK_DEMO_TIMES_EXHAUST                  = -1703, /* rtk demo times exhaust,cannot be used for demo function*/
    QXWZ_SDK_ERR_RTK_DEMO_DSK_NO_CAPS                    = -1704, /* The dsk account not have any capabilities,cannot be used for demo function*/
    QXWZ_SDK_ERR_RTK_DEMO_ALREADY_ACTIVATED              = -1705, /* The dsk account has been officially activated,cannot be used for demo function*/
    QXWZ_SDK_ERR_RTK_DEMO_COMMODITY_CANNOT_DEMO          = -1706, /* This commodity does not support demonstration functionality */

    QXWZ_SDK_LSSR_REG_CODE_ERR_LEN                       = -1800, /* register code length invalid */
    QXWZ_SDK_LSSR_REG_CODE_NOT_MATCH                     = -1801, /* register code and host do not match */
    QXWZ_SDK_LSSR_REG_CODE_EXPIRED                       = -1802, /* register code has expired */
    QXWZ_SDK_LSSR_REG_CODE_USED                          = -1803, /* register code has been successfully applied */
    QXWZ_SDK_LSSR_REG_CODE_WRONG_TYPE                    = -1804, /* the type of register code is unknown */
    QXWZ_SDK_LSSR_REG_CODE_TIME_NOT_SYNC                 = -1805, /* the host has not synchronized yet */
    QXWZ_SDK_LSSR_REG_CODE_SDK_NOT_READY                 = -1806, /* the SDK is not ready yet */
    QXWZ_SDK_LSSR_REG_CODE_HAS_MAXINUM_LIMIT             = -1807, /* register codes has reached the maximum limit */
    QXWZ_SDK_LSSR_REG_CODE_VERIFY_FAILED                 = -1808, /* register code verify failed */
    QXWZ_SDK_LSSR_REG_CODE_ERR_INTERVAL                  = -1809, /* internal error */

    QXWZ_SDK_QUERY_GEOFENCE_ERR_PARAM_INVALID            = -1900, /* param invalid */
    QXWZ_SDK_QUERY_GEOFENCE_ERR_DEV_ID_NOT_EXIST         = -1901, /* device id is not exist */
    QXWZ_SDK_QUERY_GEOFENCE_ERR_SYSTEM_ERROR             = -1902, /* system error */

    QXWZ_SDK_QUERY_CAP_ERR_PAYG_NOT_SUPPORT              = -2000, /* accounts that do not support volume based billing */
    QXWZ_SDK_QUERY_CAP_ERR_TP_NOT_SUPPORT                = -2001, /* accounts that do not support segmented billing */
    QXWZ_SDK_QUERY_CAP_ERR_SYSTEM_ERROR                  = -2002, /* system error */
}QXWZ_SDK_STATUS_CODE_E;



/*******************************************************************************
 * SDK common macros definition
 *******************************************************************************/
/*
 * capability identifier
 */
#define QXWZ_SDK_CAP_ID_NOSR                    (1UL)            /* NOSR capability */
#define QXWZ_SDK_CAP_ID_NSSR                    (1UL << 1U)      /* NSSR capability */
#define QXWZ_SDK_CAP_ID_LSSR                    (1UL << 2U)      /* LSSR capability */
#define QXWZ_SDK_CAP_ID_PDR                     (1UL << 3U)      /* PDR capability */
#define QXWZ_SDK_CAP_ID_VDR                     (1UL << 4U)      /* VDR capability */
#define QXWZ_SDK_CAP_ID_EPH                     (1UL << 5U)      /* EPH capability */
#define QXWZ_SDK_CAP_ID_QXSUPL                  (1UL << 6U)      /* QXSUPL capability */
#define QXWZ_SDK_CAP_ID_SIDS                    (1UL << 7U)      /* SIDS capability */
#define QXWZ_SDK_CAP_ID_UPLOADX                 (1UL << 8U)      /* UPLOADX capability */
#define QXWZ_SDK_CAP_ID_BASE_STATION            (1UL << 9U)      /* one of STARX capability */
#define QXWZ_SDK_CAP_ID_ROVER_STATION           (1UL << 10U)     /* one of STARX capability */
#define QXWZ_SDK_CAP_ID_GNSS_STATION            (1UL << 11U)     /* one of STARX capability */
#define QXWZ_SDK_CAP_ID_ESIM                    (1UL << 12U)     /* one of STARX capability */
#define QXWZ_SDK_CAP_ID_OFFLINE_MEASUREMENT     (1UL << 13U)     /* OFFLINE_MEASUREMENT capability */
#define QXWZ_SDK_CAP_ID_DC                      (1UL << 14U)
#define QXWZ_SDK_CAP_ID_IONO                    (1UL << 15U)
#define QXWZ_SDK_CAP_ID_FORESTRY_INDUSTRY       (1UL << 16U)

/*
 * capability state
 */
#define QXWZ_SDK_CAP_STATE_INSERVICE            0U       /* capability in service */
#define QXWZ_SDK_CAP_STATE_INACTIVE             1U       /* capability not activated */
#define QXWZ_SDK_CAP_STATE_SUSPENDED            2U       /* capability suspended */
#define QXWZ_SDK_CAP_STATE_EXPIRED              3U       /* capability expired */
#define QXWZ_SDK_CAP_STATE_DISABLED             9U       /* capability disabled */

/*
 * capability activation method
 */
#define QXWZ_SDK_CAP_ACT_METHOD_AUTO            0       /* capability activated automatically */
#define QXWZ_SDK_CAP_ACT_METHOD_MANUAL          1       /* capability need activated manually */
#define QXWZ_SDK_CAP_ACT_METHOD_TERMINAL        2       /* capability need activated by terminal */


/*
 * capability resolve
 */
#define QXWZ_SDK_MAX_FILE_ID_LEN                128             /* file ID length */
#define QXWZ_SDK_MAX_FILE_TYPE_LEN              16              /* file type length */
#define QXWZ_SDK_MAX_FILE_FORMAT_LEN            16              /* file format length */
#define QXWZ_SDK_MAX_TASK_FILE_NUM              10              /* task file number */
#define QXWZ_SDK_MAX_META_INFO_KEY_LEN          16              /* key length */
#define QXWZ_SDK_MAX_META_INFO_VALUE_LEN        64              /* value length */
#define QXWZ_SDK_MAX_TASK_NUM                   10              /* task number */
#define QXWZ_SDK_MAX_TASK_TYPE_LEN              16              /* task type length */
#define QXWZ_SDK_MAX_TASK_ID_LEN                64              /* task ID length */
#define QXWZ_SDK_MAX_META_INFO_NUM              10              /* meta info number */
#define QXWZ_SDK_MAX_FILE_RECV_BUF_LEN          4096            /* receiving buffer size */
#define QXWZ_SDK_RESOLVE_METAINFO_GZIP          "gzip"          /* meta key gzip */
#define QXWZ_SDK_RESOLVE_METAINFO_TASK_TYPE     "taskType"      /* meta key task type */
#define QXWZ_SDK_RESOLVE_METAINFO_REQUESTID     "requestId"     /* meta key request ID */
#define QXWZ_SDK_RESOLVE_METAINFO_COORDFRAME    "coordframe"    /* meta key coordinate frame */
#define QXWZ_SDK_RESOLVE_METAINFO_ANTENNA       "antenna"
#define QXWZ_SDK_RESOLVE_METAINFO_DEVMODEL      "devModel"
#define QXWZ_SDK_RESOLVE_METAINFO_GNSSMODEL     "gnssModel"

/*
 * device center
 */
#define QXWZ_SDK_DEVICE_INFO_STR_LEN 64
#define QXWZ_SDK_NETWORK_SUPPLIER_STR_LEN 32
/*
 * ionosphere limit
 */


/*
 * limitations
 */

#define CONFIG_CAPINFO_ENABLE                   1   /* switch capinfo handle */
#define CONFIG_PRINT_STDOUT_ENABLE              0   /* switch standard output, not used */
#define CONFIG_OPENAPI_ENABLE                   1   /* switch use openapi */

#define QXWZ_SDK_MAX_CAPS                       20U   /* max capability number */

#define QXWZ_SDK_VERSION_LEN                    128 /* sdk version length */
#define QXWZ_SDK_MAX_KEY_LEN                    128 /* sdk account key length */
#define QXWZ_SDK_MAX_SECRET_LEN                 128 /* sdk account secret length */
#define QXWZ_SDK_MAX_DEV_ID_LEN                 128 /* sdk account device ID length */
#define QXWZ_SDK_MAX_DEV_TYPE_LEN               128 /* sdk account device type length */
#define QXWZ_SDK_MAX_QID_LEN                    128 /* sdk QID length */
#define QXWZ_SDK_MAX_ACCESS_TOKEN_LEN           512 /* sdk access token length */
#define QXWZ_SDK_MAX_SSR_KEY_STR_LEN            512 /* ssr key length */
#define QXWZ_SDK_MAX_EXEC_STRATEGY_NUM          8   /* sdk exec strategy number */
#define QXWZ_SDK_MAX_COORD_FRAME_NUM            8   /* sdk coordinate frame number */
#define QXWZ_SDK_MAX_COORD_FRAME_NAME           32  /* sdk coordinate frame name length */
#define QXWZ_SDK_MAX_HOST_LEN                   128 /* host name length */
#define QXWZ_SDK_DNS_SERVER_LEN                 16  /* dns server number */
#define QXWZ_SDK_MAX_HARDWARE_CAPS              5   /* hardware capability number */
#define QXWZ_SDK_MAX_CERT_PATH_LEN              1024 /* cert path length */
#define QXWZ_SDK_MAX_CALLER_NAME_LEN            32U  /* max caller  name */
#define QXWZ_SDK_MAX_CALLER_VERSION_LEN         16U  /* max caller version */
#define QXWZ_SDK_MAX_GGA_LEN                    256U /* max gga string length */
#define QXWZ_SDK_SERVICE_INSTANCE_SIK_LEN       32   /* service instance id length */
#define QXWZ_SDK_DURATION_LEN                   32   /* duration length */
#define QXWZ_SDK_RATING_VALUE_STR_LEN           64   /* rating value string length */


#define QXWZ_SDK_MAX_AUDIT_ID_LEN               (18+1)  /* reserve 1 byte for \0 */
#define QXWZ_SDK_MAX_AUDIT_NAME_LEN             (255+1) /* reserve 1 byte for \0 */

#define QXWZ_SDK_NOSR_UPLOAD_GGA                10001    /* user can upload GGA after nosr start successfully */



/**
 * @brief define different SDK data type
 */
typedef enum {
    QXWZ_SDK_DATA_TYPE_NONE                 = 0,    /* type guard */
    /* raw nosr data */
    QXWZ_SDK_DATA_TYPE_RAW_NOSR             = 1,    /* nosr rtcm data */



    QXWZ_SDK_DATA_TYPE_SIDS_INT             = 301,  /* sids integrity data */




    QXWZ_SDK_DATA_TYPE_CEIL                 = 0x7fffffff,    /* type guard */
} qxwz_sdk_data_type_e;

/**
 * @brief define different SDK authentication type
 */
typedef enum {
    QXWZ_SDK_KEY_TYPE_NONE                  = 0,    /* key type guard */
    QXWZ_SDK_KEY_TYPE_AK                    = 1,    /* appkey */
    QXWZ_SDK_KEY_TYPE_DSK                   = 2,    /* DSK */
    QXWZ_SDK_KEY_TYPE_EXTERNAL              = 5,    /* allow no dsk,dss,deviceid and devicetype while initializing */
    QXWZ_SDK_KEY_TYPE_EXTERNAL_KEY          = 6,    /* only allow no dsk and dss while initializing, deviceid and devicetype are needed.*/
    QXWZ_SDK_KEY_TYPE_CEIL                          /* key type guard */
} qwxz_sdk_key_type_e;

/**
 * @brief define SDK capability information
 */
typedef struct {
    qxwz_uint32_t caps_num;         /* capability number */
    struct {
        qxwz_uint32_t cap_id;       /* capability ID */
        qxwz_uint8_t state;         /* capability state */
        qxwz_uint8_t act_method;    /* capability activating method */
        qxwz_uint64_t expire_time;  /* capability expired time */

        /*
         * `keys_num`:
         *      0: no keys in this capability;
         *      1: it has only one key;
         *      2: it has two keys, check them one by one;
         */
        qxwz_uint32_t keys_num;
        struct {
            struct {
                qxwz_uint32_t week_num; /* week number of gps time */
                qxwz_uint32_t week_sec; /* week second of gps time */
            } start_time, expire_time;
        } keys_valid_period[2];
    } caps[QXWZ_SDK_MAX_CAPS];
} qxwz_sdk_cap_info_t;

/**
 * @brief define coordinate frame information
 */
typedef struct {
    qxwz_int32_t coord_sys_count;                           /* coordinate frame count*/
    struct {
        qxwz_int32_t index;                                 /* identifier of the coordinate frame */
        qxwz_int32_t port;                                  /* port of the coordinate frame */
        qxwz_char_t name[QXWZ_SDK_MAX_COORD_FRAME_NAME];    /* description of the coordinate frame */
    } coord_sys[QXWZ_SDK_MAX_COORD_FRAME_NUM];
    qxwz_int32_t serv_config_status;                        /* server configuration status */
    qxwz_int32_t curr_coord_sys_index;                      /* current coordinate frame index */
} qxwz_sdk_coord_sys_info_t;



/*
 * Response for the RTCM execution plan query
 */
typedef struct {
    qxwz_int32_t exec_strategy_count;
    struct {
        qxwz_int32_t exec_type;
        qxwz_uint64_t exec_time;
        struct {
            qxwz_uint16_t year;
            qxwz_uint8_t  month;
            qxwz_uint8_t  day;
            qxwz_uint16_t minute;
        } exec_period;
    } exec_strategies[QXWZ_SDK_MAX_EXEC_STRATEGY_NUM];
} qxwz_sdk_exec_strategy_t;

/*
 * persistent callbacks
 */
/* sdk data callback */
typedef qxwz_void_t (*qxwz_sdk_data_callback_t)(qxwz_sdk_data_type_e type, const qxwz_void_t *data, qxwz_uint32_t len);
/* sdk status report callback */
typedef qxwz_void_t (*qxwz_sdk_status_callback_t)(qxwz_int32_t status_code);
typedef qxwz_void_t (*qxwz_sdk_cap_status_callback_t)(qxwz_uint32_t cap_id, qxwz_int32_t status_code);
/* sdk authentication callback */
typedef qxwz_void_t (*qxwz_sdk_auth_callback_t)(qxwz_int32_t status_code, qxwz_sdk_cap_info_t *cap_info);
/* sdk start callback */
typedef qxwz_void_t (*qxwz_sdk_start_callback_t)(qxwz_int32_t status_code, qxwz_uint32_t cap_id);
/* sdk stop callback */
typedef qxwz_void_t (*qxwz_sdk_stop_callback_t)(qxwz_int32_t status_code, qxwz_uint32_t cap_id);


/*
 * oneshot callbacks for coordinate frame
 */

/* coordinate frame getting callback */
typedef qxwz_void_t (*qxwz_sdk_get_coord_sys_callback_t)(qxwz_int32_t status_code, qxwz_sdk_coord_sys_info_t *coord_sys_info);
/* coordinate frame setting callback */
typedef qxwz_void_t (*qxwz_sdk_set_coord_sys_callback_t)(qxwz_int32_t status_code);


typedef qxwz_void_t (*qxwz_sdk_query_exec_strategy_callback_t)(qxwz_int32_t status_code, qxwz_sdk_exec_strategy_t *strategy);
typedef qxwz_void_t (*qxwz_sdk_resume_dsk_callback_t)(qxwz_int32_t status_code);

/**
 * @brief define capability activation response information
 */
typedef struct {
    qxwz_int32_t caps_num;      /* capability number */
    struct {
        qxwz_uint32_t cap_id;   /* capability ID */
        qxwz_int32_t result;    /*  QXWZ_SDK_STAT_CAP_ACT_SUCC       :activate cap successfully
                                    QXWZ_SDK_ERR_CAP_EXPIRED         :cap is expired
                                    QXWZ_SDK_ERR_CAP_NOT_INCLUDE     :there is no current cap in DSK
                                    QXWZ_SDK_ERR_CAP_SYSTEM_ERROR    :cap system error, please contact your administrator
                                    QXWZ_SDK_ERR_CAP_NEED_AUDIT_DSK  :please audit DSK firstly(real name authentication) by qxwz_sdk_audit_dsk
                                    QXWZ_SDK_ERR_CAP_ACT_FAIL        :activate cap fail, please contact your administrator
                                */
    } caps[QXWZ_SDK_MAX_CAPS];
} qxwz_sdk_activate_resp_t;

/* capability activating status report callback */
typedef qxwz_void_t (*qxwz_sdk_activate_callback_t)(qxwz_int32_t status_code, qxwz_sdk_activate_resp_t *act_resp);



/* get online cap info callback */
typedef qxwz_void_t (*qxwz_sdk_get_online_cap_info_callback_t)(qxwz_int32_t status_code, qxwz_sdk_cap_info_t *cap_info);

/**
 * @brief define SDK configuration information
 */
typedef struct {
    qwxz_sdk_key_type_e key_type;                           /* key type: AK/DSK */
    qxwz_char_t key[QXWZ_SDK_MAX_KEY_LEN];                  /* key string */
    qxwz_char_t secret[QXWZ_SDK_MAX_SECRET_LEN];            /* secret string */
    qxwz_char_t dev_id[QXWZ_SDK_MAX_DEV_ID_LEN];            /* device ID string */
    qxwz_char_t dev_type[QXWZ_SDK_MAX_DEV_TYPE_LEN];        /* device type string */
    qxwz_sdk_data_callback_t data_cb;                       /* SDK data callback */
    qxwz_sdk_status_callback_t status_cb;                   /* SDK status report callback */
    qxwz_sdk_cap_status_callback_t cap_status_cb;
    qxwz_sdk_auth_callback_t auth_cb;                       /* SDK authentication callback */
    qxwz_sdk_start_callback_t start_cb;                     /* SDK start callback */
} qxwz_sdk_config_t;

/**
 * @brief define SDK account information
 */
typedef struct {
    qxwz_int32_t key_type;                              /* key type: AK/DSK */
    qxwz_char_t key[QXWZ_SDK_MAX_KEY_LEN];              /* key string */
    qxwz_char_t secret[QXWZ_SDK_MAX_SECRET_LEN];        /* secret string */
    qxwz_char_t dev_id[QXWZ_SDK_MAX_DEV_ID_LEN];        /* device ID string */
    qxwz_char_t dev_type[QXWZ_SDK_MAX_DEV_TYPE_LEN];    /* device type string */
} qxwz_sdk_account_t;

/**
 * @brief define SDK configuration type
 */
typedef enum {
    QXWZ_SDK_CONF_SERV = 0,             /* configure sdk gateway server */
    QXWZ_SDK_CONF_OSS,                  /* configure sdk oss heartbeat and reconnect interval */
    QXWZ_SDK_CONF_NOSR_DATA_FORMAT,     /* configure nosr diff data format */
    QXWZ_SDK_CONF_NET_TIMEOUT,          /* configure network timeout, the value type should be `qxwz_uint32_t *`, 1 ~ 600s */
    QXWZ_SDK_CONF_DNS_SERVER,           /* configure sdk dns server */
    QXWZ_SDK_CONF_STARX_PUB_KEY,        /* configure sdk starx public key */
    QXWZ_SDK_CONF_LOG_INFO,
    QXWZ_SDK_CONF_CALLER,               /* configure caller infomation */
} qxwz_sdk_conf_t;


/**
 * @brief caller info struct
 * 
 */
typedef struct
{
    qxwz_char_t name[QXWZ_SDK_MAX_CALLER_NAME_LEN];         /* name */
    qxwz_char_t version[QXWZ_SDK_MAX_CALLER_VERSION_LEN];   /* version */
} qxwz_sdk_caller_info_t;


typedef enum {
    LOG_LEVEL_NONE = 0,
    LOG_LEVEL_FATAL,
    LOG_LEVEL_ERROR,
    LOG_LEVEL_WARNING,
    LOG_LEVEL_INFO,
    LOG_LEVEL_DEBUG,
    LOG_LEVEL_VERBOSE,
} LOG_LEVEL;

typedef enum
{
    LOG_TARGET_NONE = 0,
    LOG_TARGET_CONSOLE,
    LOG_TARGET_FILE,
    LOG_TARGET_ALL,
} LOG_TARGET;

#define QXWZ_LOG_DUMP_PATH_MAX_LEN  (128)
typedef struct {
    qxwz_uint32_t level;
    qxwz_uint32_t target;
    qxwz_char_t  dump_path[QXWZ_LOG_DUMP_PATH_MAX_LEN];
    qxwz_uint32_t is_color_console;
    qxwz_uint32_t is_close_crash_file;
    qxwz_uint32_t log_file_size;
    qxwz_uint32_t log_file_num;
} qxwz_sdk_log_conf_t;


/**
 * @brief define SDK gateway server configuration
 */
typedef struct {
    qxwz_char_t openapi_host[QXWZ_SDK_MAX_HOST_LEN];    /* openapi server port */
    qxwz_uint32_t openapi_port;                         /* openapi server port */

    qxwz_char_t oss_host[QXWZ_SDK_MAX_HOST_LEN];        /* oss server host name */
    qxwz_uint32_t oss_port;                             /* oss server port */
} qxwz_sdk_serv_conf_t;

/**
 * @brief define SDK oss gateway configuration item
 */
typedef struct {
    qxwz_uint32_t oss_heartbeat_interval;   /* oss heartbeat interval */
    qxwz_uint32_t oss_reconnect_interval;   /* oss reconnect interval */
} qxwz_sdk_oss_conf_t;

/**
 * @brief define nosr data format
 */
typedef enum {
    QXWZ_SDK_NOSR_QX_FORMAT,        /* QXWZ data format */
    QXWZ_SDK_NOSR_STD_FORMAT        /* standard rtcm data format */
} qxwz_sdk_nosr_data_format_t;

/**
 * @brief define SDK dns server configuration
 */
typedef struct {
    qxwz_char_t dns_server[QXWZ_SDK_DNS_SERVER_LEN];    /* dns server ip list */
} qxwz_sdk_dns_serv_conf_t;


/* sids data structure */
typedef struct {
    qxwz_uint8_t sig_id;               /* Signal number */
    qxwz_uint8_t sig_int;              /* Signal integrity */
} qxwz_sids_sig_info_t;

typedef struct {
    qxwz_uint8_t sat_id;               /* Satellite number */
    qxwz_uint8_t sig_num;              /* the total signal numbers of a satellite */
    qxwz_sids_sig_info_t *sig_info;
} qxwz_sids_sat_info_t;

typedef struct {
    qxwz_uint8_t ctrl_meta;            /* Control byte */
    qxwz_uint8_t multi_msg_flag;       /* MultipleMessage */
    qxwz_uint8_t gnss_sys;             /* 'G' = GPS, 'R' = GLONASS, 'C' = COMPASS(BDS), 'E' = GALILEO  'N' = NULL */
    struct {
        qxwz_uint16_t week_num;
        qxwz_uint32_t week_sec;        /* GPS seconds */
    } gps_time;
    qxwz_uint8_t sat_num;              /* Satellite number */
    qxwz_sids_sat_info_t *sat_info;
} qxwz_sids_sid_info_t;                /* Satellite integrity data */










/*
 * device center
 */

/*
 * ionosphere limit
 */



typedef struct
{
    qxwz_uint32_t year;                                                     /* year */
    qxwz_uint32_t month;                                                    /* month */
    qxwz_uint32_t day;                                                      /* day */
    qxwz_uint32_t minute;                                                   /* minute */
} qxwz_sdk_account_rating_t;

typedef enum
{
    QXWZ_SDK_ACCOUNT_LIFECYCLE_DIMENSIONS_DSK = 0,                          /* dsk */
    QXWZ_SDK_ACCOUNT_LIFECYCLE_DIMENSIONS_SI = 1,                           /* si_capability */
    QXWZ_SDK_ACCOUNT_LIFECYCLE_DIMENSIONS_UNKNOW,                           /* unknow lifecycle dimensions */
} qxwz_sdk_lifecycle_dimensions_e;

typedef enum
{
    QXWZ_SDK_DSK_STATE_INITIAL = 0,                                         /* initial */
    QXWZ_SDK_DSK_STATE_NOT_ACTIVATE = 1,                                    /* dsk not activate */
    QXWZ_SDK_DSK_STATE_EXPIRED = 2,                                         /* dsk has expired */
    QXWZ_SDK_DSK_STATE_PAUSE = 3,                                           /* dsk pause */
    QXWZ_SDK_DSK_STATE_ACTIVATE = 9,                                        /* dsk activate */
    QXWZ_SDK_DSK_STATE_UNKNOW,                                              /* unknow dsk state */
} qxwz_sdk_dsk_state_e;

typedef enum
{
    QXWZ_SDK_CAPABILITY_STATE_NOT_ACTIVATE = 1,                             /* capability not activate */
    QXWZ_SDK_CAPABILITY_STATE_EXPIRED = 2,                                  /* capability has expired */
    QXWZ_SDK_CAPABILITY_STATE_ACTIVATE = 9,                                 /* capability activate */
    QXWZ_SDK_CAPABILITY_STATE_UNKNOW,                                       /* unknow capability state */
} qxwz_sdk_cap_state_e;


typedef struct          
{           
    qxwz_uint32_t cap_id;                                                   /* capability ID */
    qxwz_uint32_t cap_type;                                                 /* capability type(0: annual and monthly packages  1: billing by volume) */
    qxwz_sdk_cap_state_e cap_state;                                         /* capability state */
    qxwz_uint64_t create_time;                                              /* capability create time */
    qxwz_uint64_t force_active_time;                                        /* capability force active time */
    qxwz_uint64_t active_time;                                              /* capability active time */
    qxwz_uint64_t expire_time;                                              /* capability expired time */
    qxwz_sdk_account_rating_t rating_value;                                 /* capability duration */
} qxwz_cap_detailed_info_t;

typedef struct
{
    qxwz_uint64_t siId;                                                     /* service instance id */
    qxwz_char_t sik[QXWZ_SDK_SERVICE_INSTANCE_SIK_LEN];                     /* service instance sik */
    qxwz_char_t ak[QXWZ_SDK_MAX_KEY_LEN];                                   /* key string */
    qxwz_sdk_lifecycle_dimensions_e lifecycle_dimension;                    /* dimensions of the lifecycle */
    qxwz_char_t dsk[QXWZ_SDK_MAX_KEY_LEN];                                  /* key string */
    qxwz_char_t dev_id[QXWZ_SDK_MAX_DEV_ID_LEN];                            /* device ID string */
    qxwz_char_t dev_type[QXWZ_SDK_MAX_DEV_TYPE_LEN];                        /* device type string */
    qxwz_sdk_dsk_state_e dsk_state;                                         /* DSK state */
    qxwz_uint64_t create_time;                                              /* account create time */
    qxwz_uint64_t force_active_time;                                        /* account force active time */
    qxwz_uint64_t active_time;                                              /* account active time */
    qxwz_uint64_t expire_time;                                              /* account expired time */
    qxwz_sdk_account_rating_t rating_value;                                 /* account duration */
    qxwz_uint32_t caps_num;                                                 /* cap num */
    qxwz_cap_detailed_info_t cap_detaild_info[QXWZ_SDK_MAX_CAPS];           /* cap detaild infomation */
} qxwz_sdk_capabilities_info_t;


typedef qxwz_void_t (*qxwz_sdk_query_capabilities_callback_t)(qxwz_int32_t status_code, qxwz_sdk_capabilities_info_t* capbilities_info);


/**
 * get SDK version string
 *
 * @return:
 *      pointer of the version string;
 */
QXWZ_PUBLIC(const qxwz_char_t*) qxwz_sdk_version(void);

/**
 * get SDK build information
 *
 * @return:
 *      pointer of the build information string;
 */
QXWZ_PUBLIC(const qxwz_char_t*) qxwz_sdk_get_build_info(void);

/**
 * set common configs
 *
 * @param[in]  type: type of the configuration, see definition of `qxwz_sdk_conf_t`;
 * @param[in]  conf: pointer to the specific parameter;
 *
 * @return:
 *      0: succeeds;
 *     <0: fails;
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_config(qxwz_sdk_conf_t type, qxwz_void_t* conf);

/**
 * initialize SDK
 *
 * @param[in]  config: collect of account and callbacks;
 *
 * @return:
 *      0: succeeds;
 *     <0: fails;
 *
 * Notice:
 *      If something wrong happens to the SDK, the error code would be published through
 *      the `status_cb` callback.
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_init(qxwz_sdk_config_t *config);

/**
 * get account information including key type, key, secret, device id and device type.
 *
 * @param[out]  account: structure pointer of account information;
 *
 * @return:
 *      0: succeeds;
 *     <0: fails;
 *
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_get_account(qxwz_sdk_account_t *account);


/**
 * do authentication
 *
 * @return:
 *      0: succeeds;
 *     <0: fails;
 *
 * Notice:
 *      The result of authentication would be notified through the `auth_cb`,
 *      which is registered in the `qxwz_sdk_init` call.
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_auth(void);

/**
 * start the service corresponding to the specific capability
 *
 * @param[in]  cap_id: identifier of the capability;
 *
 * @return:
 *      0: succeeds;
 *     <0: fails;
 *
 * Notice:
 *      The result of start a capability would be notified through the `start_cb`,
 *      which is registered in the `qxwz_sdk_init` call.
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_start(qxwz_uint32_t cap_id);

/**
 * start the service corresponding to the specific capability
 *
 * @param[in]  cap_id: identifier of the capability;
 * @param[in]  params: parameters needed to start the capability;
 *
 * @return:
 *      0: succeeds;
 *     <0: fails;
 *
 * Notice:
 *      The result of start a capability would be notified through the `start_cb`,
 *      which is registered in the `qxwz_sdk_init` call.
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_start_with_params(qxwz_uint32_t cap_id, qxwz_void_t *params);

/**
 * drive SDK run once
 *
 * @param[in]  monotonic_tick: monotonic increasing seconds;
 *
 * @return:
 *      0: succeeds;
 *     <0: fails;
 *
 * Notice:
 *      The result of start a capability would be notified through the `start_cb`,
 *      which is registered in the `qxwz_sdk_init` call.
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_tick(qxwz_uint64_t monotonic_tick);

/**
 * stop the service corresponding to the specific capability
 *
 * @param[in]  cap: identifier of the capability;
 *
 * @return:
 *      0: succeeds;
 *     <0: fails;
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_stop(qxwz_uint32_t cap);

/**
 * cleanup SDK
 *
 * @return:
 *      0: succeeds;
 *     <0: fails;
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_cleanup(void);

/**
 * upload gga
 *
 * @param[in]  gga: pointer of GGA string;
 * @param[in]  len: length of the string;
 *
 * @return:
 *      0: succeeds;
 *     <0: fails;
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_upload_gga(const qxwz_char_t *gga, qxwz_uint32_t len);

/**
 * upload gga for a sepicific capability
 *
 * @param[in]  cap_id: identifier of the capability;
 * @param[in]  gga: pointer of GGA string;
 * @param[in]  len: length of the string;
 *
 * @return:
 *      0: succeeds;
 *     <0: fails;
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_upload_gga_by_cap_id(qxwz_uint32_t cap_id, const qxwz_char_t *gga, qxwz_uint32_t len);



/**
 * get detailed information of the capabilities bound to the account
 *
 * @param[in]  cap_info: structure pointer of capability information;
 *
 * @return:
 *      0: succeeds;
 *     <0: fails;
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_get_cap_info(qxwz_sdk_cap_info_t *cap_info);

/**
 * get coordinate system information, including count of coordinate system,
 * detail infomation of each coordinate system and index of current coordinate system in use.
 * this function is asynchronous, you will get the result in the callback function after it is fetched.
 *
 *  @param[in] get_coord_sys_cb: the callback which will be called after fetching information from server;
 *
 *  @return:
 *       0: succeeds;
 *      <0: fails;
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_get_coord_sys(qxwz_sdk_get_coord_sys_callback_t get_coord_sys_cb);

/**
 *  set coordinate system by index.
 *  this function is asynchronous, you will get the setting result code in the callback function.
 *  if you set coordinate system after starting NOSR, you need restart NOSR after setting successfully.
 *
 *  @param[in] coord_sys_index: the index of coordinate system;
 *  @param[in] set_coord_sys_cb: the callback which will be called after setting is done;
 *
 *  @return:
 *       0: succeeds;
 *      <0: fails;
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_set_coord_sys(qxwz_uint32_t coord_sys_index, qxwz_sdk_set_coord_sys_callback_t set_coord_sys_cb);

/**
 *  query RTCM execution plans of the current account.
 *  this function is asynchronous, you will get the result in the callback function.
 *
 *  @param[in] query_exec_strategy_cb: the callback which will be called after query is done;
 *
 *  @return:
 *       0: succeeds;
 *      <0: fails;
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_query_exec_strategy(qxwz_sdk_query_exec_strategy_callback_t query_exec_strategy_cb);

/**
 *  resume the paused account.
 *  this function is asynchronous, you will get the result in the callback function.
 *
 *  @param[in] resume_dsk_cb: the callback which will be called after resuming is done;
 *
 *  @return:
 *       0: succeeds;
 *      <0: fails;
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_resume_dsk(qxwz_sdk_resume_dsk_callback_t resume_dsk_cb);


/**
 *  activate the capabilities from terminal
 *
 *  @param[in] caps: the array of capabilities;
 *  @param[in] caps_num: the number of capbilities;
 *  @param[in] act_cb: the callback to notify the activation result;
 *
 *  @return:
 *       0: succeeds;
 *      <0: fails;
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_activate(const qxwz_uint32_t *caps, qxwz_int32_t caps_num, qxwz_sdk_activate_callback_t act_cb);












/**
 * get details of account capabilities online
 *
 * @param[in]  get_online_cap_info_cb: get online cap info callback
 *
 * @return:
 *      0: succeeds
 *     <0: fails
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_get_online_cap_info(qxwz_sdk_get_online_cap_info_callback_t get_online_cap_info_cb);



/**
 * @brief 
 * 
 * @param type data type
 * @param data datas
 * @param data_len datas length
 * @param encode_buffer encode buffer
 * @param encode_buffer_len encode buffer length
 * @return -2: invaild params
 *         >0: encode data len 
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sidiff_data_encode(qxwz_sdk_data_type_e type, qxwz_uint8_t *data, qxwz_uint16_t data_len, qxwz_uint8_t* encode_buffer, qxwz_uint16_t encode_buffer_len);



/**
 * query capabilities
 *
 * @param[in]  query_capabilities_cb: query capabilities callback
 *
 * @return:
 *      0: succeeds
 *     <0: fails
 */
QXWZ_PUBLIC(qxwz_int32_t) qxwz_sdk_query_capabilities(qxwz_sdk_query_capabilities_callback_t query_capabilities_cb);


#ifdef __cplusplus
}
#endif

#endif
