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
#ifndef _AM_OPENAT_TLS_H_
#define _AM_OPENAT_TLS_H_

#define TLS_MAX_SOCK_ADDR_LEN 28

typedef enum tls_soctype_enum_s                              /* soc type */
{
    OPENAT_TLS_SOC_SOCK_TCP = 0,                            /* stream socket, TCP */
    OPENAT_TLS_SOC_SOCK_UDP,                                /* datagram socket, UDP   */
    OPENAT_TLS_SOC_SOCK_RAW,                                /* raw socket             */
    OPENAT_TLS_SOC_SOCK_NOSUPPORT          
}openat_tls_soctype_enum;

struct tls_socaddr_struct_s                          /* soc address struct */
{
    openat_tls_soctype_enum    sock_type;                      /* socket type                               */
    s16                 addr_len;                       /* address length                            */
    u16                 port;                           /* port number                               */
    u8                  addr[TLS_MAX_SOCK_ADDR_LEN]; /* IP address. For keep the 4-type boundary, */
};

#define MAX_SET_RANDBYTES 32
#define MAX_SET_PREMASTER 48
typedef struct
{
    int32   *ciphersuite;
    u8   ignore_local_time;//0: care about tiem check for certification; 1:ignore tiem check for certification
    u8   randbytes[MAX_SET_RANDBYTES*2+1]; //随机数为32字节
    u8   premaster[MAX_SET_PREMASTER*2+1]; //premaster为48字节
    char *caPath;
    u8 ssl_version;
	/*+\NEW\WJ\2019.1.28\添加认证方式*/
    u8 verify_mode; //0：根证书认证 1：其他证书认证
	/*-\NEW\WJ\2019.1.28\添加认证方式*/
}openat_tls_ssl_cfg;

typedef struct tls_socaddr_struct_s  openat_tls_socaddr_struct;

#define sockaddr_struct openat_tls_socaddr_struct



/***************************************************************************
 * <GROUP Enums>
 *
 * SSL versions.
 * Ref. tls_new_ctx().
 ***************************************************************************/
typedef enum {
    OPENAT_TLS_ALL_VERSIONS = 0, /* ALL supported SSL/TLS versions */
    OPENAT_SSLv2 = 0x01u << 0,   /* SSLv2 */
    OPENAT_SSLv3 = 0x01u << 1,   /* SSLv3 */
    OPENAT_TLSv1 = 0x01u << 2,   /* TLSv1 */
    OPENAT_TLS_UNKNOWN_VERSION = 0xffu /* Unknown */
}openat_tls_version_enum;


/***************************************************************************
 * <GROUP Enums>
 *
 * SSL side.
 * Ref. tls_new_ctx().
 ***************************************************************************/
typedef enum {
    OPENAT_TLS_CLIENT_SIDE = 0, /* Client side */
    OPENAT_TLS_SERVER_SIDE = 1  /* Server side */
} openat_tls_side_enum;


/***************************************************************************
 * <GROUP Enums>
 *
 * TLS events.
 * Ref. app_tls_notify_ind_struct.
 ***************************************************************************/
typedef enum {
    OPENAT_TLS_HANDSHAKE_READY    = 0x01u << 0, /* The connection is ready for performing handshake. */
    OPENAT_TLS_HANDSHAKE_DONE     = 0x01u << 1, /* Handshake procedure is finished, success or failure. */
    OPENAT_TLS_HANDSHAKING        = (0x01u << 1) + 1, 
    OPENAT_TLS_READ               = 0x01u << 2, /* There is data for reading. */
    OPENAT_TLS_WRITE              = 0x01u << 3, /* There is buffer for writing. */
    OPENAT_TLS_CLOSE              = 0x01u << 4  /* The SSL connection is closed. */
} openat_tls_event_enum;



/***************************************************************************
 * <GROUP Enums>
 *
 * Error codes of TLS operations.
 ***************************************************************************/
