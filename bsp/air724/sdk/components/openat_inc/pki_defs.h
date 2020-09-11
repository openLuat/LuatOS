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
 *    pki_defs.h
 *
 * Project:
 * --------
 *    MAUI
 *
 * Description:
 * ------------
 *    PKI exported services
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
 * removed!
 * removed!
 *
 *------------------------------------------------------------------------------
 * Upper this line, this part is controlled by PVCS VM. DO NOT MODIFY!! 
 *============================================================================== 
 *******************************************************************************/
#ifndef PKI_DEFS_H
#define PKI_DEFS_H

/* Define SHA1 SIZE constant for PKI wrapper user */
#define PKI_SHA1_SIZE 20

/* all string lengths below are number of 
 * ASCII characters not including zero-terminate */

#define PKI_LABEL_LENGTH                    64  /* certificate label name length (ASCII characters not including zero-terminate) */
#define PKI_NAME_COMMON_NAME_LENGTH         64  /* certificate common name length (ASCII characters not including zero-terminate) */
#define PKI_NAME_SERIAL_NUMER_LENGTH        64  /* certificate serial number length (ASCII characters not including zero-terminate) */
#define PKI_NAME_COUNTRY_LENGTH             2   /* certificate country name length (ASCII characters not including zero-terminate) */
#define PKI_NAME_STATE_LENGTH               128 /* certificate state name length (ASCII characters not including zero-terminate) */
#define PKI_NAME_LOCALITY_LENGTH            128 /* certificate locality name length (ASCII characters not including zero-terminate) */
#define PKI_NAME_ORGANISATION_LENGTH        64  /* certificate organization name length (ASCII characters not including zero-terminate) */
#define PKI_NAME_ORGANISATION_UNIT_LENGTH   64  /* certificate organization unit name length (ASCII characters not including zero-terminate) */
#define PKI_NAME_TITLE_LENGTH               64  /* certificate title name length (ASCII characters not including zero-terminate) */
#define PKI_NAME_SURNAME_LENGTH             40  /* certificate surname name length (ASCII characters not including zero-terminate) */
#define PKI_NAME_GIVEN_NAME_LENGTH          16  /* certificate given name length (ASCII characters not including zero-terminate) */
#define PKI_NAME_INITIALS_LENGTH            5   /* certificate initials length (ASCII characters not including zero-terminate) */
#define PKI_NAME_DOMAIN_COMPONENT_LENGTH    128 /* certificate domain component name length (ASCII characters not including zero-terminate) */
#define PKI_NAME_EMAIL_ADDRESS_LENGTH       128 /* certificate email address length (ASCII characters not including zero-terminate) */

/* all string sizes below are string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */

#define PKI_LABEL_SIZE                      (PKI_LABEL_LENGTH + 2)              /* certificate label name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define PKI_NAME_COMMON_NAME_SIZE           (PKI_NAME_COMMON_NAME_LENGTH + 2)   /* certificate common name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define PKI_NAME_SERIAL_NUMBER_SIZE         (PKI_NAME_SERIAL_NUMER_LENGTH + 2)  /* certificate serial number string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define PKI_NAME_COUNTRY_SIZE               (PKI_NAME_COUNTRY_LENGTH + 2)       /* certificate country name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define PKI_NAME_STATE_SIZE                 (PKI_NAME_STATE_LENGTH + 2)         /* certificate state name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define PKI_NAME_LOCALITY_SIZE              (PKI_NAME_LOCALITY_LENGTH + 2)      /* certificate locality name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define PKI_NAME_ORGANISATION_SIZE          (PKI_NAME_ORGANISATION_LENGTH + 2)  /* certificate organization name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define PKI_NAME_ORGANISATION_UNIT_SIZE     (PKI_NAME_ORGANISATION_UNIT_LENGTH + 2) /* certificate organization unit name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define PKI_NAME_TITLE_SIZE                 (PKI_NAME_TITLE_LENGTH + 2)         /* certificate title name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define PKI_NAME_SURNAME_SIZE               (PKI_NAME_SURNAME_LENGTH + 2)       /* certificate surname name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define PKI_NAME_GIVEN_NAME_SIZE            (PKI_NAME_GIVEN_NAME_LENGTH + 2)    /* certificate given name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define PKI_NAME_INITIALS_SIZE              (PKI_NAME_INITIALS_LENGTH + 2)      /* certificate initials string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define PKI_NAME_DOMAIN_COMPONENT_SIZE      (PKI_NAME_DOMAIN_COMPONENT_LENGTH + 2)  /* certificate domain component name string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */
#define PKI_NAME_EMAIL_ADDRESS_SIZE         (PKI_NAME_EMAIL_ADDRESS_LENGTH + 2) /* certificate email address string buffer size, including 2 bytes zero-terminate in case of UCS2 encoding */

