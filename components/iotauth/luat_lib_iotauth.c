
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
#include "luat_malloc.h"
#include "time.h"
#include "luat_str.h"
#include "luat_mcu.h"

#define LUAT_LOG_TAG "iotauth"
#include "luat_log.h"

#define CLIENT_ID_LEN 192
#define USER_NAME_LEN 192
#define PASSWORD_LEN 256

typedef struct iotauth_ctx
{
    char client_id[CLIENT_ID_LEN];
    char user_name[USER_NAME_LEN];
    char password[PASSWORD_LEN];
}iotauth_ctx_t;


static const unsigned char hexchars_s[] = "0123456789abcdef";
static const unsigned char hexchars_u[] = "0123456789ABCDEF";

static void str_tohex(const char* str, size_t str_len, char* hex,uint8_t uppercase) {
    unsigned char* hexchars = NULL;
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

static void aliyun_token(const char* product_key,const char* device_name,const char* device_secret,long long cur_timestamp,const char* method,uint8_t is_tls,char* client_id, char* user_name, char* password){
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

/*
阿里云物联网平台三元组生成
@api iotauth.aliyun(product_key, device_name,device_secret,method,cur_timestamp)
@string product_key
@string device_name
@string device_secret
@string method 加密方式,"hmacmd5" "hmacsha1" "hmacsha256" 可选,默认"hmacmd5"
@number cur_timestamp 可选 默认为 32472115200(2999-01-01 0:0:0)
@bool istls 是否TLS直连 true:TLS直连  false:TCP直连模式 默认TCP直连模式
@return string mqtt三元组 client_id
@return string mqtt三元组 user_name
@return string mqtt三元组 password
@usage
local client_id,user_name,password = iotauth.aliyun("123456789","abcdefg","Y877Bgo8X5owd3lcB5wWDjryNPoB")
print(client_id,user_name,password)
*/
static int l_iotauth_aliyun(lua_State *L) {
    iotauth_ctx_t ctx = {0};
    size_t len;
    uint8_t is_tls = 0;
    long long cur_timestamp = 32472115200;
    const char* product_key = luaL_checklstring(L, 1, &len);
    const char* device_name = luaL_checklstring(L, 2, &len);
    const char* device_secret = luaL_checklstring(L, 3, &len);
    const char* method = luaL_optlstring(L, 4, "hmacmd5", &len);
    if (lua_type(L, (5)) == LUA_TNUMBER){
        cur_timestamp = luaL_checkinteger(L, 5);
    }
    if (lua_isboolean(L, 6)){
		is_tls = lua_toboolean(L, 6);
	}
    aliyun_token(product_key,device_name,device_secret,cur_timestamp,method,is_tls,ctx.client_id,ctx.user_name,ctx.password);
    lua_pushlstring(L, ctx.client_id, strlen(ctx.client_id));
    lua_pushlstring(L, ctx.user_name, strlen(ctx.user_name));
    lua_pushlstring(L, ctx.password, strlen(ctx.password));
    return 3;
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

static void onenet_token(const char* product_id,const char* device_name,const char* device_secret,long long cur_timestamp,char * method,char * version,char *token){
    size_t  declen = 0, enclen =  0;
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
    }else if (!strcmp("sha1", method)||!strcmp("SHA1", method)) {
        luat_crypto_hmac_sha1_simple(StringForSignature, strlen(StringForSignature),plaintext, declen,  hmac);
    }else if (!strcmp("sha256", method)||!strcmp("SHA256", method)) {
        luat_crypto_hmac_sha256_simple(StringForSignature, strlen(StringForSignature),plaintext, declen,  hmac);
    }else{
        LLOGE("not support: %s",method);
        return;
    }
    luat_str_base64_encode((unsigned char *)sign.sign, sizeof(sign.sign), &enclen, (const unsigned char * )hmac, strlen(hmac));
    url_encoding_for_token(&sign,token);
}

/*
中国移动物联网平台三元组生成
@api iotauth.onenet(produt_id, device_name,key,method,cur_timestamp,version)
@string produt_id
@string device_name
@string key
@string method 加密方式,"md5" "sha1" "sha256" 可选,默认"md5"
@number cur_timestamp 可选 默认为 32472115200(2999-01-01 0:0:0)
@string version 可选 默认"2018-10-31"
@return string mqtt三元组 client_id
@return string mqtt三元组 user_name
@return string mqtt三元组 password
@usage
local client_id,user_name,password = iotauth.onenet("123456789","test","KuF3NT/jUBJ62LNBB/A8XZA9CqS3Cu79B/ABmfA1UCw=")
print(client_id,user_name,password)
*/
static int l_iotauth_onenet(lua_State *L) {
    char password[PASSWORD_LEN] = {0};
    size_t len;
    long long cur_timestamp = 32472115200;
    const char* produt_id = luaL_checklstring(L, 1, &len);
    const char* device_name = luaL_checklstring(L, 2, &len);
    const char* key = luaL_checklstring(L, 3, &len);
    const char* method = luaL_optlstring(L, 4, "md5", &len);
    if (lua_type(L, (5)) == LUA_TNUMBER){
        cur_timestamp = luaL_checkinteger(L, 5);
    }
    const char* version = luaL_optlstring(L, 6, "2018-10-31", &len);
    onenet_token(produt_id,device_name,key,cur_timestamp,method,version, password);
    lua_pushlstring(L, device_name, strlen(device_name));
    lua_pushlstring(L, produt_id, strlen(produt_id));
    lua_pushlstring(L, password, strlen(password));
    return 3;
}

static void iotda_token(const char* device_id,const char* device_secret,long long cur_timestamp,int ins_timestamp,char* client_id,const char* password){
    char hmac[64] = {0};
    char timestamp[12] = {0};
    struct tm *timeinfo = localtime( &cur_timestamp );
    if(snprintf_(timestamp, 12, "%04d%02d%02d%02d", (timeinfo->tm_year)+1900,timeinfo->tm_mon+1,timeinfo->tm_mday,timeinfo->tm_hour)<0){
        return;
    }
    snprintf_(client_id, CLIENT_ID_LEN, "%s_0_%d_%s", device_id,ins_timestamp,timestamp);
    luat_crypto_hmac_sha256_simple(device_secret, strlen(device_secret),timestamp, strlen(timestamp), hmac);
    str_tohex(hmac, 32, password,0);
}

/*
华为物联网平台三元组生成
@api iotauth.iotda(device_id,device_secret,cur_timestamp)
@string device_id
@string device_secret
@number cur_timestamp 可选 如不填则不校验时间戳
@return string mqtt三元组 client_id
@return string mqtt三元组 user_name
@return string mqtt三元组 password
@usage
local client_id,user_name,password = iotauth.iotda("6203cc94c7fb24029b110408_88888888","123456789")
print(client_id,user_name,password)
*/
static int l_iotauth_iotda(lua_State *L) {
    char client_id[CLIENT_ID_LEN] = {0};
    char password[PASSWORD_LEN] = {0};
    size_t len = 0;
    long long cur_timestamp = 0;
    int ins_timestamp = 0;
    const char* device_id = luaL_checklstring(L, 1, &len);
    const char* device_secret = luaL_checklstring(L, 2, &len);
    if (lua_type(L, (3)) == LUA_TNUMBER){
        cur_timestamp = luaL_checkinteger(L, 3);
        ins_timestamp = 1;
    }
    iotda_token(device_id,device_secret,cur_timestamp,ins_timestamp,client_id,password);
    lua_pushlstring(L, client_id, strlen(client_id));
    lua_pushlstring(L, device_id, strlen(device_id));
    lua_pushlstring(L, password, strlen(password));
    return 3;
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

static void qcloud_token(const char* product_id,const char* device_name,const char* device_secret,long long cur_timestamp,const char* method,const char* sdk_appid,char* username,char* password){
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

/*
腾讯联网平台三元组生成
@api iotauth.qcloud(product_id, device_name,device_secret,method,cur_timestamp,sdk_appid)
@string 产品id,创建项目后可以查看到,类似于LD8S5J1L07
@string 设备名称,例如设备的imei号
@string 设备密钥,创建设备后,查看设备详情可得到
@string method 加密方式,"sha1" "sha256" 可选,默认"sha256"
@number cur_timestamp 可选 默认为 32472115200(2999-01-01 0:0:0)
@string sdk_appid 可选 默认为"12010126"
@return string mqtt三元组 client_id
@return string mqtt三元组 user_name
@return string mqtt三元组 password
@usage
local client_id,user_name,password = iotauth.qcloud("LD8S5J1L07","test","acyv3QDJrRa0fW5UE58KnQ==")
print(client_id,user_name,password)
*/
static int l_iotauth_qcloud(lua_State *L) {
    iotauth_ctx_t ctx = {0};
    size_t len = 0;
    long long cur_timestamp = 32472115200;
    const char* product_id = luaL_checklstring(L, 1, &len);
    const char* device_name = luaL_checklstring(L, 2, &len);
    const char* device_secret = luaL_checklstring(L, 3, &len);
    const char* method = luaL_optlstring(L, 4, "sha256", &len);
    if (lua_type(L, (5)) == LUA_TNUMBER){
        cur_timestamp = luaL_checkinteger(L, 5);
    }
    const char* sdk_appid = luaL_optlstring(L, 6, "12010126", &len);
    qcloud_token(product_id, device_name,device_secret,cur_timestamp,method,sdk_appid,ctx.user_name,ctx.password);
    snprintf_(ctx.client_id, CLIENT_ID_LEN,"%s%s", product_id,device_name);
    lua_pushlstring(L, ctx.client_id, strlen(ctx.client_id));
    lua_pushlstring(L, ctx.user_name, strlen(ctx.user_name));
    lua_pushlstring(L, ctx.password, strlen(ctx.password));
    return 3;
}

static void tuya_token(const char* device_id,const char* device_secret,long long cur_timestamp,const char* password){
    char hmac[64] = {0};
    char token_temp[100]  = {0};
    memset(token_temp, 0, 100);
    snprintf_(token_temp, 100, "deviceId=%s,timestamp=%lld,secureMode=1,accessType=1", device_id, cur_timestamp);
    luat_crypto_hmac_sha256_simple(token_temp, strlen(token_temp),device_secret, strlen(device_secret), hmac);
    str_tohex(hmac, 32, password,0);
}

/*
涂鸦联网平台三元组生成
@api iotauth.tuya(device_id,device_secret,cur_timestamp)
@string device_id
@string device_secret
@number cur_timestamp 可选 默认为 32472115200(2999-01-01 0:0:0)
@return string mqtt三元组 client_id
@return string mqtt三元组 user_name
@return string mqtt三元组 password
@usage
local client_id,user_name,password = iotauth.tuya("6c95875d0f5ba69607nzfl","fb803786602df760")
print(client_id,user_name,password)
*/
static int l_iotauth_tuya(lua_State *L) {
    iotauth_ctx_t ctx = {0};
    size_t len = 0;
    long long cur_timestamp = 32472115200;
    const char* device_id = luaL_checklstring(L, 1, &len);
    const char* device_secret = luaL_checklstring(L, 2, &len);
    if (lua_type(L, (3)) == LUA_TNUMBER){
        cur_timestamp = luaL_checkinteger(L, 3);
    }
    tuya_token(device_id,device_secret,cur_timestamp,ctx.password);
    snprintf_(ctx.client_id, CLIENT_ID_LEN, "tuyalink_%s", device_id);
    snprintf_(ctx.user_name, USER_NAME_LEN, "%s|signMethod=hmacSha256,timestamp=%lld,secureMode=1,accessType=1", device_id,cur_timestamp);
    lua_pushlstring(L, ctx.client_id, strlen(ctx.client_id));
    lua_pushlstring(L, ctx.user_name, strlen(ctx.user_name));
    lua_pushlstring(L, ctx.password, strlen(ctx.password));
    return 3;
}

static void baidu_token(const char* iot_core_id,const char* device_key,const char* device_secret,const char* method,long long cur_timestamp,char* username,char* password){
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

/*
百度物联网平台三元组生成
@api iotauth.baidu(iot_core_id, device_key,device_secret,method,cur_timestamp)
@string iot_core_id
@string device_key
@string device_secret
@string method 加密方式,"MD5" "SHA256" 可选,默认"MD5"
@number cur_timestamp 可选 如不填则不校验时间戳
@return string mqtt三元组 client_id
@return string mqtt三元组 user_name
@return string mqtt三元组 password
@usage
local client_id,user_name,password = iotauth.baidu("abcd123","mydevice","ImSeCrEt0I1M2jkl")
print(client_id,user_name,password)
*/
static int l_iotauth_baidu(lua_State *L) {
    char user_name[USER_NAME_LEN] = {0};
    char password[PASSWORD_LEN] = {0};
    size_t len = 0;
    const char* iot_core_id = luaL_checklstring(L, 1, &len);
    const char* device_key = luaL_checklstring(L, 2, &len);
    const char* device_secret = luaL_checklstring(L, 3, &len);
    const char* method = luaL_optlstring(L, 4, "MD5", &len);
    long long cur_timestamp = luaL_optinteger(L, 5, 0);
    baidu_token(iot_core_id,device_key,device_secret,method,cur_timestamp,user_name,password);
    lua_pushlstring(L, iot_core_id, strlen(iot_core_id));
    lua_pushlstring(L, user_name, strlen(user_name));
    lua_pushlstring(L, password, strlen(password));
    return 3;
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
	{ NULL,               ROREG_INT(0)}
};

LUAMOD_API int luaopen_iotauth( lua_State *L ) {
    luat_newlib2(L, reg_iotauth);
    return 1;
}
