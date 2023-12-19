
/*
@module  iotauth
@summary IoT鉴权库, 用于生成各种云平台的参数
@version core V0007
@date    2022.08.06
@demo iotauth
@tag LUAT_USE_IOTAUTH
*/
#include "luat_base.h"
#include "luat_crypto.h"
#include "luat_mem.h"
#include "time.h"
#include "luat_str.h"
#include "luat_mcu.h"

#include "luat_iotauth.h"

#define LUAT_LOG_TAG "iotauth"
#include "luat_log.h"

static const unsigned char hexchars_s[] = "0123456789abcdef";
static const unsigned char hexchars_u[] = "0123456789ABCDEF";

static void str_tohex(const char* str, size_t str_len, char* hex,uint8_t uppercase) {
    const unsigned char* hexchars = NULL;
    if (uppercase)
        hexchars = hexchars_u;
    else
        hexchars = hexchars_s;
    for (size_t i = 0; i < str_len; i++)
    {
        char ch = *(str+i);
        hex[i*2] = hexchars[(unsigned char)ch >> 4];
        hex[i*2+1] = hexchars[(unsigned char)ch & 0xF];
    }
}

void luat_aliyun_token(const char* product_key,const char* device_name,const char* device_secret,long long cur_timestamp,const char* method,uint8_t is_tls,char* client_id, char* user_name, char* password){
    char deviceId[64] = {0};
    char macSrc[200] = {0};
    char macRes[32] = {0};
    char timestamp_value[20] = {0};
    uint8_t securemode = 3;
    if (is_tls){
        securemode = 2;
    }
    sprintf_(timestamp_value,"%lld",cur_timestamp);
    sprintf_(deviceId,"%s.%s",product_key,device_name);
    /* setup clientid */
    if (!strcmp("hmacmd5", method)||!strcmp("HMACMD5", method)) {
        sprintf_(client_id,"%s|securemode=%d,signmethod=hmacmd5,timestamp=%s|",deviceId,securemode,timestamp_value);
    }else if (!strcmp("hmacsha1", method)||!strcmp("HMACSHA1", method)) {
        sprintf_(client_id,"%s|securemode=%d,signmethod=hmacsha1,timestamp=%s|",deviceId,securemode,timestamp_value);
    }else if (!strcmp("hmacsha256", method)||!strcmp("HMACSHA256", method)) {
        sprintf_(client_id,"%s|securemode=%d,signmethod=hmacsha256,timestamp=%s|",deviceId,securemode,timestamp_value);
    }else{
        LLOGE("not support: %s",method);
        return;
    }

    /* setup username */
    sprintf_(user_name,"%s&%s",device_name,product_key);

    /* setup password */
    memcpy(macSrc, "clientId", strlen("clientId"));
    memcpy(macSrc + strlen(macSrc), deviceId, strlen(deviceId));
    memcpy(macSrc + strlen(macSrc), "deviceName", strlen("deviceName"));
    memcpy(macSrc + strlen(macSrc), device_name, strlen(device_name));
    memcpy(macSrc + strlen(macSrc), "productKey", strlen("productKey"));
    memcpy(macSrc + strlen(macSrc), product_key, strlen(product_key));
    memcpy(macSrc + strlen(macSrc), "timestamp", strlen("timestamp"));
    memcpy(macSrc + strlen(macSrc), timestamp_value, strlen(timestamp_value));
    if (!strcmp("hmacmd5", method)||!strcmp("HMACMD5", method)) {
        luat_crypto_hmac_md5_simple(macSrc, strlen(macSrc),device_secret, strlen(device_secret),  macRes);
        str_tohex(macRes, 16, password,1);
    }else if (!strcmp("hmacsha1", method)||!strcmp("HMACSHA1", method)) {
        luat_crypto_hmac_sha1_simple(macSrc, strlen(macSrc),device_secret, strlen(device_secret),  macRes);
        str_tohex(macRes, 20, password,1);
    }else if (!strcmp("hmacsha256", method)||!strcmp("HMACSHA256", method)) {
        luat_crypto_hmac_sha256_simple(macSrc, strlen(macSrc),device_secret, strlen(device_secret),  macRes);
        str_tohex(macRes, 32, password,1);
    }else{
        LLOGE("not support: %s",method);
        return;
    }
}


typedef struct {
    char et[32];
    char version[12];
    char method[12];
    char res[64];
    char sign[64];
} sign_msg;

typedef  struct {
    char* old_str;
    char* str;
}URL_PARAMETES;