/* defines the maximum number of certificates with exactly same subject name (must less than 10) */
#define PKI_NUM_MAX_DUP_LINK_FILES  (5) 

/* This is a certificate chain validation warning enum */
typedef enum {
    PKI_VAL_WARNING_NONE                        = 0x00000000,   /* NO warning in validation */
    PKI_VAL_WARNING_HAS_INTERMED_CERTS          = 0x00000001,   /* There are intermediate CA certificates in the chain */
    PKI_VAL_WARNING_BC_NOT_SET_CRITICAL         = 0x00000002,   /* One of the CA certificates in the chain has a basic constraints extension which isn't marked critical, which is required by PKIX */
    PKI_VAL_WARNING_BC_PATHLEN_EXCEEDED         = 0x00000004,   /* The basic constraints path length of one of the CA certificates in the chain has been exceeded */
    PKI_VAL_WARNING_UNKNOWN_CRITICAL_EXT        = 0x00000008,   /* Unknown critical extension encountered */
    PKI_VAL_WARNING_CERT_EXPIRED                = 0x00000010,   /* One of the certificates in the chain has a validity period that doesn't include the validation time */
    PKI_VAL_WARNING_KU_MISSING                  = 0x00000020,   /* One of the CA certificates in the chain doesn't have a key usage extension, which is required by PKIX */
    PKI_VAL_WARNING_KU_INVALID                  = 0x00000040,   /* A CA certificate in the chain doesn't have certSign bit asserted in its key usage extension, or the end-entity's key usage extension doesn't have the bits required by user */
    PKI_VAL_WARNING_BC_MISSING                  = 0x00000080,   /* One of the CA certificates in the chain doesn't have a basic constraint extension, which is required by PKIX */
    PKI_VAL_WARNING_BC_NOT_CA                   = 0x00000100,   /* One of the CA certificates in the chain doesn't have a CA bit set in its basic constraint extension */
    PKI_VAL_WARNING_NO_TRUSTED                  = 0x00000200,   /* The certificate chain doesn't end with a trusted certificate */
    PKI_VAL_WARNING_INVALID_SIGNATURE           = 0x00000400,   /* One of the certificates in the chain has an invalid signature */
    PKI_VAL_WARNING_CRL_NOT_FOUND               = 0x00001000,   /* No CRL was found for one of the certificates in the chain */
    PKI_VAL_WARNING_REVOKED                     = 0x00002000,   /* One of the certificates in the chain was revoked by a CRL */
    PKI_VAL_WARNING_INVALID_CRL_SIGNATURE       = 0x00004000,   /* One of the CRL's has an invalid signature */
    PKI_VAL_WARNING_CRL_INVALID_DATES           = 0x00008000,   /* One of the CRL's has invalid dates */
    PKI_VAL_WARNING_NC_UNSUPPORTED              = 0x00010000,   /* One of the certificates had a Name Constraint extension, and it was critical, but we don't support Name Constraints (Certicom solution) */
    PKI_VAL_WARNING_ISSUER_NOT_MATCHED          = 0x00020000,   /* One of the certificates in the chain had an issuer name that was not matched by the next cerificate in the chain */
    PKI_VAL_WARNING_BAD_CERTIFICATE             = 0x00040000,   /* One of the certificates in the chain can't be parsed correctly */
    PKI_VAL_WARNING_BAD_CRL                     = 0x00080000,   /* One of the CRL can be parsed correctly */
    PKI_VAL_WARNING_BAD_CA_CERTIFICATE          = 0x00100000,   /* One of the CA certificates in the chain verify failed */
    PKI_VAL_WARNING_PURPOSE_ERROR               = 0x00200000,   /* One of the certificates in the chain can't pass the specified trusted and untursted certs pool checking */
    PKI_VAL_WARNING_CRL_KU_INVALID              = 0x00400000,   /* One of the CRL's key usage check failed */
    PKI_VAL_WARNING_CRL_UNKNOWN_CRITICAL_EXT    = 0x00800000,   /* One of the CRL's has an unknown critical extension */
    PKI_VAL_WARNING_PROXY_CERT_ERROR            = 0x01000000,   /* Proxy certificate verify failed */
    PKI_VAL_WARNING_INVALID_EXT_ERROR           = 0x02000000,   /* invalid or inconsistent certificate extension */
    PKI_VAL_WARNING_POLICY_CHECK_ERROR          = 0x04000000,   /* invalid or inconsistent certificate policy extension */
    PKI_VAL_WARNING_TOTAL
}pki_val_warning_enum;

