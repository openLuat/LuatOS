/*****************************************************************************
*  Copyright Statement:
*  --------------------
*  This software is protected by Copyright and the information contained
*  herein is confidential. The software may not be copied and the information
*  contained herein may not be used or disclosed except with the written
*  permission of MediaTek Inc. (C) 2005
*
*  BY OPENING THIS FILE, BUYER HEREBY UNEQUIVOCALLY ACKNOWLEDGES AND AGREES
*  THAT THE SOFTWARE/FIRMWARE AND ITS DOCUMENTATIONS ("MEDIATEK SOFTWARE")
*  RECEIVED FROM MEDIATEK AND/OR ITS REPRESENTATIVES ARE PROVIDED TO BUYER ON
*  AN "AS-IS" BASIS ONLY. MEDIATEK EXPRESSLY DISCLAIMS ANY AND ALL WARRANTIES,
*  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF
*  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE OR NONINFRINGEMENT.
*  NEITHER DOES MEDIATEK PROVIDE ANY WARRANTY WHATSOEVER WITH RESPECT TO THE
*  SOFTWARE OF ANY THIRD PARTY WHICH MAY BE USED BY, INCORPORATED IN, OR
*  SUPPLIED WITH THE MEDIATEK SOFTWARE, AND BUYER AGREES TO LOOK ONLY TO SUCH
*  THIRD PARTY FOR ANY WARRANTY CLAIM RELATING THERETO. MEDIATEK SHALL ALSO
*  NOT BE RESPONSIBLE FOR ANY MEDIATEK SOFTWARE RELEASES MADE TO BUYER'S
*  SPECIFICATION OR TO CONFORM TO A PARTICULAR STANDARD OR OPEN FORUM.
*
*  BUYER'S SOLE AND EXCLUSIVE REMEDY AND MEDIATEK'S ENTIRE AND CUMULATIVE
*  LIABILITY WITH RESPECT TO THE MEDIATEK SOFTWARE RELEASED HEREUNDER WILL BE,
*  AT MEDIATEK'S OPTION, TO REVISE OR REPLACE THE MEDIATEK SOFTWARE AT ISSUE,
*  OR REFUND ANY SOFTWARE LICENSE FEES OR SERVICE CHARGE PAID BY BUYER TO
*  MEDIATEK FOR SUCH MEDIATEK SOFTWARE AT ISSUE. 
*
*  THE TRANSACTION CONTEMPLATED HEREUNDER SHALL BE CONSTRUED IN ACCORDANCE
*  WITH THE LAWS OF THE STATE OF CALIFORNIA, USA, EXCLUDING ITS CONFLICT OF
*  LAWS PRINCIPLES.  ANY DISPUTES, CONTROVERSIES OR CLAIMS ARISING THEREOF AND
*  RELATED THERETO SHALL BE SETTLED BY ARBITRATION IN SAN FRANCISCO, CA, UNDER
*  THE RULES OF THE INTERNATIONAL CHAMBER OF COMMERCE (ICC).
*
*****************************************************************************/

/*******************************************************************************
 * Filename:
 * ---------
 *  tls_api.h
 *
 * Project:
 * --------
 *   Maui
 *
 * Description:
 * ------------
 *   This file contains function prototypes, constants and enum for TLS
 *   API used for socket applications.
 *
 * Author:
 * -------
 * -------
 *
 *==============================================================================
 * 				HISTORY
 * Below this line, this part is controlled by PVCS VM. DO NOT MODIFY!! 
 *------------------------------------------------------------------------------
 * removed!
 *
 * removed!
 * removed!
 * removed!
 *
 * removed!
 * removed!
 * removed!
 *
 * removed!
 * removed!
 * removed!
 *
 * removed!
 * removed!
 * removed!
 *
 * removed!
 * removed!
 * removed!
 *
 * removed!
 * removed!
 * removed!
 *
 * removed!
 * removed!
 * removed!
 *
 * removed!
 * removed!
 * removed!
 *
 *------------------------------------------------------------------------------
 * Upper this line, this part is controlled by PVCS VM. DO NOT MODIFY!! 
 *==============================================================================
 *******************************************************************************/
#ifndef _AM_SSL_H_
#define _AM_SSL_H_


#ifndef _SSL_API_H
#ifdef AM_TODO_SSL
#include "ssl_api.h"
#endif
#endif /* _SSL_API_H */

#ifndef _TLS_CONST_H_
//#include "tls_const.h"
#endif /* _TLS_CONST_H_ */

#ifndef _TLS_APP_ENUMS_H
//#include "tls_app_enums.h"
#endif /* _TLS_APP_ENUMS_H */

#ifndef _TLS_CALLBACK_H_
//#include "tls_callback.h"
#endif /* _TLS_CALLBACK_H_ */

#ifndef _TLS2APP_STRUCT_H_
//#include "tls2app_struct.h"
#endif /* _TLS2APP_STRUCT_H_ */

//#include "tls_enums.h"


#include "ssl.h"
#include "ctr_drbg.h"
#include "entropy.h"


#define _TLS_CTX_API_PROTOTYPES_

    
#define TLS_MAX_FILENAME_LEN (130)
#define TLS_PASSWD_BUF_LEN   (64)
#define TLS_MAX_MOD_NAME_LEN (12)
#define TLS_MAX_AUTHNAMES    (32)



