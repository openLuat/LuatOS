// IoT鉴权函数, 用于生成各种云平台的参数

#include "luat_base.h"
#include "luat_crypto.h"
#include "luat_malloc.h"
#include "time.h"

#define LUAT_LOG_TAG "iotauth"
#include "luat_log.h"

typedef struct onenet_msg{
    const char* produt_id;
    const char* device_name;
    const char* key;
    const char* method;
    const char* version;
    long long time;
}onenet_msg_t;
typedef struct {
    char et[32];
    char *version;
    char *method;
    char res[128];
    char sign[128];
} sign_msg;

typedef  struct {
    char* old_str;
    char* str;
}URL_PARAMETES;

static void HexDump(char *pData, uint16_t len){
    for (int i = 0; i < len; i++) {
        printf("0x%02.2x ", (unsigned char)pData[i]);
    }
    printf("\n");
}

static const unsigned char hexchars[] = "0123456789abcdef";
static void str_tohex(const char* str, size_t str_len, char* hex) {
    for (size_t i = 0; i < str_len; i++)
    {
        char ch = *(str+i);
        hex[i*2] = hexchars[(unsigned char)ch >> 4];
        hex[i*2+1] = hexchars[(unsigned char)ch & 0xF];
    }
}

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
    char temp[128]     = {0};
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
    sprintf(token, "version=%s&res=%s&et=%s&method=%s&sign=%s", temp_msg->version, temp_msg->res, temp_msg->et, temp_msg->method, temp_msg->sign);
    return strlen(token);
}

int onenet_token(onenet_msg_t* msg, long long time,char * method,char * version,char *token){
    size_t  declen = 0, enclen =  0;
    char plaintext[64]     = { 0 };
    char hmac[64]          = { 0 };
    char StringForSignature[256] = { 0 };
    sign_msg sign = {0};
    sign.method = method;
    sign.version = version;

    sprintf(sign.et,"%lld",time);
    sprintf(sign.res,"products/%s/devices/%s",msg->produt_id,msg->device_name);
    luat_str_base64_decode((unsigned char *)plaintext, sizeof(plaintext), &declen, (const unsigned char * )msg->key, strlen((char*)msg->key));
    sprintf(StringForSignature, "%s\n%s\n%s\n%s", sign.et, sign.method, sign.res, sign.version);
    printf("StringForSignature:%d\n%s\n",declen,StringForSignature);
    if (!strcmp("md5", method)) {
        luat_crypto_hmac_md5_simple(plaintext, declen,StringForSignature, strlen(StringForSignature), hmac);
    }else if (!strcmp("sha1", method)) {
        luat_crypto_hmac_sha1_simple(plaintext, declen,StringForSignature, strlen(StringForSignature), hmac);
    }else if (!strcmp("sha256", method)) {
        luat_crypto_hmac_sha256_simple(plaintext, declen,StringForSignature, strlen(StringForSignature), hmac);
    }else{
        LLOGE("not support: %s",method);
        return -1;
    }
    luat_str_base64_encode((unsigned char *)sign.sign, sizeof(sign.sign), &enclen, (const unsigned char * )hmac, strlen(hmac));
    return url_encoding_for_token(&sign,token);
}

static int l_iotauth_aliyun(lua_State *L) {
    return 0;
}

static int l_iotauth_onenet(lua_State *L) {
    char token[200]={0};
    size_t len;
    onenet_msg_t onenet;
    onenet.device_name = luaL_checklstring(L, 1, &len);
    onenet.produt_id = luaL_checklstring(L, 2, &len);
    onenet.key = luaL_checklstring(L, 3, &len);
    onenet.method = luaL_optlstring(L, 4, "sha256", &len);
    onenet.time = luaL_optinteger(L, 5,time(NULL) + 3600);
    onenet.version = luaL_optlstring(L, 6, "2018-10-31", &len);
    len = onenet_token(&onenet, onenet.time,onenet.method,onenet.version,token);
    lua_pushlstring(L, token, len);
    return 1;
}