/* This enum defines the error return values of PKI adaptation layer */
typedef enum {
    PKI_ERR_NONE,                       /* 0 : Success */
    PKI_ERR_FAIL,                       /* 1 : General error */
    PKI_ERR_MEMFULL,                    /* 2 : Memory full error */
    PKI_ERR_INVALID_CONTEXT,            /* 3 : Input context error */
    PKI_ERR_OUT_OF_RANGE,               /* 4 : Specified item out of range in decoding process */
    PKI_ERR_INCORRECT_PASSWORD,         /* 5 : The input password is incorrect */
    PKI_ERR_FS_ERROR,                   /* 6 : File system operation failed */
    PKI_ERR_NEED_PASSWORD,              /* 7 : password required operation notify */   
    PKI_ERR_INVALID_INPUT,              /* 8 : input paramaters are invalid */
    PKI_ERR_EXT_NOT_FOUND,              /* 9 : specified extension is not found */
    PKI_ERR_ISSUER_UID_NOT_FOUND,       /* 10 : the issuer uid is not found in specified certificate */
    PKI_ERR_SUBJECT_UID_NOT_FOUND,      /* 11 : the subject uid is not found in specified certificate */
    PKI_ERR_UNSUPPORTED_CONTENT,        /* 12 : the specified content can't be parsed */
    PKI_ERR_CERT_NOT_FOUND,             /* 13 : can't find certificate in PEM decoding */
    PKI_ERR_CORRUPTED_DATA,             /* 14 : the input data is corrupted */
    PKI_ERR_EXCEED_MAX_DATA_SIZE,       /* 15 : the specified pkcs7 or pkcs12 data exceed predefined maximum size for importing */
    PKI_ERR_NOT_SUPPORTED_OP,           /* 16 : specifial return value for subject name hash utility (OpenSSL solution) */
    PKI_ERR_OCSP_VERIFY_FAIL,           /* 17 : verify OCSP cert fail */
    PKI_ERR_OCSP_STATUS_REVOKED,        /* 18 : the certificate is revoked */
    PKI_ERR_OCSP_STATUS_UNKNOWN,        /* 19 : the certificate is unknown */
    PKI_ERR_OCSP_NONCE_FAIL,            /* 20 : verify OCSP nonce fail */
    PKI_ERR_OCSP_TIME_VALIDITY,         /* 21 : proelbm in checking time fields */
    PKI_ERR_TOTAL
} pki_error_enum;

/* This enum defines the signature algorithms */
typedef enum
{
    PKI_SIGNALG_ECDSA_SHA1,     /* ECDSA + SHA1 */
    PKI_SIGNALG_ECDSA_SHA224,   /* ECDSA + SHA1-224 bits digest */
    PKI_SIGNALG_ECDSA_SHA256,   /* ECDSA + SHA1-256 bits digest */
    PKI_SIGNALG_ECDSA_SHA384,   /* ECDSA + SHA1-384 bits digest */
    PKI_SIGNALG_ECDSA_SHA512,   /* ECDSA + SHA1-512 bits digest */
    PKI_SIGNALG_DSA_SHA1,       /* DSA + SHA1 */
    PKI_SIGNALG_RSA_SHA1,       /* RSA + SHA1 */
    PKI_SIGNALG_RSA_MD4,        /* RSA + MD4 */
    PKI_SIGNALG_RSA_MD5,        /* RSA + MD5 */
    PKI_SIGNALG_RSA_MD2,        /* RSA + MD2 */
    PKI_SIGNALG_RSA_SHA256,     /* RSA + SHA1-256 bits digest */
    PKI_SIGNALG_RSA_SHA384,     /* RSA + SHA1-384 bits digest */
    PKI_SIGNALG_RSA_SHA512,     /* RSA + SHA1-512 bits digest */
    PKI_SIGNALG_RSA_PSS_SHA1,   /* RSA-PSS + SHA1 */
    PKI_SIGNALG_RSA_PSS_SHA224, /* RSA-PSS + SHA1-224 bits digest */
    PKI_SIGNALG_RSA_PSS_SHA256, /* RSA-PSS + SHA1-256 bits digest */
    PKI_SIGNALG_RSA_PSS_SHA384, /* RSA-PSS + SHA1-384 bits digest */
    PKI_SIGNALG_RSA_PSS_SHA512, /* RSA-PSS + SHA1-512 bits digest */
    PKI_SIGNALG_TOTAL
} pki_signature_alg;