typedef enum {
    OPENAT_TLS_ERR_NONE                   = 0,   /* No error. */
    OPENAT_TLS_ERR_WOULDBLOCK             = -1,  /* Operation cannot complete now. */
    OPENAT_TLS_ERR_NO_FREE_CTX            = -2,  /* No free global context slots. */
    OPENAT_TLS_ERR_NO_MEMORY              = -3,  /* Allocate memory failed. */
    OPENAT_TLS_ERR_INVALID_CONTEXT        = -4,  /* Invalid global context id. */
    OPENAT_TLS_ERR_INVALID_CIPHER         = -5,  /* Invalid cipher enum value. */
    OPENAT_TLS_ERR_EXCESS_MAX_CIPHERS     = -6,  /* Too many ciphers. */
    OPENAT_TLS_ERR_INVALID_PARAMS         = -7,  /* Invalid parameter. */
    OPENAT_TLS_ERR_INVALID_ROOT_CERT      = -8,  /* Invalid root certificate id. */
    OPENAT_TLS_ERR_INVALID_PRIV_KEY       = -9,  /* Invalid private key id. */
    OPENAT_TLS_ERR_INVALID_PERSONAL_CERT  = -10, /* Invalid personal certificate id. */
    OPENAT_TLS_ERR_INVALID_FILE_TYPE      = -11, /* Invalid file encoding type. */
    OPENAT_TLS_ERR_INVALID_AUTH_MODE      = -12, /* Invalid client auth mode. */
    OPENAT_TLS_ERR_EXCESS_MAX_AUTH_MODES  = -13, /* Too many client auth modes. */
    OPENAT_TLS_ERR_ALREADY                = -14, /* The operation is progressing. */
    OPENAT_TLS_ERR_HANDSHAKED             = -15, /* Handshaked completed. */
    OPENAT_TLS_ERR_INVALID_SOCK_ID        = -16, /* Invalid socket id. */
    OPENAT_TLS_ERR_NO_CONN_CTX            = -17, /* No associated connection context. */
    OPENAT_TLS_ERR_HANDSHAKING            = -18, /* Opreation denied when connection is handshaking. */
    OPENAT_TLS_ERR_REHANDSHAKING          = -19, /* Connection is rehandshaking. */
    OPENAT_TLS_ERR_REHANDSHAKED           = -20, /* TLS auto re-handshaked completed. */
    OPENAT_TLS_ERR_SHUTDOWNED             = -21, /* Opreation denied when connection is shutdowned. */
    OPENAT_TLS_ERR_REQ_HANDSHAKE          = -22, /* TLS peer requested handshake. */
    OPENAT_TLS_ERR_NEED_HANDSHAKE         = -23, /* Need handshake first. */
    OPENAT_TLS_ERR_REHANDSHAKE_REJ        = -24, /* Peer rejects our renegotiation, connection still valid. */
    OPENAT_TLS_ERR_CONN_CLOSED            = -25, /* Connection closed by peer. */
    OPENAT_TLS_ERR_IO_ERROR               = -26, /* Lower-layer IO error. */
    OPENAT_TLS_ERR_OP_DENIED              = -27, /* Operation denied due to incorrect state. */
    OPENAT_TLS_ERR_READ_REQUIRED          = -28, /* Application data need to be read before processing rehandshake. */
    OPENAT_TLS_ERR_CERT_VALIDATE          = -29, /* Certificate validation failed. */
    OPENAT_TLS_ERR_PRNG_FAIL              = -30, /* Set PRNG failed. */
    OPENAT_TLS_ERR_WAITING_CERT           = -32, /* Waiting certificate confirm from CERTMAN. */
    OPENAT_TLS_ERR_FILESYS                = -33, /* File system operation failed. */
    OPENAT_TLS_ERR_TASK_NOT_READY         = -34, /* TLS task not ready, waiting for CERTMAN confirm message. */
    OPENAT_TLS_ERR_SSL_INTERNAL           = -100,/* SSL layer internal error. */
    OPENAT_TLS_ERR_SOC_INTERNAL           = -101,/* Socket layer internal error. */
    OPENAT_TLS_ERR_CERTMAN_INTERNAL       = -102 /* Certman internal error. */
} openat_tls_error_enum;

typedef void (*f_openat_tls_notify_indcb)(kal_uint16 mod,
                                 kal_int8 s,
                                 openat_tls_event_enum event,
                                 kal_bool result,
                                 kal_int32 error,
                                 kal_int32 detail_cause);


kal_char* openat_tls_get_ca_path(void);
void openat_tls_set_ca_path(kal_char* fileName);
kal_bool openat_tlsLoadCert_ext(const kal_char* fileName);
void* openat_tls_malloc(kal_uint32 size, void* ref);
void openat_tls_mfree(void* ptr, void* ref);
kal_int8 openat_tls_parent_ctx_id(kal_int8 s);
kal_int32 openat_tls_get_ctx_slot(void);
void openat_tls_free_ctx_slot(kal_uint8 id);
kal_int32 openat_tls_validate_ctx(kal_uint8 ctx_id);
void openat_tls_init_ctx(kal_uint8 ctx_id,
                  kal_uint16 mod_id,
                  openat_tls_version_enum ver,
                  openat_tls_side_enum side,
                  kal_uint16 app_str_id);

kal_int32 openat_tls_set_default_io_callback(kal_uint8 ctx_id);
void openat_tls_common_delete_conn(kal_int8 s);
void openat_tls_delete_assoc_conn(kal_uint8 ctx_id);
kal_int32 openat_tls_rw_result_check(kal_int32 result, kal_int8 ctx_id);
kal_int32 openat_tls_new_ctx(openat_tls_version_enum ver, openat_tls_side_enum side,
            kal_uint16 mod_id, kal_uint16 app_str_id);
//kal_int32 openat_tls_set_ciphers(kal_uint8 ctx_id,
//                const tls_cipher_enum ciphers[], const kal_int32 num);
kal_int32 openat_tls_new_conn(kal_uint8 ctx_id, kal_int8 sock_id, openat_tls_socaddr_struct *faddr,f_openat_tls_notify_indcb cb);
kal_int32 openat_tls_delete_conn(kal_int8 sock_id);
kal_int32 openat_tls_delete_ctx(kal_uint8 ctx_id);
kal_int32 openat_tls_check_invalid_cert(kal_int8 sock_id, kal_bool onoff, const kal_char* ca_file,kal_bool byfile);
kal_int32 openat_tls_set_client_auth(kal_uint8 ctx_id,
                    const kal_char* client_ca_path, const kal_char* client_key_path, const kal_char* password,kal_bool byfile);
kal_int32 openat_tls_set_null_client_auth(kal_uint8 ctx_id);
kal_int32 openat_tls_set_hostname(kal_uint8 ctx_id, const kal_char* hostname);
kal_int32 openat_tls_set_identity(kal_uint8 ctx_id, kal_uint32 cert_id);



#endif /* !_TLS_API_H */