static int url_encoding_for_token(sign_msg* msg,char *token){
    int i,j,k,slen;
    sign_msg* temp_msg = msg;
    URL_PARAMETES url_patametes[] = {
        {"+","%2B"},
        {" ","%20"},
        {"/","%2F"},
        {"?","%3F"},
        {"%","%25"},
        {"#","%23"},
        {"&","%26"},
        {"=","%3D"},
    };
    char temp[64]     = {0};
    slen = strlen(temp_msg->res);
    for (i = 0,j = 0; i < slen; i++) {
        for(k = 0; k < 8; k++){
            if(temp_msg->res[i] == url_patametes[k].old_str[0]) {
                memcpy(&temp[j],url_patametes[k].str,strlen(url_patametes[k].str));
                j+=3;
                break;
            }
        }
        if (k == 8) {
            temp[j++] = temp_msg->res[i];
        }
	}
    memcpy(temp_msg->res,temp,strlen(temp));
    temp_msg->res[strlen(temp)] = 0;
    memset(temp,0x00,sizeof(temp));
    slen = strlen(temp_msg->sign);
    for (i = 0,j = 0; i < slen; i++) {
        for(k = 0; k < 8; k++){
            if(temp_msg->sign[i] == url_patametes[k].old_str[0]) {
                memcpy(&temp[j],url_patametes[k].str,strlen(url_patametes[k].str));
                j+=3;
                break;
            }
        }
        if(k == 8){
            temp[j++] = temp_msg->sign[i];
        }
	}
    memcpy(temp_msg->sign,temp,strlen(temp));
    temp_msg->sign[strlen(temp)] = 0;
    if(snprintf_(token,PASSWORD_LEN, "version=%s&res=%s&et=%s&method=%s&sign=%s", temp_msg->version, temp_msg->res, temp_msg->et, temp_msg->method, temp_msg->sign)<0){
        return -1;
    }
    return strlen(token);
}

void luat_onenet_token(const char* product_id,const char* device_name,const char* device_secret,long long cur_timestamp,char * method,char * version,char *token){
    size_t  declen = 0, enclen =  0,hmac_len = 0;
    char plaintext[64]     = { 0 };
    char hmac[64]          = { 0 };
    char StringForSignature[256] = { 0 };
    sign_msg sign = {0};
    memcpy(sign.method, method, strlen(method));
    memcpy(sign.version, version, strlen(version));
    sprintf_(sign.et,"%lld",cur_timestamp);
    sprintf_(sign.res,"products/%s/devices/%s",product_id,device_name);
    luat_str_base64_decode((unsigned char *)plaintext, sizeof(plaintext), &declen, (const unsigned char * )device_secret, strlen((char*)device_secret));
    sprintf_(StringForSignature, "%s\n%s\n%s\n%s", sign.et, sign.method, sign.res, sign.version);
    if (!strcmp("md5", method)||!strcmp("MD5", method)) {
        luat_crypto_hmac_md5_simple(StringForSignature, strlen(StringForSignature), plaintext, declen, hmac);
        hmac_len = 16;
    }else if (!strcmp("sha1", method)||!strcmp("SHA1", method)) {
        luat_crypto_hmac_sha1_simple(StringForSignature, strlen(StringForSignature),plaintext, declen,  hmac);
        hmac_len = 20;
    }else if (!strcmp("sha256", method)||!strcmp("SHA256", method)) {
        luat_crypto_hmac_sha256_simple(StringForSignature, strlen(StringForSignature),plaintext, declen,  hmac);
        hmac_len = 32;
    }else{
        LLOGE("not support: %s",method);
        return;
    }
    
    luat_str_base64_encode((unsigned char *)sign.sign, sizeof(sign.sign), &enclen, (const unsigned char * )hmac, hmac_len);
    url_encoding_for_token(&sign,token);
}

void luat_iotda_token(const char* device_id,const char* device_secret,long long cur_timestamp,int ins_timestamp,char* client_id,const char* password){
    char hmac[65] = {0};
    char timestamp[11] = {0};
    struct tm *timeinfo = localtime( &cur_timestamp );
    if(snprintf_(timestamp, 11, "%04d%02d%02d%02d", (timeinfo->tm_year)+1900,timeinfo->tm_mon+1,timeinfo->tm_mday,timeinfo->tm_hour)<0){
        return;
    }
    snprintf_(client_id, CLIENT_ID_LEN, "%s_0_%d_%s", device_id,ins_timestamp,timestamp);
    luat_crypto_hmac_sha256_simple(device_secret, strlen(device_secret),timestamp, strlen(timestamp), hmac);
    str_tohex(hmac, 32, password,0);
}