#define MAX_IP_SOCKET_NUM  (10)

//tls_const.h
#ifdef __AM_SSL__
#define TLS_APP_COMMON_NUM 4
#else
#define TLS_APP_COMMON_NUM 3
#endif
//AM add by hanjun.liu @20140126 for CR_MKBug00021179_hanjun.liu end

#if (!(defined OBIGO_Q03C_BROWSER ) &&(defined WAP_SEC_SUPPORT))
#define TLS_APP_WAP_NUM 1
#else
#define TLS_APP_WAP_NUM 0
#endif

#ifdef __EMAIL__
#define TLS_APP_EMAIL_NUM 1
#else
#define TLS_APP_EMAIL_NUM 0
#endif
    
typedef enum
{
        TLS_APP_NUM_SPARED = TLS_APP_COMMON_NUM,                                
        TLS_WAP_APP_NUM_END =  TLS_APP_NUM_SPARED + TLS_APP_WAP_NUM,  
        TLS_EMAIL_APP_NUM_END = TLS_WAP_APP_NUM_END + TLS_APP_EMAIL_NUM,    

        TLS_MAX_GLOBAL_CTX = TLS_EMAIL_APP_NUM_END               
} tls_max_app_num_enum;

#define TLS_MAX_CIPHERS             (32)
#define TLS_MAX_CLIENT_AUTH         (7)
#define TLS_ALL_ROOT_CERTS          (0xFF)


//tls_app_enums.h
/***************************************************************************
 * <GROUP Enums>
 *
 * SSL alert levels.
 ***************************************************************************/
typedef enum {
    TLS_ALERT_LV_WARNING = 1, /* Warning alert. */
    TLS_ALERT_LV_FATAL = 2    /* Fatal alert, application MUST terminate the connection immediately. */
} tls_alert_level_enum;


/***************************************************************************
 * <GROUP Enums>
 *
 * SSL alert descriptions. Ref. RFC 4346, section 7.2.2.
 ***************************************************************************/
typedef enum {
    TLS_ALERT_CLOSE_NOTIFY                = 0,  /* Peer shuts down the connection. */
    TLS_ALERT_UNEXPECTED_MESSAGE          = 10, /* Received an unexped mesage, always a fatal. */
    TLS_ALERT_BAD_RECORD_MAC              = 20, /* Bad MAC, always a fatal. */
    TLS_ALERT_DECRYPTION_FAILED           = 21, /* Decryption failed, always a fatal. */
    TLS_ALERT_RECORD_OVERFLOW             = 22, /* Record size exceeds the limitation, always a fatal. */
    TLS_ALERT_DECOMPRESSION_FAILURE       = 30, /* Deccompression failed, always a fatal. */
    TLS_ALERT_HANDSHAKE_FAILURE           = 40, /* Handshake failed, fatal. */
    TLS_ALERT_NOCERTIFICATE_RESERVED      = 41, /* Response to a certification request if no appropriate certificate is available, SSLv3 only. */
    TLS_ALERT_BAD_CERTIFICATE             = 42, /* A certificate was corrupt, signatures that did not verify correctly. */
    TLS_ALERT_UNSUPPORTED_CERTIFICATE     = 43, /* Unsupported certificate type. */
    TLS_ALERT_CERTIFICATE_REVOKED         = 44, /* Received a revoked certificate from peer. */
    TLS_ALERT_CERTIFICATE_EXPIRED         = 45, /* A certificate has expired or not yet valid. */
    TLS_ALERT_CERTIFICATE_UNKNOWN         = 46, /* Some unspecificate issue in processing the certificate.  */
    TLS_ALERT_ILLEGAL_PARAMETER           = 47, /* Illegal parameter in the message, always a fatal. */
    TLS_ALERT_UNKNOWN_CA                  = 48, /* The certificate chain cannot be verified successfully due to untrusted CA, always a fatal. */
    TLS_ALERT_ACCESS_DENIED               = 49, /* sender decided not to proceed with negotiation when access control was applied, always a fatal. */
    TLS_ALERT_DECODE_ERROR                = 50, /* The field in a message is incorrect, always a fatal. */
    TLS_ALERT_DECRYPT_ERROR               = 51, /* a handshake cryptographic operation failed, including verify a signature, decrypt a key exchange, or validate a finished mesasge. */
    TLS_ALERT_EXPORT_RESTRICTION_RESERVED = 60, /* A negotiation not in compliance with export restrictions was detected. */
    TLS_ALERT_PROTOCOL_VERSION            = 70, /* The protocol version proposed by client is not supported by server side, always a fatal. */
    TLS_ALERT_INSUFFICIENT_SECURITY       = 71, /* The server requires cphers more secure than those supported by the client, always a fatal. */
    TLS_ALERT_INTERNAL_ERROR              = 80, /* An internal error unrelated to the peer, always a fatal. */
    TLS_ALERT_USER_CANCELLED              = 90, /* The handshake is canceled for some reason unrelated to a protocol failure, generally a warning. */
    TLS_ALERT_NO_RENEGOTIATION            = 100 /* When peer suggest to renegotiate again but local rejects it, always a warning. */
} tls_alert_desc_enum;