static int l_iotauth_iotda(lua_State *L) {
    return 0;
}

/* Max size of base64 encoded PSK = 64, after decode: 64/4*3 = 48*/
#define DECODE_PSK_LENGTH 48
/* Max size of conn Id  */
#define MAX_CONN_ID_LEN (6)

static void get_next_conn_id(char *conn_id)
{
    int i;
    srand((unsigned)luat_mcu_ticks());
    for (i = 0; i < MAX_CONN_ID_LEN - 1; i++) {
        int flag = rand() % 3;
        switch (flag) {
            case 0:
                conn_id[i] = (rand() % 26) + 'a';
                break;
            case 1:
                conn_id[i] = (rand() % 26) + 'A';
                break;
            case 2:
                conn_id[i] = (rand() % 10) + '0';
                break;
        }
    }

    conn_id[MAX_CONN_ID_LEN - 1] = '\0';
}

int qcloud_token(const char* product_id,const char* device_name,const char* device_secret,long long cur_timestamp,const char* method,const char* sdk_appid,const char* token){
    char *username     = NULL;
    int   username_len = 0;
    char  conn_id[MAX_CONN_ID_LEN] = {};
    char username_sign[41] = {0};
    char   psk_base64decode[DECODE_PSK_LENGTH];
    size_t psk_base64decode_len = 0;
    luat_str_base64_decode((unsigned char *)psk_base64decode, DECODE_PSK_LENGTH, &psk_base64decode_len,(unsigned char *)device_secret, strlen(device_secret));
    username_len = strlen(product_id) + strlen(device_name) + strlen(sdk_appid) + MAX_CONN_ID_LEN + 20;
    username     = (char *)luat_heap_malloc(username_len);
    if (username == NULL) {
        printf("malloc username failed!\r\n");
        return -1;
    }
    get_next_conn_id(conn_id);
    printf("conn_id %s\n",conn_id);
    snprintf(username, username_len, "%s%s;%s;%s;%ld", product_id, device_name, sdk_appid,conn_id, cur_timestamp);
    if (!strcmp("sha1", method)) {
        luat_crypto_hmac_sha1_simple(username, strlen(username),psk_base64decode, psk_base64decode_len, username_sign);
    }else if (!strcmp("sha256", method)) {
        luat_crypto_hmac_sha256_simple(username, strlen(username),psk_base64decode, psk_base64decode_len, username_sign);
    }else{
        LLOGE("not support: %s",method);
        return -1;
    }
    char *username_sign_hex  = (char *)luat_heap_malloc(strlen(username_sign)*2+1);
    memset(username_sign_hex, 0, strlen(username_sign)*2+1);
    str_tohex(username_sign, strlen(username_sign), username_sign_hex);
    sprintf(token, "%s;hmacsha1", username_sign_hex);
    luat_heap_free(username);
    luat_heap_free(username_sign_hex);
    return strlen(token);
}

static int l_iotauth_qcloud(lua_State *L) {
    char token[200]={0};
    size_t len;
    const char* product_id = luaL_checklstring(L, 1, &len);
    const char* device_name = luaL_checklstring(L, 2, &len);
    const char* device_secret = luaL_checklstring(L, 3, &len);
    const char* method = luaL_optlstring(L, 4, "sha256", &len);
    long long cur_timestamp = luaL_optinteger(L, 5,time(NULL) + 3600);
    const char* sdk_appid = luaL_optlstring(L, 6, "12010126", &len);
    len = qcloud_token(product_id, device_name,device_secret,cur_timestamp,method,sdk_appid,token);
    lua_pushlstring(L, token, len);
    return 1;
}

