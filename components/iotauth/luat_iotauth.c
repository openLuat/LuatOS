
#include "luat_base.h"
#include "luat_crypto.h"
#include "luat_mem.h"
#include "time.h"
#include "luat_str.h"
#include "luat_mcu.h"
#include "printf.h"
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

/* 大小写不敏感的算法名比较, 如 method_is("HMACMD5", "hmacmd5") 为真 */
static int method_is(const char* method, const char* name) {
    if (method == NULL || name == NULL)
        return 0;
    while (*name) {
        char a = *method++;
        char b = *name++;
        if (a >= 'A' && a <= 'Z')
            a += 32;
        if (a != b)
            return 0;
    }
    return *method == '\0';
}

int luat_aliyun_token(iotauth_ctx_t* ctx,const char* product_key,const char* device_name,const char* device_secret,long long cur_timestamp,const char* method,uint8_t is_tls){
    char deviceId[64] = {0};
    char macSrc[200] = {0};
    char macRes[32] = {0};
    char timestamp_value[20] = {0};
    const char* sign_method = NULL;
    uint8_t securemode = is_tls ? 2 : 3;
    if (method_is(method, "hmacmd5")) {
        sign_method = "hmacmd5";
    }else if (method_is(method, "hmacsha1")) {
        sign_method = "hmacsha1";
    }else if (method_is(method, "hmacsha256")) {
        sign_method = "hmacsha256";
    }else{
        LLOGE("not support: %s",method);
        return -1;
    }
    sprintf_(timestamp_value,"%lld",cur_timestamp);
    sprintf_(deviceId,"%s.%s",product_key,device_name);
    /* setup clientid */
    sprintf_(ctx->client_id,"%s|securemode=%d,signmethod=%s,timestamp=%s|",deviceId,securemode,sign_method,timestamp_value);

    /* setup username */
    sprintf_(ctx->user_name,"%s&%s",device_name,product_key);

    /* setup password */
    memcpy(macSrc, "clientId", strlen("clientId"));
    memcpy(macSrc + strlen(macSrc), deviceId, strlen(deviceId));
    memcpy(macSrc + strlen(macSrc), "deviceName", strlen("deviceName"));
    memcpy(macSrc + strlen(macSrc), device_name, strlen(device_name));
    memcpy(macSrc + strlen(macSrc), "productKey", strlen("productKey"));
    memcpy(macSrc + strlen(macSrc), product_key, strlen(product_key));
    memcpy(macSrc + strlen(macSrc), "timestamp", strlen("timestamp"));
    memcpy(macSrc + strlen(macSrc), timestamp_value, strlen(timestamp_value));
    if (method_is(method, "hmacmd5")) { /* hmacmd5 */
        luat_crypto_hmac_md5_simple(macSrc, strlen(macSrc),device_secret, strlen(device_secret),  macRes);
        str_tohex(macRes, 16, ctx->password,1);
    }else if (method_is(method, "hmacsha1")) { /* hmacsha1 */
        luat_crypto_hmac_sha1_simple(macSrc, strlen(macSrc),device_secret, strlen(device_secret),  macRes);
        str_tohex(macRes, 20, ctx->password,1);
    }else{ /* hmacsha256 */
        luat_crypto_hmac_sha256_simple(macSrc, strlen(macSrc),device_secret, strlen(device_secret),  macRes);
        str_tohex(macRes, 32, ctx->password,1);
    }
    return 0;
}


typedef struct {
    char et[32];
    char version[12];
    char method[12];
    char res[64];
    char sign[64];
} sign_msg;

/* URL编码所需字符集, 转义结果 "%XX" 即字符自身ASCII值的十六进制 */
static const char url_enc_chars[] = "+ /?%#&=";

/* 对 src 做URL编码后写回自身, 保留老版本的越界截断行为 */
static void url_encode_inplace(char* src) {
    char temp[192] = {0};
    int i, j;
    size_t slen = strlen(src);
    for (i = 0, j = 0; i < (int)slen; i++) {
        if (strchr(url_enc_chars, src[i])) {
            if (j + 3 >= (int)sizeof(temp)) break;
            j += snprintf_(temp + j, sizeof(temp) - j, "%%%02X", src[i]);
        }else{
            if (j + 1 >= (int)sizeof(temp)) break;
            temp[j++] = src[i];
        }
    }
    temp[j] = 0;
    memcpy(src, temp, j + 1);
}