/***************************************************************************
 * <GROUP Enums>
 *
 * Encoding of certificate files.
 * Ref. tls_set_verify().
 ***************************************************************************/
typedef enum {
    TLS_FILETYPE_PEM = 0, /* PEM encoding */
    TLS_FILETYPE_DER      /* DER encoding */
} tls_filetype_enum;


/***************************************************************************
 * <GROUP Enums>
 *
 * Client authentication modes.
 * Ref. tls_auth_mode_enum().
 ***************************************************************************/
typedef enum {
    TLS_CLIENT_AUTH_BEGIN,
    TLS_CLIENT_AUTH_RSA_CLIENT, /* RSA client side */
    TLS_CLIENT_AUTH_RSA_SERVER, /* RSA server side */
    TLS_CLIENT_AUTH_DSS_CLIENT, /* DSS(DSA) cient side */
    TLS_CLIENT_AUTH_DSS_SERVER, /* DSS(DSA) server side */
    TLS_CLIENT_AUTH_END = 0xff
} tls_auth_mode_enum;





/***************************************************************************
 * <GROUP Enums>
 *
 * User decision of handling the received invalid certificate.
 * Ref. app_tls_invalid_cert_ind_struct.
 ***************************************************************************/
typedef enum {
    TLS_USER_REJECT          = 0, /* User rejects the invalid certificate. */
    TLS_USER_ACCEPT_ONCE     = 1, /* User accepts the invalid certificate for this time */
    TLS_USER_ACCEPT_FOREVER  = 2  /* User accepts the invalid cert forever */
} tls_inval_cert_action;


/***************************************************************************
 * <GROUP Enums>
 *
 * Suppoerted ciphers.
 * Ref. tls_set_ciphers().
 * <i>Note</i>:
 * (*) TLS 1.1 implementations MUST NOT negotiate these cipher suites in TLS
 *     1.1 mode. For backward compatibility, they may be offered in the
 *     ClientHello for use with TLS 1.0 or SSLv3-only servers.
 *     TLS 1.1 clients MUST check that the server did not choose one of these
 *     cipher suites during the handshake.
 ***************************************************************************/
typedef enum {
    TLS_NULL_MD5                = 0,  /* 0x0001, TLS_RSA_WITH_NULL_MD5. */
    TLS_EXP_RC4_MD5             = 1,  /* 0x0003, TLS_RSA_EXPORT_WITH_RC4_40_MD5.(*) */
    TLS_RC4_MD5                 = 2,  /* 0x0004, TLS_RSA_WITH_RC4_128_MD5. */
    TLS_RC4_SHA                 = 3,  /* 0x0005, TLS_RSA_WITH_RC4_128_SHA, TLS Profile MUST. */
    TLS_EXP_DES_CBC_SHA         = 4,  /* 0x0008, TLS_RSA_EXPORT_WITH_DES40_CBC_SHA.(*) */
    TLS_DES_CBC_SHA             = 5,  /* 0x0009, TLS_RSA_WITH_DES_CBC_SHA. */
    TLS_DES_CBC3_SHA            = 6,  /* 0x000A, TLS_RSA_WITH_3DES_EDE_CBC_SHA, TLS Profile MUST. */
    TLS_EXP_EDH_DSS_DES_CBC_SHA = 7,  /* 0x0011, TLS_DHE_DSS_EXPORT_WITH_DES40_CBC_SHA.(*) */
    TLS_EDH_DSS_CBC_SHA         = 8,  /* 0x0012, TLS_DHE_DSS_WITH_DES_CBC_SHA. */
    TLS_EDH_DSS_DES_CBC3_SHA    = 9,  /* 0x0013, TLS_DHE_DSS_WITH_3DES_EDE_CBC_SHA. */
    TLS_EXP_EDH_RSA_DES_CBC_SHA = 10, /* 0x0014, TLS_DHE_RSA_EXPORT_WITH_DES40_CBC_SHA.(*) */
    TLS_EDH_RSA_DES_CBC_SHA     = 11, /* 0x0015, TLS_DHE_RSA_WITH_DES_CBC_SHA. */
    TLS_EDH_RSA_DES_CBC3_SHA    = 12, /* 0x0016, TLS_DHE_RSA_WITH_3DES_EDE_CBC_SHA. */
    TLS_EXP_ADH_RC4_MD5         = 13, /* 0x0017, TLS_DH_anon_EXPORT_WITH_RC4_40_MD5.(*) */
    TLS_ADH_RC4_MD5             = 14, /* 0x0018, TLS_DH_anon_WITH_RC4_128_MD5. */
    TLS_EXP_ADH_DES_CBC_SHA     = 15, /* 0x0019, TLS_DH_anon_EXPORT_WITH_DES40_CBC_SHA.(*) */
    TLS_ADH_DES_CBC_SHA         = 16, /* 0x001A, TLS_DH_anon_WITH_DES_CBC_SHA. */
    TLS_ADH_DES_CBC3_SHA        = 17, /* 0x001B, TLS_DH_anon_WITH_3DES_EDE_CBC_SHA. */
 
    TLS_AES128_SHA              = 18, /* 0x002F, TLS_RSA_WITH_AES_128_CBC_SHA. */
    TLS_AES256_SHA              = 19, /* 0x0035, TLS_RSA_WITH_AES_256_CBC_SHA. */

    TLS_EXP1024_DES_CBC_SHA     = 20, /* 0x0062, TLS_RSA_EXPORT1024_WITH_DES_CBC_SHA. */
    TLS_EXP1024_RC4_SHA         = 21, /* 0x0064, TLS_RSA_EXPORT1024_WITH_RC4_56_SHA. */
    TLS_DHE_DSS_RC4_SHA         = 22, /* 0x0066, TLS_DHE_DSS_WITH_RC4_128_SHA. */

    TLS_ECDH_SECT163K1_RC4_SHA  = 23, /* 0xC002 in RFC 4492, TLS_ECDH_ECDSA_WITH_RC4_128_SHA. */
    TLS_ECDH_SECT163K1_NULL_SHA = 24, /* 0xC001 in RFC 4492, TLS_ECDH_ECDSA_WITH_NULL_SHA. */

    TLS_PSK_AES128_SHA          = 25, /* 0x008C in RFC 4279, TLS_PSK_WITH_AES_128_CBC_SHA. */
    TLS_PSK_DES_CBC3_SHA        = 26, /* 0x008B in RFC 4279, TLS_PSK_WITH_3DES_EDE_CBC_SHA. */
    TLS_UNKNOWN_CIPHER,
    TLS_TOTAL_CIPHER_NUM = TLS_UNKNOWN_CIPHER
} tls_cipher_enum ;





