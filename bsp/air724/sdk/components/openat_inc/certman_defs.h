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
/*****************************************************************************
 *
 * Filename:
 * ---------
 *    certman_struct.h
 *
 * Project:
 * --------
 *    MAUI
 *
 * Description:
 * ------------
 *    Certificate Manager exported structures and constant definitions
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
 * removed!
 * removed!
 * removed!
 *
 * removed!
 * removed!
 * removed!
 * removed!
 *
 *------------------------------------------------------------------------------
 * Upper this line, this part is controlled by PVCS VM. DO NOT MODIFY!! 
 *============================================================================== 
 *******************************************************************************/
#ifndef CERTMAN_DEFS_H
#define CERTMAN_DEFS_H


#ifndef PKI_STRUCT_H
#include "pki_defs.h"
#endif

#ifndef CUSTPACK_CERTS_H
#ifdef AM_TODO_SSL
#include "custpack_certs.h"
#endif
#endif
#ifndef CUSTPACK_JAVA_CERTS_H
#ifdef AM_TODO_SSL
#include "custpack_java_certs.h"
#endif
#endif

//AM add by hanjun.liu @20131219 for CR_MKBug00020850_hanjun.liu start
#ifdef __AM_SSL__
#define CERTMAN_AT_CMD_SUPPORT
#endif
//AM add by hanjun.liu @20131219 for CR_MKBug00020850_hanjun.liu end

/* all string lengths below are number of ASCII characters not including zero-terminate */
#define kal_wchar kal_char

#define CERTMAN_LABEL_LENGTH                PKI_LABEL_LENGTH            /* certificate label name length (ASCII characters not including zero-terminate) */
#define CERTMAN_COMMON_NAME_LENGTH          PKI_NAME_COMMON_NAME_LENGTH /* certificate common name length (ASCII characters not including zero-terminate) */
#define CERTMAN_SERIAL_NUMER_LENGTH         PKI_NAME_SERIAL_NUMER_LENGTH    /* certificate serial number length (ASCII characters not including zero-terminate) */
#define CERTMAN_COUNTRY_LENGTH              PKI_NAME_COUNTRY_LENGTH     /* certificate country name length (ASCII characters not including zero-terminate) */
#define CERTMAN_STATE_LENGTH                PKI_NAME_STATE_LENGTH       /* certificate state name length (ASCII characters not including zero-terminate) */
#define CERTMAN_LOCALITY_LENGTH             PKI_NAME_LOCALITY_LENGTH    /* certificate locality name length (ASCII characters not including zero-terminate) */
#define CERTMAN_ORGANISATION_LENGTH         PKI_NAME_ORGANISATION_LENGTH    /* certificate organization name length (ASCII characters not including zero-terminate) */
#define CERTMAN_ORGANISATION_UNIT_LENGTH    PKI_NAME_ORGANISATION_UNIT_LENGTH   /* certificate organization unit name length (ASCII characters not including zero-terminate) */
#define CERTMAN_TITLE_LENGTH                PKI_NAME_TITLE_LENGTH       /* certificate title name length (ASCII characters not including zero-terminate) */
#define CERTMAN_SURNAME_LENGTH              PKI_NAME_SURNAME_LENGTH     /* certificate surname name length (ASCII characters not including zero-terminate) */
#define CERTMAN_GIVEN_NAME_LENGTH           PKI_NAME_GIVEN_NAME_LENGTH  /* certificate given name length (ASCII characters not including zero-terminate) */  
#define CERTMAN_INITIALS_LENGTH             PKI_NAME_INITIALS_LENGTH    /* certificate initials length (ASCII characters not including zero-terminate) */
#define CERTMAN_DOMAIN_COMPONENT_LENGTH     PKI_NAME_DOMAIN_COMPONENT_LENGTH    /* certificate domain component name length (ASCII characters not including zero-terminate) */    
#define CERTMAN_EMAIL_ADDRESS_LENGTH        PKI_NAME_EMAIL_ADDRESS_LENGTH       /* certificate email address length (ASCII characters not including zero-terminate) */


/* all string sizes below are string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */

#define CERTMAN_LABEL_SIZE                  (CERTMAN_LABEL_LENGTH + 2)              /* certificate label name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define CERTMAN_COMMON_NAME_SIZE            (CERTMAN_COMMON_NAME_LENGTH + 2)        /* certificate common name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */        
#define CERTMAN_SERIAL_NUMBER_SIZE          (CERTMAN_SERIAL_NUMER_LENGTH + 2)       /* certificate serial number string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define CERTMAN_COUNTRY_SIZE                (CERTMAN_COUNTRY_LENGTH + 2)            /* certificate country name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define CERTMAN_STATE_SIZE                  (CERTMAN_STATE_LENGTH + 2)              /* certificate state name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define CERTMAN_LOCALITY_SIZE               (CERTMAN_LOCALITY_LENGTH + 2)           /* certificate locality name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define CERTMAN_ORGANISATION_SIZE           (CERTMAN_ORGANISATION_LENGTH + 2)       /* certificate organization name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define CERTMAN_ORGANISATION_UNIT_SIZE      (CERTMAN_ORGANISATION_UNIT_LENGTH + 2)  /* certificate organization unit name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define CERTMAN_TITLE_SIZE                  (CERTMAN_TITLE_LENGTH + 2)              /* certificate title name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */      
#define CERTMAN_SURNAME_SIZE                (CERTMAN_SURNAME_LENGTH + 2)            /* certificate surname name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define CERTMAN_GIVEN_NAME_SIZE             (CERTMAN_GIVEN_NAME_LENGTH + 2)         /* certificate given name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define CERTMAN_INITIALS_SIZE               (CERTMAN_INITIALS_LENGTH + 2)           /* certificate initials string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define CERTMAN_DOMAIN_COMPONENT_SIZE       (CERTMAN_DOMAIN_COMPONENT_LENGTH + 2)   /* certificate domain component name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define CERTMAN_EMAIL_ADDRESS_SIZE          (CERTMAN_EMAIL_ADDRESS_LENGTH + 2)      /* certificate email address string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */

/* general size constants */

#define CERTMAN_SERIAL_SIZE             20  /* number of bytes in certificate's serial number */
#define CERTMAN_SHA1_SIZE               20  /* SHA-1 hash length (number of bytes) */
#define CERTMAN_NUM_PARSED_CERT         20  /* number of certificates allowed to parse */
#define CERTMAN_NUM_CERT_IN_CHAIN_DISP  10  /* number of certificates in chain for display purpose */
#define CERTMAN_NUM_CERT_IN_CHAIN       CERTMAN_NUM_CERT_IN_CHAIN_DISP  /* number of certificates in chain for display purpose */
#define CERTMAN_NUM_CERT_IN_LIST        12  /* number of certificate list elements per response */
#define CERTMAN_NUM_ID_IN_LIST          20  /* number of IDs listed per response */
#define CERTMAN_NUM_KEYTYPE_IN_LIST     10  /* number of public key types per get certificates by issuers file request */
#define CERTMAN_NUM_CERT_IN_VALIDATE    8  /* max number of certificates in validate request certificate chain */

/* max number of characters of a full filename, not including zero-terminate byte (starting from C:\ to end of file extension) */
#define CERTMAN_FILENAME_LENGTH         260

/* CertMan Root Folder */
#define CERTMAN_ROOT_FOLDER             L"z:\\@certman\\"

/* folder storing all DER encoded Root CA + Intermediate CA + Other User certificates with KeyPurpose=CERTMAN_KP_SERVER_AUTH */
#define CERTMAN_SHARED_CERTS_PATH       (CERTMAN_ROOT_FOLDER L"shared\\")

/* JAVA TCK trusted ca certs folder */
#define CERTMAN_JAVA_TCK_FOLDER         certman_get_java_tck_folder()

/* JAVA TCK trusted ca certs working folder */
#define CERTMAN_JAVA_TCK_VERIFY_PATH   certman_get_java_tck_verify_path()

/* folder storing all Java DER encoded Root CA + Intermediate CA + Other User certificates with KeyPurpose=CERTMAN_KP_SERVER_AUTH */
#define CERTMAN_JAVA_CERTS_PATH         (CERTMAN_ROOT_FOLDER L"java\\") 