static int url_encoding_for_token(sign_msg* msg,char *token){
    url_encode_inplace(msg->res);
    url_encode_inplace(msg->sign);
    if(snprintf_(token,PASSWORD_LEN, "version=%s&res=%s&et=%s&method=%s&sign=%s", msg->version, msg->res, msg->et, msg->method, msg->sign)<0){
        return -1;
    }
    return strlen(token);
}

int luat_onenet_token(iotauth_ctx_t* ctx,const iotauth_onenet_t* onenet) {
    size_t  declen = 0, enclen =  0,hmac_len = 0;
    char plaintext[64]     = { 0 };
    char hmac[64]          = { 0 };
    char StringForSignature[256] = { 0 };
    sign_msg sign = {0};
    memcpy(sign.method, onenet->method, strlen(onenet->method));
    memcpy(sign.version, onenet->version, strlen(onenet->version));
    sprintf_(sign.et,"%lld", onenet->cur_timestamp);
    if (onenet->res) {
        sprintf_(sign.res, "%s", onenet->res);
    }
    else {
        sprintf_(sign.res,"products/%s/devices/%s", onenet->product_id, onenet->device_name);
    }
    
    luat_str_base64_decode((unsigned char *)plaintext, sizeof(plaintext), &declen, (const unsigned char * )onenet->device_secret, strlen((char*)onenet->device_secret));
    sprintf_(StringForSignature, "%s\n%s\n%s\n%s", sign.et, sign.method, sign.res, sign.version);
    if (method_is(onenet->method, "md5")) {
        luat_crypto_hmac_md5_simple(StringForSignature, strlen(StringForSignature), plaintext, declen, hmac);
        hmac_len = 16;
    }else if (method_is(onenet->method, "sha1")) {
        luat_crypto_hmac_sha1_simple(StringForSignature, strlen(StringForSignature),plaintext, declen,  hmac);
        hmac_len = 20;
    }else if (method_is(onenet->method, "sha256")) {
        luat_crypto_hmac_sha256_simple(StringForSignature, strlen(StringForSignature),plaintext, declen,  hmac);
        hmac_len = 32;
    }else{
        LLOGE("not support: %s", onenet->method);
        return -1;
    }
    
    luat_str_base64_encode((unsigned char *)sign.sign, sizeof(sign.sign), &enclen, (const unsigned char * )hmac, hmac_len);
    snprintf_(ctx->client_id, CLIENT_ID_LEN,"%s", onenet->device_name);
    snprintf_(ctx->user_name, USER_NAME_LEN,"%s", onenet->product_id);
    url_encoding_for_token(&sign, ctx->password);
    return 0;
}