/***************************************************************************
 * <GROUP Enums>
 *
 * Bulk data encryption algorithms.
 * Ref. tls_cipher_info_struct returned by tls_get_cipher_info().
 ***************************************************************************/
typedef enum {
    TLS_ENC_ALGO_UNKNOWN,
    TLS_ENC_ALGO_NULL,      /* NULL */

    TLS_ENC_ALGO_DES_40,    /* DES 40 */
    TLS_ENC_ALGO_DES,       /* DES(56) */
    TLS_ENC_ALGO_3DES,      /* 3DES */

    TLS_ENC_ALGO_RC5,       /* RC5 */
    TLS_ENC_ALGO_RC5_56,    /* RC5_56 */

    TLS_ENC_ALGO_AES_128,   /* AES_128 */
    TLS_ENC_ALGO_AES_192,   /* AES_192,  new for OpenSSL */
    TLS_ENC_ALGO_AES_256,   /* AES_256 */

    TLS_ENC_ALGO_ARC4_40,   /* RC4_40 */
    TLS_ENC_ALGO_ARC4_56,   /* RC4_56, new for OpenSSL */
    TLS_ENC_ALGO_ARC4_64,   /* RC4_64, new for OpenSSL */
    TLS_ENC_ALGO_ARC4_128,  /* RC4_128 */

    TLS_ENC_ALGO_ARC2_40,   /* RC2_40 */
    TLS_ENC_ALGO_ARC2_56,   /* RC2_56, new for OpenSSL */
    TLS_ENC_ALGO_ARC2_64,   /* RC4_64 */
    TLS_ENC_ALGO_ARC2_128   /* RC2_128 */
} tls_encryption_enum;


/***************************************************************************
 * <GROUP Enums>
 *
 * Key exchange algorithms.
 * Ref. tls_cipher_info_struct returned by tls_get_cipher_info().
 ***************************************************************************/
typedef enum {
    TLS_KEY_ALGO_UNKNOWN,
    TLS_KEY_ALGO_RSA,            /* RSA */
    TLS_KEY_ALGO_RSA_EXPORT,     /* RSA_EXPORT */
    TLS_KEY_ALGO_DH,             /* DH */
    TLS_KEY_ALGO_DH_EXPORT,      /* DH_EXPORT */
    TLS_KEY_ALGO_DHE,            /* DH */
    TLS_KEY_ALGO_DHE_EXPORT,     /* DH_EXPORT */
    TLS_KEY_ALGO_ECDH,           /* ECDH */
    TLS_KEY_ALGO_ECDHE,          /* ECDHE */
    TLS_KEY_ALGO_ECMQV,          /* ECMQV */
    TLS_KEY_ALGO_DSA,            /* DSA */
    TLS_KEY_ALGO_PSK,            /* PSK */
    TLS_KEY_ALGO_DHE_PSK,        /* DHE_PSK */
    TLS_KEY_ALGO_RSA_PSK,        /* RSA_PSK */
    TLS_KEY_ALGO_MAX
} tls_key_exchange_enum;


/***************************************************************************
 * <GROUP Enums>
 *
 * Server authentication algorithms.
 * Ref. tls_cipher_info_struct returned by tls_get_cipher_info().
 ***************************************************************************/
typedef enum {
    TLS_AUTH_ALGO_UNKNOWN,
    TLS_AUTH_ALGO_ANON,      /* ANON */
    TLS_AUTH_ALGO_RSA,       /* RSA */
    TLS_AUTH_ALGO_DSS,       /* DSS */
    TLS_AUTH_ALGO_ECDSA,     /* ECDSA */
    TLS_AUTH_ALGO_PSK        /* PSK */
} tls_auth_enum;