/* CertMan temporary folder, cleaned during bootup */
#define CERTMAN_TMP_OUTPUT_FOLDER       (CERTMAN_ROOT_FOLDER L"tmp\\")

/* CertMan pki storage folder */
#define CERTMAN_STORE_INFOFILE_PATH         (L"z:\\@certman\\pki")

/* CertMan certificate and key database information file */
#define CERTMAN_STORE_INFOFILE_NAME         (L"z:\\@certman\\pki\\certinfo.dat")

/* Certman temp private key output folder */
#define CERTMAN_STORE_TP_KEY_PATH           (L"z:\\@certman\\pki\\pk\\")

#define CERTMAN_STORE_CLIENT_AUTH_NAME       (L"z:\\@certman\\client_auth.txt")

/* Certman certificate ID start number in database */
#define CERTMAN_ID_START	1000

/* max user input password length ASCII characters, not including zero-terminate byte */
#define CERTMAN_PASSWORD_LENGTH     32

/* max user input password ASCII string buffer size, including zero-terminate byte */
#define CERTMAN_PASSWORD_SIZE       (CERTMAN_PASSWORD_LENGTH+1)

/* max private key file password length (not NULL-terminated) */
#define CERTMAN_PKPWD_SIZE          60

/* This enum defines the certman errors */
typedef enum
{
    CERTMAN_ERR_NONE = PKI_ERR_NONE,                        /* 0 (pki wrapper error enum) */
    CERTMAN_ERR_FAIL = PKI_ERR_FAIL,                        /* 1 (pki wrapper error enum) */
    CERTMAN_ERR_MEMFULL = PKI_ERR_MEMFULL,                  /* 2 (pki wrapper error enum) */
    CERTMAN_ERR_INVALID_CONTEXT = PKI_ERR_INVALID_CONTEXT,  /* 3 (pki wrapper error enum) */
    CERTMAN_ERR_OUT_OF_RANGE = PKI_ERR_OUT_OF_RANGE,        /* 4 (pki wrapper error enum) */
    CERTMAN_ERR_INCORRECT_PASSWORD = PKI_ERR_INCORRECT_PASSWORD,    /* 5 (pki wrapper error enum) */
    CERTMAN_ERR_FS_ERROR = PKI_ERR_FS_ERROR,                /* 6 (pki wrapper error enum) */
    CERTMAN_ERR_NEED_PASSWORD = PKI_ERR_NEED_PASSWORD,      /* 7 (pki wrapper error enum) */
    CERTMAN_ERR_INVALID_INPUT = PKI_ERR_INVALID_INPUT,      /* 8 (pki wrapper error enum) */
    CERTMAN_ERR_EXT_NOT_FOUND = PKI_ERR_EXT_NOT_FOUND,      /* 9 (pki wrapper error enum) */
    CERTMAN_ERR_ISSUER_UID_NOT_FOUND = PKI_ERR_ISSUER_UID_NOT_FOUND,    /* 10 (pki wrapper error enum) */
    CERTMAN_ERR_SUBJECT_UID_NOT_FOUND = PKI_ERR_SUBJECT_UID_NOT_FOUND,  /* 11 (pki wrapper error enum) */
    CERTMAN_ERR_UNSUPPORTED_CONTENT = PKI_ERR_UNSUPPORTED_CONTENT,      /* 12 (pki wrapper error enum) */
    CERTMAN_ERR_CERT_NOT_FOUND = PKI_ERR_CERT_NOT_FOUND,    /* 13 (pki wrapper error enum) */
    CERTMAN_ERR_CORRUPTED_DATA = PKI_ERR_CORRUPTED_DATA,    /* 14 (pki wrapper error enum) */
    CERTMAN_ERR_EXCEED_MAX_DATA_SIZE = PKI_ERR_EXCEED_MAX_DATA_SIZE,    /* 15 (pki wrapper error enum) */
    CERTMAN_ERR_NOT_SUPPORTED_OP = PKI_ERR_NOT_SUPPORTED_OP,            /* 16 (pki wrapper error enum) */    
    CERTMAN_ERR_FIRST_BOOTUP,               /* 17, First bootup operation for preinstall certs */
    CERTMAN_ERR_KEY_NOT_FOUND,              /* 18, Key not found in certman database */
    CERTMAN_ERR_ISSUER_NOT_FOUND,           /* 19, Issuer name can't be found in provided issuer names file */
    CERTMAN_ERR_ID_ALREADY_EXISTS,          /* 20, The specified certificate ID already exists */
    CERTMAN_ERR_FILE_NOT_FOUND,             /* 21, File not found error */
    CERTMAN_ERR_DISK_FULL,                  /* 22, Disk full error */
    CERTMAN_ERR_FILE_CORRUPTED,             /* 23, The file content is corrupted or not supported */
    CERTMAN_ERR_INVALID_LABEL,              /* 24, Label string invalid */
    CERTMAN_ERR_INVALID_CERT_GROUP,         /* 25, specified certificate group invalid */
    CERTMAN_ERR_INVALID_KEY_PURPOSE,        /* 26, specified key purpose invalid */
    CERTMAN_ERR_INVALID_KEY_TYPE,           /* 27, specified key type invalid */
    CERTMAN_ERR_INVALID_DOMAIN,             /* 28, specified certificate domain invalid */
    CERTMAN_ERR_INVALID_FILENAME,           /* 29, specified filename parameter invalid */
    CERTMAN_ERR_INVALID_DATA,               /* 30, specified data or data length parameter invalid */
    CERTMAN_ERR_INVALID_ENCODING,           /* 31, specified data encoding type invalid */
    CERTMAN_ERR_INVALID_JOB,                /* 32, specified job ID invalid in parsing and import process */
    CERTMAN_ERR_INVALID_CERT_ID,            /* 33, specified Certificate ID is invalid */
    CERTMAN_ERR_INVALID_PASSWORD,           /* 34, specified password parameters invalid */
    CERTMAN_ERR_INVALID_PATH,               /* 35, specified path parameter invalid */
    CERTMAN_ERR_INVALID_VALIDATION_PARAM,   /* 36, specified validation parameters invalid */
    CERTMAN_ERR_NO_PWD_CALLBACK,            /* 37, No specified password callback function for certman */
    CERTMAN_ERR_LABEL_EXISTS,               /* 38, label duplicated error */
    CERTMAN_ERR_CERT_EXISTS,                /* 39, specified certificate had been imported before */
    CERTMAN_ERR_KEY_PURPOSE_DENIED,         /* 40, key purpose denied for specified operation */
    CERTMAN_ERR_ACCESS_DENIED,              /* 41, key usage request denied */
    CERTMAN_ERR_READ_ONLY,                  /* 42, the certificate is read_only one */
    CERTMAN_ERR_CERT_IN_USE,                /* 43, the certificate is inuse */
    CERTMAN_ERR_CHAIN_NOT_ALLOWED,          /* 44, certificate chain validation failed */
    CERTMAN_ERR_CHAIN_TOO_LARGE,            /* 45, certificate chain length exceeds CERTMAN_NUM_CERT_IN_CHAIN_DISP */
    CERTMAN_ERR_TOO_MANY_CERTS,             /* 46, too many certificates in validate request cert chain array */
    CERTMAN_ERR_CERT_EXPIRED,               /* 47, certificate was expired before */
    CERTMAN_ERR_NO_TRUSTED_CERT_FOUND,      /* 48, no trusted certificate found in passed certificate chain */
    CERTMAN_ERR_CONVERT_FAIL,               /* 49, database information file encode/decode error */
    CERTMAN_ERR_FILE_TOO_LARGE,             /* 50, the input text file is too large to parse */
    CERTMAN_ERR_WOULDBLOCK,                 /* 51, the operation cannot finish immediately */
    CERTMAN_ERR_RETRY,                      /* 52, request timeout, retry again */
    CERTMAN_ERR_NO_RESPONSE,                /* 53, no OCSP response from server */
    CERTMAN_ERR_TOTAL
} certman_error_enum;