int luat_iotda_token(iotauth_ctx_t* ctx,const char* device_id,const char* device_secret,long long cur_timestamp,int ins_timestamp){
    char hmac[65] = {0};
    char timestamp[11] = {0};
    struct tm *timeinfo = localtime( &cur_timestamp );
    if(snprintf_(timestamp, 11, "%04d%02d%02d%02d", (timeinfo->tm_year)+1900,timeinfo->tm_mon+1,timeinfo->tm_mday,timeinfo->tm_hour)<0){
        return -1;
    }
    snprintf_(ctx->client_id, CLIENT_ID_LEN, "%s_0_%d_%s", device_id,ins_timestamp,timestamp);
    snprintf_(ctx->user_name, USER_NAME_LEN,"%s", device_id);
    luat_crypto_hmac_sha256_simple(device_secret, strlen(device_secret),timestamp, strlen(timestamp), hmac);
    str_tohex(hmac, 32, ctx->password,0);
    return 0;
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

int luat_qcloud_token(iotauth_ctx_t* ctx,const char* product_id,const char* device_name,const char* device_secret,long long cur_timestamp,const char* method,const char* sdk_appid){
    char  conn_id[MAX_CONN_ID_LEN] = {0};
    char  username_sign[41] = {0};
    char  psk_base64decode[DECODE_PSK_LENGTH] = {0};
    size_t psk_base64decode_len = 0;
    luat_str_base64_decode((unsigned char *)psk_base64decode, DECODE_PSK_LENGTH, &psk_base64decode_len,(unsigned char *)device_secret, strlen(device_secret));
    get_next_conn_id(conn_id);
    snprintf_(ctx->client_id, CLIENT_ID_LEN,"%s%s", product_id,device_name);
    snprintf_(ctx->user_name, USER_NAME_LEN,"%s%s;%s;%s;%lld", product_id, device_name, sdk_appid,conn_id, cur_timestamp);
    uint8_t is_sha1 = method_is(method, "sha1");
    if (is_sha1) {
        luat_crypto_hmac_sha1_simple(ctx->user_name, strlen(ctx->user_name),psk_base64decode, psk_base64decode_len, username_sign);
    }else if (method_is(method, "sha256")) {
        luat_crypto_hmac_sha256_simple(ctx->user_name, strlen(ctx->user_name),psk_base64decode, psk_base64decode_len, username_sign);
    }else{
        LLOGE("not support: %s",method);
        return -1;
    }
    char username_sign_hex[100] = {0};
    if (is_sha1) {
        str_tohex(username_sign, 20, username_sign_hex,0);
        snprintf_(ctx->password, PASSWORD_LEN,"%s;hmacsha1", username_sign_hex);
    }else{
        str_tohex(username_sign, 32, username_sign_hex,0);
        snprintf_(ctx->password, PASSWORD_LEN,"%s;hmacsha256", username_sign_hex);
    }
    return 0;
}

int luat_tuya_token(iotauth_ctx_t* ctx,const char* device_id,const char* device_secret,long long cur_timestamp){
    char hmac[65] = {0};
    char token_temp[100]  = {0};
    snprintf_(token_temp, 100, "deviceId=%s,timestamp=%lld,secureMode=1,accessType=1", device_id, cur_timestamp);
    luat_crypto_hmac_sha256_simple(token_temp, strlen(token_temp),device_secret, strlen(device_secret), hmac);
    snprintf_(ctx->client_id, CLIENT_ID_LEN, "tuyalink_%s", device_id);
    snprintf_(ctx->user_name, USER_NAME_LEN, "%s|signMethod=hmacSha256,timestamp=%lld,secureMode=1,accessType=1", device_id,cur_timestamp);
    str_tohex(hmac, 32, ctx->password,0);
    return 0;
}

int luat_baidu_token(iotauth_ctx_t* ctx,const char* iot_core_id,const char* device_key,const char* device_secret,const char* method,long long cur_timestamp){
    char crypto[64] = {0};
    char token_temp[100] = {0};
    const char* method_name = NULL;
    uint8_t is_sha256 = 0;
    if (method_is(method, "md5")) {
        method_name = "MD5";
    }else if (method_is(method, "sha256")) {
        method_name = "SHA256";
        is_sha256 = 1;
    }else{
        LLOGE("not support: %s",method);
        /* 保持老版本行为: client_id 已写入后再报错 */
        snprintf_(ctx->client_id, CLIENT_ID_LEN, "%s", iot_core_id);
        return -1;
    }
    snprintf_(ctx->client_id, CLIENT_ID_LEN, "%s", iot_core_id);
    if (cur_timestamp){
        snprintf_(ctx->user_name,USER_NAME_LEN, "thingidp@%s|%s|%lld|%s",iot_core_id,device_key,cur_timestamp,method_name);
    }else{
        snprintf_(ctx->user_name,USER_NAME_LEN, "thingidp@%s|%s|%s",iot_core_id,device_key,method_name);
    }
    snprintf_(token_temp, 100, "%s&%lld&%s%s",device_key,cur_timestamp,method_name,device_secret);
    if (is_sha256) {
        luat_crypto_sha256_simple(token_temp, strlen(token_temp),crypto);
        str_tohex(crypto, 32, ctx->password,0);
    }else{
        luat_crypto_md5_simple(token_temp, strlen(token_temp),crypto);
        str_tohex(crypto, 16, ctx->password,0);
    }
    return 0;
}