/***************************************************************************
 * <GROUP Enums>
 *
 * Message digest algorithms.
 * Ref. tls_cipher_info_struct returned by tls_get_cipher_info().
 ***************************************************************************/
typedef enum {
    TLS_HASH_UNKNOWN,
    TLS_HASH_MD2,       /* MD2 */
    TLS_HASH_MD4,       /* MD4 */
    TLS_HASH_MD5,       /* MD5 */
    TLS_HASH_SHA1,      /* SHA1 */
    TLS_HASH_SHA224,    /* SHA224 */
    TLS_HASH_SHA256,    /* SHA256 */
    TLS_HASH_SHA384,    /* SHA384 */
    TLS_HASH_SHA512     /* SHA512 */
} tls_hash_enum;


//tls_enums.h
typedef enum {
    TLS_NO_NOTIFY   = 0,
    TLS_NEED_NOTIFY = 1
} tls_notify_enum;

typedef enum {
    TLS_XID_NOT_FOUND = 0,
    TLS_ROOT_CERT = 1,
    TLS_USER_CERT = 2,
    TLS_PRIV_KEY  = 3
} tls_cert_type_enum;

typedef enum {
    TLS_FS_FILE,
    TLS_FS_DIR
} tls_fstype_enum;


typedef enum {
    TLS_RSA_SIGN = 1,   /* specified in RFC 4346 */
    TLS_DSS_SIGN = 2
} raw_client_cert_type_enum;

/* TLS connection states */
typedef enum {
    TLS_S_CLOSED      = 0,
    TLS_S_CONNECTING  = 1,
    TLS_S_HANDSHAKING = 2,
    TLS_S_HANDSHAKED  = 3,
    TLS_S_SHUTDOWNED  = 4 //暂时未用
} tls_state_enum;
    
/***************************************************************************
 * <GROUP Enums>
 *
 * Client authentication modes to be used in the SSL context,
 * Ref. sec_ssl_ctx_set_client_auth_modes().
 ***************************************************************************/
typedef enum {
    RSA_SIGN_CLIENTSIDE   = 0, /* RSA client side */
    RSA_SIGN_SERVERSIDE   = 1, /* RSA server side */
    DSS_SIGN_CLIENTSIDE   = 2, /* DSS(DSA) cient side */
    DSS_SIGN_SERVERSIDE   = 3, /* DSS(DSA) server side */
    CLIENT_AUTH_MODE_END  = 0xff,
    SERVER_AUTH_MODE_END  = CLIENT_AUTH_MODE_END,
    SEC_AUTH_MODE_END     = CLIENT_AUTH_MODE_END
} ssl_auth_mode_enum;

/***************************************************************************
 * <GROUP Enums>
 *
 * Supported ciphersuites to be specified in sec_ssl_ctx_set_cipher_list().
 ***************************************************************************/
typedef enum {
    /* SSLv2, SSLv3, TLSv1 cipher suites */
    NULL_MD5                = 0,  /* 0x0001, TLS_RSA_WITH_NULL_MD5 */
    EXP_RC4_MD5             = 1,  /* 0x0003, TLS_RSA_EXPORT_WITH_RC4_40_MD5 */
    RC4_MD5                 = 2,  /* 0x0004, TLS_RSA_WITH_RC4_128_MD5 */
    RC4_SHA                 = 3,  /* 0x0005, TLS_RSA_WITH_RC4_128_SHA, TLS Profile MUST */
    EXP_DES_CBC_SHA         = 4,  /* 0x0008, TLS_RSA_EXPORT_WITH_DES40_CBC_SHA */
    DES_CBC_SHA             = 5,  /* 0x0009, TLS_RSA_WITH_DES_CBC_SHA */
    DES_CBC3_SHA            = 6,  /* 0x000A, TLS_RSA_WITH_3DES_EDE_CBC_SHA, TLS Profile MUST */
    EXP_EDH_DSS_DES_CBC_SHA = 7,  /* 0x0011, TLS_DHE_DSS_EXPORT_WITH_DES40_CBC_SHA */
    EDH_DSS_CBC_SHA         = 8,  /* 0x0012, TLS_DHE_DSS_WITH_DES_CBC_SHA */
    EDH_DSS_DES_CBC3_SHA    = 9,  /* 0x0013, TLS_DHE_DSS_WITH_3DES_EDE_CBC_SHA */
    EXP_EDH_RSA_DES_CBC_SHA = 10, /* 0x0014, TLS_DHE_RSA_EXPORT_WITH_DES40_CBC_SHA */
    EDH_RSA_DES_CBC_SHA     = 11, /* 0x0015, TLS_DHE_RSA_WITH_DES_CBC_SHA */
    EDH_RSA_DES_CBC3_SHA    = 12, /* 0x0016, TLS_DHE_RSA_WITH_3DES_EDE_CBC_SHA */
    EXP_ADH_RC4_MD5         = 13, /* 0x0017, TLS_DH_anon_EXPORT_WITH_RC4_40_MD5 */
    ADH_RC4_MD5             = 14, /* 0x0018, TLS_DH_anon_WITH_RC4_128_MD5 */
    EXP_ADH_DES_CBC_SHA     = 15, /* 0x0019, TLS_DH_anon_EXPORT_WITH_DES40_CBC_SHA */
    ADH_DES_CBC_SHA         = 16, /* 0x001A, TLS_DH_anon_WITH_DES_CBC_SHA */
    ADH_DES_CBC3_SHA        = 17, /* 0x001B, TLS_DH_anon_WITH_3DES_EDE_CBC_SHA */

    /* AES ciphersuites from RFC 3268, extending TLS v1.0 */
    AES128_SHA              = 18, /* 0x002F, TLS_RSA_WITH_AES_128_CBC_SHA */
    AES256_SHA              = 19, /* 0x0035, TLS_RSA_WITH_AES_256_CBC_SHA */

    /* Additional Extport 1024 and other ciphersuites */
    EXP1024_DES_CBC_SHA     = 20, /* 0x0062, TLS_RSA_EXPORT1024_WITH_DES_CBC_SHA */
    EXP1024_RC4_SHA         = 21, /* 0x0064, TLS_RSA_EXPORT1024_WITH_RC4_56_SHA */
    DHE_DSS_RC4_SHA         = 22, /* 0x0066, TLS_DHE_DSS_WITH_RC4_128_SHA */

    /* ECDH */
    ECDH_SECT163K1_RC4_SHA  = 23, /* 0xC002 in RFC 4492, TLS_ECDH_ECDSA_WITH_RC4_128_SHA */
    ECDH_SECT163K1_NULL_SHA = 24, /* 0xC001 in RFC 4492, TLS_ECDH_ECDSA_WITH_NULL_SHA */

    /* PSK */    
    PSK_AES128_SHA          = 25, /* 0x008C in RFC 4279, TLS_PSK_WITH_AES_128_CBC_SHA */
    PSK_DES_CBC3_SHA        = 26, /* 0x008B in RFC 4279, TLS_PSK_WITH_3DES_EDE_CBC_SHA */
    SEC_TOTAL_CIPHER_NUM
} sec_cipher_enum;