/* This enum defines the certificate groups which aren't a category setting only but a filter setting by specified group */
typedef enum
{
    PKI_CERTGRP_NONE = 0x00,       /* no specified filter group */
    PKI_CERTGRP_ROOTCA = 0x01,     /* implies the cert's issuer = subject, filter group for root ca certs */
    PKI_CERTGRP_CA = 0x02,         /* ver 3 cert with BasicConstraint: CA=TRUE, filter group for ca certs */
    PKI_CERTGRP_OTHERUSER = 0x04,  /* ver 1 cert with no private key associated or ver 3 cert with BasicConstraint: CA=FALSE and without associated private key,
                                      filter group for other user certs */
    PKI_CERTGRP_PERSONAL = 0x08,   /* associated with a private key (regardless of whether it's a CA cert), filter group for personal certs */
    PKI_CERTGRP_ANY = 0xFF         /* filter group for all certs */
} pki_cert_group_enum;

/* This enum defines the certificate domains which aren't a category setting only but a filter setting by specified domain */
typedef enum
{
    PKI_DOMAIN_NONE = 0x00,         /* no specified filter domain */
    PKI_DOMAIN_UNTRUSTED = 0x01,    /* certs' with no specified domain, filter for untrusted domain certs */
    PKI_DOMAIN_OPERATOR = 0x02,     /* Operator installed certs, filter for operator domain certs */
    PKI_DOMAIN_MANUFACTURER = 0x04, /* Manufacturer installed certs, filter for Manufacturer domain certs */
    PKI_DOMAIN_THIRD_PARTY = 0x08,  /* Third party certs, filter for third party domain certs */
    PKI_DOMAIN_ANY = 0xFF           /* filter domain for all certs */
} pki_domain_enum;

/* This enum defines the pubkey type used in PKI adaptation layer */
typedef enum
{
    PKI_PUBKEY_RSA      = 0x01,     /* RSA */
    PKI_PUBKEY_DSA      = 0x02,     /* DSA */
    PKI_PUBKEY_DH_ANSI  = 0x04,     /* Diffie Hellman Key agreement */
    PKI_PUBKEY_DH_PKCS3 = 0x08,     /* PKCS3 */
    PKI_PUBKEY_EC       = 0x10,     /* ECC */
    PKI_PUBKEY_TOTAL    = 0xFF
} pki_pubkey_type_enum;

/* This enum defines the signature hash algorithm supported in PKI adaptation layer */
typedef enum
{
    PKI_HASH_ALG_MD5 = 0,   /* MD5 */
    PKI_HASH_ALG_SHA1,      /* SHA1 */
    PKI_HASH_ALG_TOTAL
} pki_hash_alg_enum;


/* This enum defines the PKI adaptation x509 name types
 * "common name" will always be the first name type in the nametype enum,
 * must not be shifted as lots of codes have dependency on this for traversing through name array */
typedef enum {
    PKI_NAMETYPE_COMMON_NAME = 0,       /* common name */
    PKI_NAMETYPE_SERIAL_NUMBER,         /* serial */
    PKI_NAMETYPE_COUNTRY,               /* country name */
    PKI_NAMETYPE_STATE,                 /* state name */
    PKI_NAMETYPE_LOCALITY,              /* locality */
    PKI_NAMETYPE_ORGANISATION,          /* organization name */
    PKI_NAMETYPE_ORGANISATION_UNIT,     /* organization unit name */
    PKI_NAMETYPE_TITLE,                 /* title */
    PKI_NAMETYPE_SURNAME,               /* surname */
    PKI_NAMETYPE_GIVEN_NAME,            /* given name */
    PKI_NAMETYPE_INITIALS,              /* initials */
    PKI_NAMETYPE_DOMAIN_COMPONENT,      /* domain component name */
    PKI_NAMETYPE_EMAIL_ADDRESS,         /* email address */
    PKI_NAMETYPE_TOTAL
} pki_name_structype_enum;