/* This enum defines the certman certificate type */
typedef enum
{
    CERTMAN_CERTTYPE_X509,          /* x509 certificate type */
    CERTMAN_CERTTYPE_JAVA_X509,     /* x509 java certificate type (certman internal use for java certificates filter) */
    CERTMAN_CERTTYPE_JAVA_TCK,      /* JAVA TCK Cert (certman internal use for java TCK certificates filter) */    
    CERTMAN_CERTTYPE_GADGET         /* Gadget Cert (certman internal use for java TCK certificates filter) */            
} certman_certtype_enum;

/* This enum defines the certman certificate storage location */
typedef enum
{
    CERTMAN_STORAGE_PHONE,          /* certman certificate storage location setting is phone */
    CERTMAN_STORAGE_SIM             /* certman certificate storage location setting is SIM card (not support now) */
} certman_storage_enum;

/* This enum defines the certman encoding type */
typedef enum
{
    CERTMAN_ENC_UNSUPPORTED = 0x00, /* identify the content format isn't supported */
    CERTMAN_ENC_DER = 0x01,     /* single DER encoded X.509 certificate */
    CERTMAN_ENC_PEM = 0x02,     /* Base64 encoded list of X.509 certificates wrapped within multiple PEM begin/end header */
    CERTMAN_ENC_PK7 = 0x04,     /* DER/PEM encoded PKCS #7 file (list of certificates) */
    CERTMAN_ENC_PK12 = 0x08,    /* DER/PEM encoded PKCS #12 file (1 private key + 1 or more certificates OR 1 or more certificates) */
    CERTMAN_ENC_PEM_USER_CERT = 0x10     /* PEM encoded client cert file (1 private key + multiple certificates) */
} certman_encoding_enum;