//tls2app_struct.h


/***************************************************************************
 * <GROUP Structures>
 *
 * Data structure holding a certificate in DER.
 * Ref. tls_get_peer_cert() and callback function tls_cert_verify_callback().
 ***************************************************************************/
typedef struct {
    kal_uint32 len;   /* The size of the certificate in bytes */
    kal_uint8 *data;  /* Data of the certficate in DER format */
} tls_cert_struct;


// "tls_callback.h"
/*****************************************************************************
 * <GROUP Structures>
 *
 * A data structure storing information of cerficiate from peer and
 * the verify result.
 *****************************************************************************/
typedef struct {
    kal_int8         sock_id;      /* Socket id of the SSL connection. */
    tls_cert_struct  **cert_chain; /* Certificate chain sent from peer in array.
                                      Application can extracts the certificate
                                      chain from this parameter if needed in
                                      tls_cert_verify_callback(). */
    kal_uint32       *warnings;    /* Warning list of each cert in cert_chain. */
    kal_int32        error;        /* Certificate validation result. */
} tls_x509_struct;


/*****************************************************************************
 * <GROUP Callback Functions>
 *
 * Function
 *   tls_cert_verify_callback
 * DESCRIPTION
 *   Prototype of verification function which is called whenever a certificate
 *   is verified during a SSL/TLS handshake.
 * PARAMETERS
 *   x509     : [IN] A data structure holding cerficiate information and
 *                   verification result.
 *   arg      : [IN] User-specified pointer to be passed to this callback.
 * RETURN VALUES
 *   OPENAT_TLS_ERR_NONE          : If application want to override the validation
 *                           error and continue normally.
 *   OPENAT_TLS_ERR_CERT_VALIDATE : If application want the library to abort the 
 *                           handshake process.
 * SEE ALSO
 *   tls_set_verify()
 * EXAMPLE
 *   <code>
 *   kal_int32 app_cert_verify_callback(tls_x509_struct* x509, void* arg)
 *   {
 *       int i = 0;
 *       kal_uint32 cert_len = 0;
 *       kal_uint8 *cert_data = NULL;
 *       kal_uint32 cert_warn = 0;
 *
 *       if (x509->sock_id != valid_socket_id)
 *           error_handling();
 *
 *       for (x509->cert_chain[i]; x509->cert_chain[i]; i++)
 *       {
 *            cert_len = x509->cert_chain[i].len;
 *            cert_data = x509->cert_chain[i].data;
 *            cert_warn = x509->warnings[i];
 *            process_cert(cert_len, cert_data, cert_warn);
 *       }
 *
 *       if (force_success)
 *           return OPENAT_TLS_ERR_NONE;
 *       else
 *           return OPENAT_TLS_ERR_CERT_VALIDATE;
 *   }
 *   </code>
 *****************************************************************************/
typedef
kal_int32 (*tls_cert_verify_callback)(tls_x509_struct* x509, void* arg);



