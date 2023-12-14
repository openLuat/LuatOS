
/*
@module  iotauth
@summary IoT鉴权库, 用于生成各种云平台的参数
@version core V0007
@date    2022.08.06
@demo iotauth
@tag LUAT_USE_IOTAUTH
*/
#include "luat_base.h"
#include "luat_iotauth.h"

#define LUAT_LOG_TAG "iotauth"
#include "luat_log.h"

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
    luat_aliyun_token(product_key,device_name,device_secret,cur_timestamp,method,is_tls,ctx.client_id,ctx.user_name,ctx.password);
    lua_pushlstring(L, ctx.client_id, strlen(ctx.client_id));
    lua_pushlstring(L, ctx.user_name, strlen(ctx.user_name));
    lua_pushlstring(L, ctx.password, strlen(ctx.password));
    return 3;
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
    luat_onenet_token(produt_id,device_name,key,cur_timestamp,method,version, password);
    lua_pushlstring(L, device_name, strlen(device_name));
    lua_pushlstring(L, produt_id, strlen(produt_id));
    lua_pushlstring(L, password, strlen(password));
    return 3;
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
    long long cur_timestamp = 32472115200;
    int ins_timestamp = 0;
    const char* device_id = luaL_checklstring(L, 1, &len);
    const char* device_secret = luaL_checklstring(L, 2, &len);
    if (lua_type(L, (3)) == LUA_TNUMBER){
        cur_timestamp = luaL_checkinteger(L, 3);
        ins_timestamp = 1;
    }
    luat_iotda_token(device_id,device_secret,cur_timestamp,ins_timestamp,client_id,password);
    lua_pushlstring(L, client_id, strlen(client_id));
    lua_pushlstring(L, device_id, strlen(device_id));
    lua_pushlstring(L, password, strlen(password));
    return 3;
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
    luat_qcloud_token(product_id, device_name,device_secret,cur_timestamp,method,sdk_appid,ctx.user_name,ctx.password);
    snprintf_(ctx.client_id, CLIENT_ID_LEN,"%s%s", product_id,device_name);
    lua_pushlstring(L, ctx.client_id, strlen(ctx.client_id));
    lua_pushlstring(L, ctx.user_name, strlen(ctx.user_name));
    lua_pushlstring(L, ctx.password, strlen(ctx.password));
    return 3;
}
/*
涂鸦联网平台三元组生成
@api iotauth.tuya(device_id,device_secret,cur_timestamp)
@string device_id
@string device_secret
@number cur_timestamp 可选 默认7258089600(2200-01-01 0:0:0)
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
    long long cur_timestamp = 7258089600;
    const char* device_id = luaL_checklstring(L, 1, &len);
    const char* device_secret = luaL_checklstring(L, 2, &len);
    if (lua_type(L, (3)) == LUA_TNUMBER){
        cur_timestamp = luaL_checkinteger(L, 3);
    }
    luat_tuya_token(device_id,device_secret,cur_timestamp,ctx.password);
    snprintf_(ctx.client_id, CLIENT_ID_LEN, "tuyalink_%s", device_id);
    snprintf_(ctx.user_name, USER_NAME_LEN, "%s|signMethod=hmacSha256,timestamp=%lld,secureMode=1,accessType=1", device_id,cur_timestamp);
    lua_pushlstring(L, ctx.client_id, strlen(ctx.client_id));
    lua_pushlstring(L, ctx.user_name, strlen(ctx.user_name));
    lua_pushlstring(L, ctx.password, strlen(ctx.password));
    return 3;
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
    luat_baidu_token(iot_core_id,device_key,device_secret,method,cur_timestamp,user_name,password);
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