/* This enum defines the certman private key protection settings */
typedef enum
{
    CERTMAN_PROTECT_NONE,           /* no specified protection setting */
    CERTMAN_PROTECT_USAGE_CONFIRM,  /* confirm protection */
    CERTMAN_PROTECT_USAGE_PASSWORD  /* password protection */
} certman_privkey_protection_enum;

/* This enum defines the certman parsed certificate groups */
typedef enum
{
    CERTMAN_PARSED_CERTGRP_ALL,         /* identify total numbers of certificates in parseing file */
    CERTMAN_PARSED_CERTGRP_ROOTCA,      /* identify total numbers of root ca certificates in parseing file */
    CERTMAN_PARSED_CERTGRP_OTHERCA,     /* identify total numbers of intermediately ca certificates in parseing file */
    CERTMAN_PARSED_CERTGRP_OTHERUSER,   /* identify total numbers of other user certificates in parseing file */
    CERTMAN_PARSED_CERTGRP_PERSONAL,    /* identify total numbers of personal certificates in parseing file */
    CERTMAN_PARSED_CERTGRP_SIZE
} certman_parsed_cert_group_enum;

/* This enum defines the certman certificate group filter settings */
typedef enum
{
    CERTMAN_CERTGRP_NONE = PKI_CERTGRP_NONE,            /* no specified certificate group filter */
    CERTMAN_CERTGRP_ROOTCA = PKI_CERTGRP_ROOTCA,        /* specified certificate group filter for root ca (issuer = subject) */
    CERTMAN_CERTGRP_CA = PKI_CERTGRP_CA,                /* specified certificate group filter for intermediately ca (ver 3 cert with BasicConstraint: CA=TRUE) */
    CERTMAN_CERTGRP_OTHERUSER = PKI_CERTGRP_OTHERUSER,  /* specified certificate group filter for other end-entity certificate (ver 3 cert with BasicConstraint: CA=FALSE) OR 
                                                           ver 1 cert with no private key associated */
    CERTMAN_CERTGRP_PERSONAL = PKI_CERTGRP_PERSONAL,    /* specified certificate group filter for personal certificate(associated with a private key (regardless of whether it's a CA cert)) */
    CERTMAN_CERTGRP_ANY = PKI_CERTGRP_ANY               /* filter group for all certs */
} certman_cert_group_enum;