/* This enum defines the string encoding scheme in PKI adaptation layer */
typedef enum {
    PKI_DCS_ASCII = 0,      /* ASCII encoding string */
    PKI_DCS_UCS2            /* UCS2 encoding string */
} pki_dcs_enum;


/* This enum defines the defined extension key usage extension settings in X509 spec */
typedef enum {
    PKI_EXTKEYUSAGE_NONE = 0x00,                /* No specified extension key usage */
    PKI_EXTKEYUSAGE_SERVER_AUTH = 0x01,         /* extension key usage : server authentication assert */
    PKI_EXTKEYUSAGE_CLIENT_AUTH = 0x02,         /* extension key usage : client authentication assert */
    PKI_EXTKEYUSAGE_CODE_SIGNING = 0x04,        /* extension key usage : code signing assert */
    PKI_EXTKEYUSAGE_EMAIL_PROTECTION = 0x08,    /* extension key usage : email protection assert */
    PKI_EXTKEYUSAGE_IPSEC_ENDSYSTEM = 0x10,     /* extension key usage : IPSec end system assert */
    PKI_EXTKEYUSAGE_IPSEC_TUNNEL = 0x20,        /* extension key usage : IPSec tunneling assert */
    PKI_EXTKEYUSAGE_IPSEC_USER = 0x40,          /* extension key usage : IPSec user assert */
    PKI_EXTKEYUSAGE_TIME_STAMPING = 0x80,       /* extension key usage : Time stamp assert */
    PKI_EXTKEYUSAGE_OCSP_SIGNING = 0x100,       /* extension key usage : OCSP signing assert */
    PKI_EXTKEYUSAGE_ALL = 0x7FFFFFFF
} pki_extkeyusage_enum;


/* This enum defines the PKCS #7 content type */
typedef enum {
    PKI_PKCS7_CNTTYPE_DATA,         /* PKCS7 pure data content type */
    PKI_PKCS7_CNTTYPE_SIGDATA,      /* PKCS7 signed data content type */
    PKI_PKCS7_CNTTYPE_ENCDATA,      /* PKCS7 encrypted data content type */
    PKI_PKCS7_CNTTYPE_ENVDATA,      /* PKCS7 envelope data content type */
    PKI_PKCS7_CNTTYPE_SIGENVDATA,   /* PKCS7 signed envelope data content type */
    PKI_PKCS7_CNTTYPE_DIGDATA,      /* PKCS7 digest data content type */
    PKI_PKCS7_CNTTYPE_TOTAL
} pki_pkcs7_cnttype_enum;


/* This enum defines the PKCS #12 content type */
typedef enum {
    PKI_SAFEBAG_KEYBAG,             /* PKCS12 key bag type */
    PKI_SAFEBAG_SHROUDEDKEYBAG,     /* PKCS12 encrypted key bag type */
    PKI_SAFEBAG_CERTBAG,            /* PKCS12 certificate bag type */
    PKI_SAFEBAG_CRLBAG,             /* PKCS12 CRL bag type */
    PKI_SAFEBAG_SECRETBAG,          /* PKCS12 secret bag type */
    PKI_SAFEBAG_SAFECONTENTBAG,     /* PKCS12 safe content bag type */
    PKI_SAFEBAG_TOTAL
} pki_safebag_type_enum;

/* This enum defines the validation usage operations */
typedef enum
{
    PKI_VALUSAGE_VALIDATE = 0,      /* certificate chain validation */
    PKI_VALUSAGE_GENCHAIN           /* gen certificate chain */
} pki_valusage_enum;

/* This enum defines the file type of the folder set to validation trusted certs pool */
typedef enum
{  
    PKI_FILETYPE_NONE = 0,  /* didn't set verify pool */
    PKI_FILETYPE_DER,       /* the selected verify pool folder contains certs with DER format */
    PKI_FILETYPE_PEM,       /* the selected verify pool folder contains certs with PEM format */
    PKI_FILETYPE_TOTAL
}pki_filetype_enum;

#endif  /* PKI_DEFS_H */