/*****************************************************************************
 * <GROUP Callback Functions>
 *
 * Function
 *   tls_passwd_callback
 * DESCRIPTION
 *   The callback function provided by application to return password for
 *   decrypting the private key file.
 * PARAMETERS
 *   buf      : [OUT] Buffer to return the password.
 *   size     : [IN]  Size of the allocated buffer size when the TLS library
 *                    calls this callback function.
 *   rwflag   : [IN]  The callback is used for reading/decryption (rwflag=0),
 *                    or writing/encryption (rwflag=1).
 *   userdata : [IN]  User-specified pointer to be passed to this callback.
 * RETURNS
 *   Return the actual occupied bytes of the password.
 * SEE ALSO
 *   tls_set_passwd_callback()
 * 
 * EXAMPLE
 *   TLS library calls this callback function as below:
 *   <code>
 *   passwd = malloc(SSL_PASSWORD_BUF_LEN);
 *   passwd_len = ctx->passwd_cb(passwd, SSL_PASSWORD_BUF_LEN, 0,
 *                               ctx->passwd_callback_userdata);
 *   </code>
 *
 *   Application can implement this callback function if the password is
 *   stored in app_passwd:
 *   <code>
 *   int pem_passwd_cb(char *buf, int size, int rwflag, void *password)
 *   {
 *       strncpy(buf, (char *)(app_passwd), size);
 *       buf[size - 1] = '\0';
 *       return(strlen(buf));
 *   }
 *   </code>
 *****************************************************************************/
typedef kal_int32 (*tls_passwd_callback)(kal_char* buf, kal_int32 size,
                                         kal_int32 rwflag, void* userdata);



typedef struct
{
    /* tls_new_ctx */
    ssl_context              *ctx;          /* sec_ssl_ctx_new()/sec_ssl_ctx_free() */
    ctr_drbg_context         *ctr;
    entropy_context          *ent;
	/*+\BUG\wj\2020.2.19\验证SSL通过*/
    x509_crt                *ca;
    x509_crt                *user_ca;
    pk_context              *private_key;
    /*-\BUG\wj\2020.2.19\验证SSL通过*/
    
    kal_uint16               app_str;

    /* context state */
    #define TLS_CTX_INUSE    (0x0001)
    kal_uint16               state; //是否正在使用

    kal_int16              app_mod_id;
    openat_tls_version_enum         version;
    openat_tls_side_enum            side;

    /* tls_set_ciphers */
    int          ciphers[TLS_MAX_CIPHERS]; /*sec_cipher_enum*/
    kal_int32                cipher_num;

    /* tls_set_verify */
    kal_uint32               *root_cert_id;   /* pointer to an array of cert ids end by 0.  //未使用
                                               * tls_malloc()/tls_mfree() */
    kal_char                 ca_path[TLS_MAX_FILENAME_LEN +1];
    tls_cert_verify_callback verify_callback;
    void                     *verify_callback_arg;   /* pointer to this structure */
    
    #define                  CIPHER_LIST        (0x01u << 0)
    #define                  VERIFY_CERTS       (0x01u << 1)
    #define                  VERIFY_CALLBACK    (0x01u << 2)
    #define                  ALERT_CALLBACK     (0x01u << 3)
    #define                  IO_CALLBACK        (0x01u << 4)

    /* raise the flag when each default parameter is set */
    kal_uint32               set_custom;
    kal_uint32               set_default;

    /* tls_set_client_auth */
    ssl_auth_mode_enum       client_auth_modes[TLS_MAX_CLIENT_AUTH];

    /* tls_set_passwd_callback */
    kal_uint8                passwd[TLS_PASSWD_BUF_LEN];  /* random passwd */
    kal_uint32               passwd_len;
    tls_passwd_callback      certman_passwd_callback;
    void*                    certman_passwd_userdata;
    tls_passwd_callback      ssl_passwd_callback;
    void*                    ssl_passwd_userdata;

    /* tls_set_identity */
    //kal_uint32               user_cert_id;
    //kal_char                privkey_file[TLS_MAX_FILENAME_LEN +1];
    //kal_char                user_cert_file[TLS_MAX_FILENAME_LEN +1];
    //tls_filetype_enum        privkey_type;

    /* CERTMAN */
    kal_uint32 root_cert_xid;
    kal_uint32 user_cert_xid;
    kal_uint32 priv_key_xid;

    /* misc */
    /* a socket id associated to this global context */
    kal_uint32               assoc_conn[(MAX_IP_SOCKET_NUM+31) / 32];
    /* a socket id is waiting for notification of HANDSHAKE_READY */
    kal_uint32               hshk_ready_notify[(MAX_IP_SOCKET_NUM+31) / 32];
    kal_bool                 set_ctx_failed;
 
    kal_uint32               wait_cert;  /* ROOT_CERT, PRIV_KEY, USER_CERT */
    openat_tls_socaddr_struct       *faddr[MAX_IP_SOCKET_NUM];
}tls_context_struct;