/* This enum defines the certman domain settings */
typedef enum
{
    CERTMAN_DOMAIN_NONE = PKI_DOMAIN_NONE,                  /* no specified filter domain */
    CERTMAN_DOMAIN_UNTRUSTED = PKI_DOMAIN_UNTRUSTED,        /* certs' with no specified domain, filter for untrusted domain certs */
    CERTMAN_DOMAIN_OPERATOR = PKI_DOMAIN_OPERATOR,          /* Operator installed certs, filter for operator domain certs */
    CERTMAN_DOMAIN_MANUFACTURER = PKI_DOMAIN_MANUFACTURER,  /* Manufacturer installed certs, filter for Manufacturer domain certs */
    CERTMAN_DOMAIN_THIRD_PARTY = PKI_DOMAIN_THIRD_PARTY,    /* Third party certs, filter for third party domain certs */
    CERTMAN_DOMAIN_ANY = PKI_DOMAIN_ANY                     /* filter domain for all certs */
} certman_domain_enum;

/* This enum defines the certman public key types */
typedef enum
{
    CERTMAN_PUBKEY_RSA = PKI_PUBKEY_RSA,            /* RSA  = 0x01 */
    CERTMAN_PUBKEY_DSA = PKI_PUBKEY_DSA,            /* DSA  = 0x02 */
    CERTMAN_PUBKEY_DH_ANSI = PKI_PUBKEY_DH_ANSI,    /* DH   = 0x04 */
    CERTMAN_PUBKEY_DH_PKCS3 = PKI_PUBKEY_DH_PKCS3,  /* PKCS3= 0x08 */
    CERTMAN_PUBKEY_EC = PKI_PUBKEY_EC,              /* EC   = 0x10 */
    CERTMAN_PUBKEY_TOTAL = PKI_PUBKEY_TOTAL         /* ALL  = 0xFF */
} certman_pubkey_type_enum;

/* This enum defines the certman name types ("common name" will always be the first name type in the nametype enum, must not be shifted as lots of codes have dependency on this for traversing through name array) */
typedef enum {
    CERTMAN_NAMETYPE_COMMON_NAME = PKI_NAMETYPE_COMMON_NAME,            /* common name */
    CERTMAN_NAMETYPE_SERIAL_NUMBER = PKI_NAMETYPE_SERIAL_NUMBER,        /* serial */        
    CERTMAN_NAMETYPE_COUNTRY = PKI_NAMETYPE_COUNTRY,                    /* country name */                    
    CERTMAN_NAMETYPE_STATE = PKI_NAMETYPE_STATE,                        /* state name */
    CERTMAN_NAMETYPE_LOCALITY = PKI_NAMETYPE_LOCALITY,                  /* locality */
    CERTMAN_NAMETYPE_ORGANISATION = PKI_NAMETYPE_ORGANISATION,          /* organization name */
    CERTMAN_NAMETYPE_ORGANISATION_UNIT = PKI_NAMETYPE_ORGANISATION_UNIT,/* organization unit name */
    CERTMAN_NAMETYPE_TITLE = PKI_NAMETYPE_TITLE,                        /* title */
    CERTMAN_NAMETYPE_SURNAME = PKI_NAMETYPE_SURNAME,                    /* surname */
    CERTMAN_NAMETYPE_GIVEN_NAME = PKI_NAMETYPE_GIVEN_NAME,              /* given name */
    CERTMAN_NAMETYPE_INITIALS = PKI_NAMETYPE_INITIALS,                  /* initials */
    CERTMAN_NAMETYPE_DOMAIN_COMPONENT = PKI_NAMETYPE_DOMAIN_COMPONENT,  /* domain component name */
    CERTMAN_NAMETYPE_EMAIL_ADDRESS = PKI_NAMETYPE_EMAIL_ADDRESS,        /* email address */
    CERTMAN_NAMETYPE_SIZE
} certman_name_type_enum;

/* This enum defines the certman DCS */
typedef enum
{
    CERTMAN_DCS_ASCII = PKI_DCS_ASCII,  /* ASCII encoding string */
    CERTMAN_DCS_UCS2 = PKI_DCS_UCS2     /* UCS2 encoding string */
} certman_dcs_enum;

/* This enum defines the certman certificate property settings (not used now) */
typedef enum
{
    CERTMAN_PROP_NONE = 0x00,                  /* no specified property */
    CERTMAN_PROP_READ_ONLY = 0x01,             /* read only certificate */
    CERTMAN_PROP_ALLOWED_KEY_EXPORT = 0x02,    /* only applicable to personal certificate */
    CERTMAN_PROP_EXPIRED = 0x04                /* when certificate has expired */
} certman_property_enum;