int tuya_token(const char* device_id,const char* device_secret,long long cur_timestamp,const char* token){
    char hmac[64] = {0};
    char *token_temp  = (char *)luat_heap_malloc(100);
    memset(token_temp, 0, 100);
    snprintf(token_temp, 100, "deviceId=%s,timestamp=%ld,secureMode=1,accessType=1", device_id, cur_timestamp);
    luat_crypto_hmac_sha256_simple(token_temp, strlen(token_temp),device_secret, strlen(device_secret), hmac);
    str_tohex(hmac, strlen(hmac), token);
    luat_heap_free(token_temp);
    return strlen(token);
}

static int l_iotauth_tuya(lua_State *L) {
    char token[200]={0};
    size_t len;
    const char* device_id = luaL_checklstring(L, 1, &len);
    const char* device_secret = luaL_checklstring(L, 2, &len);
    long long cur_timestamp = luaL_optinteger(L, 3,time(NULL) + 3600);
    len = tuya_token(device_id,device_secret,cur_timestamp,token);
    lua_pushlstring(L, token, len);
    return 1;
}

static void baidu_token(const char* iot_core_id,const char* device_key,const char* device_secret,const char* method,long long cur_timestamp,char* user_name,char* password){
    char crypto[64] = {0};
    char *token_temp  = (char *)luat_heap_malloc(100);
    memset(token_temp, 0, 100);
    if (!strcmp("MD5", method)||!strcmp("md5", method)) {
        sprintf(user_name, "thingidp@%s|%s|%lld|%s",iot_core_id,device_key,cur_timestamp,"MD5");
        snprintf(token_temp, 100, "%s&%lld&%s%s",device_key,cur_timestamp,"MD5",device_secret);
        luat_crypto_md5_simple(token_temp, strlen(token_temp),crypto);
    }else if (!strcmp("SHA256", method)||!strcmp("sha256", method)) {
        sprintf(user_name, "thingidp@%s|%s|%lld|%s",iot_core_id,device_key,cur_timestamp,"SHA256");
        snprintf(token_temp, 100, "%s&%lld&%s%s",device_key,cur_timestamp,"SHA256",device_secret);
        luat_crypto_sha256_simple(token_temp, strlen(token_temp),crypto);
    }else{
        LLOGE("not support: %s",method);
        return -1;
    }
    str_tohex(crypto, strlen(crypto), password);
    luat_heap_free(token_temp);
}

static int l_iotauth_baidu(lua_State *L) {
    char user_name[100]={0};
    char password[200]={0};
    size_t len;
    const char* iot_core_id = luaL_checklstring(L, 1, &len);
    const char* device_key = luaL_checklstring(L, 2, &len);
    const char* device_secret = luaL_checklstring(L, 3, &len);
    const char* method = luaL_optlstring(L, 4, "MD5", &len);
    long long cur_timestamp = luaL_optinteger(L, 5,time(NULL) + 3600);
    baidu_token(iot_core_id,device_key,device_secret,method,cur_timestamp,user_name,password);
    lua_pushlstring(L, iot_core_id, strlen(iot_core_id));
    lua_pushlstring(L, user_name, strlen(user_name));
    lua_pushlstring(L, password, strlen(password));
    return 3;
}

static int l_iotauth_aws(lua_State *L) {
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_iotauth[] =
{
    { "aliyun" ,          ROREG_FUNC(l_iotauth_aliyun)},
    { "onenet" ,          ROREG_FUNC(l_iotauth_onenet)},
    { "iotda" ,           ROREG_FUNC(l_iotauth_iotda)},
    { "qcloud" ,          ROREG_FUNC(l_iotauth_qcloud)},
    { "tuya" ,            ROREG_FUNC(l_iotauth_tuya)},
    { "baidu" ,           ROREG_FUNC(l_iotauth_baidu)},
    { "aws" ,             ROREG_FUNC(l_iotauth_aws)},
	{ NULL,               ROREG_INT(0)}
};

LUAMOD_API int luaopen_iotauth( lua_State *L ) {
    luat_newlib2(L, reg_iotauth);
    return 1;
}