/* Max size of base64 encoded PSK = 64, after decode: 64/4*3 = 48*/
#define DECODE_PSK_LENGTH 48
/* Max size of conn Id  */
#define MAX_CONN_ID_LEN (6)

static void get_next_conn_id(char *conn_id){
    size_t i;
    luat_crypto_trng(conn_id, 5);
    for (i = 0; i < MAX_CONN_ID_LEN - 1; i++) {
        conn_id[i] = (conn_id[i] % 26) + 'a';
    }
    conn_id[MAX_CONN_ID_LEN - 1] = '\0';
}

void luat_qcloud_token(const char* product_id,const char* device_name,const char* device_secret,long long cur_timestamp,const char* method,const char* sdk_appid,char* username,char* password){
    char  conn_id[MAX_CONN_ID_LEN] = {0};
    char  username_sign[41] = {0};
    char  psk_base64decode[DECODE_PSK_LENGTH] = {0};
    size_t psk_base64decode_len = 0;
    luat_str_base64_decode((unsigned char *)psk_base64decode, DECODE_PSK_LENGTH, &psk_base64decode_len,(unsigned char *)device_secret, strlen(device_secret));
    get_next_conn_id(conn_id);
    snprintf_(username, USER_NAME_LEN,"%s%s;%s;%s;%lld", product_id, device_name, sdk_appid,conn_id, cur_timestamp);
    if (!strcmp("sha1", method)||!strcmp("SHA1", method)) {
        luat_crypto_hmac_sha1_simple(username, strlen(username),psk_base64decode, psk_base64decode_len, username_sign);
    }else if (!strcmp("sha256", method)||!strcmp("SHA256", method)) {
        luat_crypto_hmac_sha256_simple(username, strlen(username),psk_base64decode, psk_base64decode_len, username_sign);
    }else{
        LLOGE("not support: %s",method);
        return;
    }
    char username_sign_hex[100] = {0};
    if (!strcmp("sha1", method)||!strcmp("SHA1", method)) {
        str_tohex(username_sign, 20, username_sign_hex,0);
        snprintf_(password, PASSWORD_LEN,"%s;hmacsha1", username_sign_hex);
    }else if (!strcmp("sha256", method)||!strcmp("SHA256", method)) {
        str_tohex(username_sign, 32, username_sign_hex,0);
        snprintf_(password, PASSWORD_LEN,"%s;hmacsha256", username_sign_hex);
    }
}

void luat_tuya_token(const char* device_id,const char* device_secret,long long cur_timestamp,const char* password){
    char hmac[65] = {0};
    char token_temp[100]  = {0};
    snprintf_(token_temp, 100, "deviceId=%s,timestamp=%lld,secureMode=1,accessType=1", device_id, cur_timestamp);
    luat_crypto_hmac_sha256_simple(token_temp, strlen(token_temp),device_secret, strlen(device_secret), hmac);
    str_tohex(hmac, 32, password,0);
}

void luat_baidu_token(const char* iot_core_id,const char* device_key,const char* device_secret,const char* method,long long cur_timestamp,char* username,char* password){
    char crypto[64] = {0};
    char token_temp[100] = {0};
    if (!strcmp("MD5", method)||!strcmp("md5", method)) {
        if (cur_timestamp){
            snprintf_(username,USER_NAME_LEN, "thingidp@%s|%s|%lld|%s",iot_core_id,device_key,cur_timestamp,"MD5");
        }else{
            snprintf_(username,USER_NAME_LEN, "thingidp@%s|%s|%s",iot_core_id,device_key,"MD5");
        }
        snprintf_(token_temp, 100, "%s&%lld&%s%s",device_key,cur_timestamp,"MD5",device_secret);
        luat_crypto_md5_simple(token_temp, strlen(token_temp),crypto);
        str_tohex(crypto, 16, password,0);
    }else if (!strcmp("SHA256", method)||!strcmp("sha256", method)) {
        if (cur_timestamp){
            snprintf_(username,USER_NAME_LEN, "thingidp@%s|%s|%lld|%s",iot_core_id,device_key,cur_timestamp,"SHA256");
        }else{
            snprintf_(username,USER_NAME_LEN, "thingidp@%s|%s|%s",iot_core_id,device_key,"SHA256");
        }
        snprintf_(token_temp, 100, "%s&%lld&%s%s",device_key,cur_timestamp,"SHA256",device_secret);
        luat_crypto_sha256_simple(token_temp, strlen(token_temp),crypto);
        str_tohex(crypto, 32, password,0);
    }else{
        LLOGE("not support: %s",method);
    }
    return;
}