/* This enum defines the certman extension key usage extension settings in X509 spec */
typedef enum
{
    CERTMAN_KP_NONE = PKI_EXTKEYUSAGE_NONE,                         /* No specified extension key usage */
    CERTMAN_KP_SERVER_AUTH = PKI_EXTKEYUSAGE_SERVER_AUTH,           /* extension key usage : server authentication assert */
    CERTMAN_KP_CLIENT_AUTH = PKI_EXTKEYUSAGE_CLIENT_AUTH,           /* extension key usage : client authentication assert */
    CERTMAN_KP_CODE_SIGNING = PKI_EXTKEYUSAGE_CODE_SIGNING,         /* extension key usage : code signing assert */
    CERTMAN_KP_EMAIL_PROTECTION = PKI_EXTKEYUSAGE_EMAIL_PROTECTION, /* extension key usage : email protection assert */
    CERTMAN_KP_IPSEC_ENDSYSTEM = PKI_EXTKEYUSAGE_IPSEC_ENDSYSTEM,   /* extension key usage : IPSec end system assert */
    CERTMAN_KP_IPSEC_TUNNEL = PKI_EXTKEYUSAGE_IPSEC_TUNNEL,         /* extension key usage : IPSec tunneling assert */
    CERTMAN_KP_IPSEC_USER = PKI_EXTKEYUSAGE_IPSEC_USER,             /* extension key usage : IPSec user assert */
    CERTMAN_KP_TIME_STAMPING = PKI_EXTKEYUSAGE_TIME_STAMPING,       /* extension key usage : Time stamp assert */
    CERTMAN_KP_OCSP_SIGNING = PKI_EXTKEYUSAGE_OCSP_SIGNING,         /* extension key usage : OCSP signing assert */
    CERTMAN_KP_ALL = PKI_EXTKEYUSAGE_ALL
} certman_keypurpose_enum;

/* This enum defines the certman password authorization stages */
typedef enum
{
    CERTMAN_PWDAUTH_FIRST,              /* first time password access request */
    CERTMAN_PWDAUTH_FAILED_RETRY_AGAIN, /* retry for password error */
    CERTMAN_PWDAUTH_FAILED_ABORT,       /* last trial failed */
    CERTMAN_PWDAUTH_SUCCEEDED           /* password verify success */
} certman_pwdauth_stage_enum;

/* This enum defines the certman siganture algorithms */
typedef enum
{
    CERTMAN_SIGNALG_ECDSA_SHA1 = PKI_SIGNALG_ECDSA_SHA1,            /* ECDSA + SHA1 */
    CERTMAN_SIGNALG_ECDSA_SHA224 = PKI_SIGNALG_ECDSA_SHA224,        /* ECDSA + SHA1-224 bits digest */
    CERTMAN_SIGNALG_ECDSA_SHA256 = PKI_SIGNALG_ECDSA_SHA256,        /* ECDSA + SHA1-256 bits digest */
    CERTMAN_SIGNALG_ECDSA_SHA384 = PKI_SIGNALG_ECDSA_SHA384,        /* ECDSA + SHA1-384 bits digest */
    CERTMAN_SIGNALG_ECDSA_SHA512 = PKI_SIGNALG_ECDSA_SHA512,        /* ECDSA + SHA1-512 bits digest */
    CERTMAN_SIGNALG_DSA_SHA1 = PKI_SIGNALG_DSA_SHA1,                /* DSA + SHA1 */
    CERTMAN_SIGNALG_RSA_SHA1 = PKI_SIGNALG_RSA_SHA1,                /* RSA + SHA1 */
    CERTMAN_SIGNALG_RSA_MD4 = PKI_SIGNALG_RSA_MD4,                  /* RSA + MD4 */
    CERTMAN_SIGNALG_RSA_MD5 = PKI_SIGNALG_RSA_MD5,                  /* RSA + MD5 */
    CERTMAN_SIGNALG_RSA_MD2 = PKI_SIGNALG_RSA_MD2,                  /* RSA + MD2 */
    CERTMAN_SIGNALG_RSA_SHA256 = PKI_SIGNALG_RSA_SHA256,            /* RSA + SHA1-256 bits digest */
    CERTMAN_SIGNALG_RSA_SHA384 = PKI_SIGNALG_RSA_SHA384,            /* RSA + SHA1-384 bits digest */
    CERTMAN_SIGNALG_RSA_SHA512 = PKI_SIGNALG_RSA_SHA512,            /* RSA + SHA1-512 bits digest */
    CERTMAN_SIGNALG_RSA_PSS_SHA1 = PKI_SIGNALG_RSA_PSS_SHA1,        /* RSA-PSS + SHA1 */
    CERTMAN_SIGNALG_RSA_PSS_SHA224 = PKI_SIGNALG_RSA_PSS_SHA224,    /* RSA-PSS + SHA1-224 bits digest */
    CERTMAN_SIGNALG_RSA_PSS_SHA256 = PKI_SIGNALG_RSA_PSS_SHA256,    /* RSA-PSS + SHA1-256 bits digest */
    CERTMAN_SIGNALG_RSA_PSS_SHA384 = PKI_SIGNALG_RSA_PSS_SHA384,    /* RSA-PSS + SHA1-384 bits digest */
    CERTMAN_SIGNALG_RSA_PSS_SHA512 = PKI_SIGNALG_RSA_PSS_SHA512,    /* RSA-PSS + SHA1-512 bits digest */
    CERTMAN_SIGNALG_TOTAL
} certman_signature_alg;

