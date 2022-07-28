// IoT鉴权函数, 用于生成各种云平台的参数

#include "luat_base.h"
#include "luat_crypto.h"

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

int onenet_creat_token_init(onenet_msg_t* msg, long long time,char * method,char * version,char *token){
    int declen = 0, enclen =  0;
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
    printf("StringForSignature: %s\n",StringForSignature);
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
    // for (size_t i = 0; i < 64; i++){
    //     printf("hmac[%d]: 0x%02x\n",i,hmac[i]);
    // }
    luat_str_base64_encode((unsigned char *)sign.sign, sizeof(sign.sign), &enclen, (const unsigned char * )hmac, strlen(hmac));
    return url_encoding_for_token(&sign,token);
}

static int l_iotauth_aliyun(lua_State *L) {
    return 0;
}

static int l_iotauth_onenet(lua_State *L) {
    char authorization_buf[200]={0};
    int authorization_buf_len;
    size_t len;
    onenet_msg_t onenet;
    onenet.device_name = luaL_checklstring(L, 1, &len);
    onenet.produt_id = luaL_checklstring(L, 2, &len);
    onenet.key = luaL_checklstring(L, 3, &len);
    onenet.method = luaL_optlstring(L, 4, "sha256", &len);
    onenet.time = luaL_optinteger(L, 5,time() + 3600);
    onenet.version = luaL_optlstring(L, 6, "2018-10-31", &len);
    len = onenet_creat_token_init(&onenet, onenet.time,onenet.method,onenet.version,authorization_buf);
    lua_pushlstring(L, authorization_buf, len);
    return 1;
}

static int l_iotauth_iotda(lua_State *L) {
    return 0;
}

static int l_iotauth_qcloud(lua_State *L) {
    return 0;
}

static int l_iotauth_tuya(lua_State *L) {
    return 0;
}

static int l_iotauth_baidu(lua_State *L) {
    return 0;
}

static int l_iotauth_aws(lua_State *L) {
    return 0;
}

static int l_iotauth_test(lua_State *L) {
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
    { "test" ,            ROREG_FUNC(l_iotauth_test)},
	{ NULL,               ROREG_INT(0)}
};

LUAMOD_API int luaopen_iotauth( lua_State *L ) {
    luat_newlib2(L, reg_iotauth);
    return 1;
}