typedef struct {
    //ssl_conn            *conn_ctx;  /* sec_ssl_new()/sec_ssl_free() */
    
    kal_int8            socket_id;
    openat_tls_side_enum       side;
    kal_int16         app_mod_id;

    tls_context_struct  *ctx;       /* backward pointer to global context */
    tls_state_enum      state; //初始状态或则握手失败状态为：TLS_S_CLOSED，握手成功为TLS_S_HANDSHAKED

    /* auxiliary flags for remembering states */
    #define TLS_AUTO_REHANDSHAKE      (0x01)
    #define TLS_REHANDSHAKING         (0x02)
    #define TLS_HANDSHAKE_REQUESTED   (0x04)
    kal_uint32          flags;  //没用

    #define RCVD_INVALID_CERT     (0x01u << 0)
    #define INVALID_CERT_NOTIFIED (0x01u << 1)
    #define RCVD_CLIENT_AUTH      (0x01u << 2)
    #define CLIENT_AUTH_NOTIFIED  (0x01u << 3)
    #define OCSP_VERIFYING        (0x01u << 4)
    #define OCSP_VERIFIED         (0x01u << 5)
    #define PROCESSING_HANDSHAKE  (RCVD_INVALID_CERT | RCVD_CLIENT_AUTH | OCSP_VERIFYING)

    kal_uint32          cert_state; //暂时未用，值为0 /* handling cert with mmi_certman or certman */

    /* invalid certificate */
    kal_bool            check_cert; //只设置了值，并没有实际使用
#ifdef _DEFENCE_MITM_
    tls_cert_fngrpt_record  *server_cert_fngrpt;
#endif /* _DEFENCE_MITM_ */
    kal_uint8           *peer_cert;       //值为NULL，并未实际使用          /* tls_malloc()/tls_mfree() */
    kal_uint32          peer_cert_len;    //值为NULL，并未实际使用
    kal_uint32          peer_cert_warning; //并未实际使用
    kal_char           *peer_cert_filename;    /* tls_malloc()/tls_mfree() */

#ifdef __OCSP_SUPPORT__
    kal_uint8           ocsp_tarns_id;

    kal_uint8           *peer_cert_issuer;      /* tls_malloc()/tls_mfree() */
    kal_uint32          peer_cert_issuer_len;
#endif /* __OCSP_SUPPORT__ */

    /* client authentication */
    //sec_cert_types      cert_type;      /* len, types[SEC_MAX_CERT_TYPES], in raw format */
    kal_uint8           auth_name_cnt;  //并未实际使用
    //sec_auth_names      auth_names[TLS_MAX_AUTHNAMES]; /* just write them to files */
    kal_char            *certauth_filename;     /* tls_malloc()/tls_mfree() */
	f_openat_tls_notify_indcb tls_notify_indcb;
} tls_conn_context_struct;





typedef struct {
    kal_int16 app_mod_id;
} tls_socket_fw_mod_struct;

extern HANDLE tls_global_lock;

#define TLS_MAX_BIT_SHIFT   (31)

#define ASSOC_CONN_SET(ctx_id, s)    \
    (tls_global_ctx[(ctx_id)].assoc_conn[(s)/32] |= (0x1 << (TLS_MAX_BIT_SHIFT - ((s) % 32))))

#define ASSOC_CONN_CLR(ctx_id, s)    \
    (tls_global_ctx[(ctx_id)].assoc_conn[(s)/32] &= ~(0x1 << (TLS_MAX_BIT_SHIFT - ((s) % 32))))

#define ASSOC_CONN_ISSET(ctx_id, s)    \
    (tls_global_ctx[(ctx_id)].assoc_conn[(s)/32] & (0x1 << (TLS_MAX_BIT_SHIFT - ((s) % 32))))


#define HSHK_READY_NOTIFY_SET(ctx_id, s)    \
    (tls_global_ctx[(ctx_id)].hshk_ready_notify[(s)/32] |= (0x1 << (TLS_MAX_BIT_SHIFT - ((s) % 32))))

#define ASSOC_CONN_SET(ctx_id, s)    \
    (tls_global_ctx[(ctx_id)].assoc_conn[(s)/32] |= (0x1 << (TLS_MAX_BIT_SHIFT - ((s) % 32))))    
    
#define HSHK_READY_NOTIFY_ISSET(ctx_id, s)   \
        (tls_global_ctx[(ctx_id)].hshk_ready_notify[(s)/32] & (0x1 << (TLS_MAX_BIT_SHIFT - ((s) % 32))))
        
#define HSHK_READY_NOTIFY_CLR(ctx_id, s)     \
        (tls_global_ctx[(ctx_id)].hshk_ready_notify[(s)/32] &= ~(0x1 << (TLS_MAX_BIT_SHIFT - ((s) % 32))))

#define TLS_GLOBAL_MUTEX_LOCK                                   \
    do {                                                        \
        OPENAT_wait_semaphore(tls_global_lock,OPENAT_OS_SUSPENDED);                        \
    } while (0)

#define TLS_GLOBAL_MUTEX_UNLOCK                                 \
    do {                                                        \
        OPENAT_release_semaphore(tls_global_lock);                        \
    } while (0)

extern kal_bool tls_ready;

#define TLS_CHECK_READY()                                       \
            do {                                                        \
                if (!tls_ready)                                         \
                {                                                       \
                    OPENAT_print("TLS_TASK_NOT_READY!!!");     \
                    return OPENAT_TLS_ERR_TASK_NOT_READY;                      \
                }                                                       \
            } while (0)


extern void* openat_tls_malloc(kal_uint32 size, void* ref);
extern void openat_tls_mfree(void * ptr, void * ref);


extern kal_int8 tls_parent_ctx_id(kal_int8 s);


#endif /* !_TLS_API_H */