/* This enum defines the certman certificate chain source type in validation service request */
typedef enum
{
    CERTMAN_VALSOURCE_ARRAY = 0   /* default, does not check dependencies of certificates from input cert array */
} certman_valsource_enum;

/* This enum defines the certman validation purpose type */
typedef enum
{
    CERTMAN_VALTYPE_TRUSTED_ISSUER = 0,     /* returns the first trusted cert which could be used to verify the requested cert(s) */
    CERTMAN_VALTYPE_CANCEL                  /* abort the validation process */
} certman_valtype_enum;


typedef enum {
    CERTMAN_OCSP_OPT_USE_OCSP    = 0x01 << 0, /* kal_bool, Enable OCSP validation */
    CERTMAN_OCSP_OPT_MUST_PASS   = 0x01 << 1, /* kal_bool, Must pass OCSP validation */
    CERTMAN_OCSP_OPT_RESPONDER   = 0x01 << 2, /* kal_char*, user specific responder URL */
    CERTMAN_OCSP_OPT_NETWORK     = 0x01 << 3, /* certman_ocsp_network_profile_struct, user specific network parameters */
    CERTMAN_OCSP_OPT_RETRY_TIMER = 0x01 << 4  /* kal_uint32, user specific retry timer in seconds */
} certman_ocsp_opt_enum;

#ifdef __CERTMAN_SUPPORT__
	#define CERTMAN_AT_CMD
  #define _SUPPORT_CLIENT_AUTH_
#endif

#define CERTMAN_USER_CERT_IMPORT_STATUS 	1 << 1
#define CERTMAN_USER_CERT_KEY_EXPORT_STATUS 1 << 2
#define CERTMAN_USER_CERT_IMPORT_ERROR 		1 << 3
#define CERTMAN_USER_CERT_KEY_ERROR 		1 << 4





//typedef enum
//{
 //   CERTMAN_CERT_IMPORT_STATUS = 1,
//	CERTMAN_CERT_KEY_EXPORT_STATUS =2,
//	CERTMAN_CERT_NONE
//} certman_user_cert_status_enum;


typedef enum
{
    CERTMAN_CERT_STATUS_INSTALLED,
	CERTMAN_CERT_STATUS_NOT_FOUND
} certman_user_cert_status_enum;

typedef enum
{
    CERTMAN_CERT_STATUS_SUCCESS,
	CERTMAN_CERT_STATUS_FAILURE
} certman_user_cert_op_status_enum;


typedef enum
{
    CERTMAN_USER_OP_CERT_IMPORT,
	CERTMAN_USER_OP_KEY_EXPORT
} certman_user_cert_op_enum;

#define TEMP_USER_CERT_FILE L"z:\\temp_user_cert_file.der"
#define TMP_USER_CERT_FILENAME_LEN 30

//#endif

#endif  /* CERTMAN_DEFS_H */
