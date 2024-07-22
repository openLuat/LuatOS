#ifndef LUAT_LCD
#define LUAT_LCD

#define CLIENT_ID_LEN 192
#define USER_NAME_LEN 192
#define PASSWORD_LEN 256

typedef struct iotauth_ctx
{
    char client_id[CLIENT_ID_LEN];
    char user_name[USER_NAME_LEN];
    char password[PASSWORD_LEN];
}iotauth_ctx_t;

typedef struct iotauth_onenet {
    const char* product_id;
    const char* device_name;
    const char* device_secret;
    long long cur_timestamp;
    const char* method;
    const char* version;
    const char* res;
}iotauth_onenet_t;

/**
 *@brief 阿里云获取三元组信息
 *@param ctx iotauth_ctx_t 获取的三元组信息
 *@param product_key 产品密钥
 *@param device_name 设备名称
 *@param device_secret 设备秘钥
 *@param cur_timestamp 时间戳
 *@param method 加密方式
 *@param is_tls 是否 tls
 *@return 成功为0，其他值失败
 */
int luat_aliyun_token(iotauth_ctx_t* ctx,const char* product_key,const char* device_name,const char* device_secret,long long cur_timestamp,const char* method,uint8_t is_tls);
/**
 *@brief onenet获取三元组信息
 *@param ctx iotauth_ctx_t 获取的三元组信息
 *@param onenet onenet传入结构体信息
 *@return 成功为0，其他值失败
 */
int luat_onenet_token(iotauth_ctx_t* ctx,const iotauth_onenet_t* onenet);
/**
 *@brief 华为物联网获取三元组信息
 *@param ctx iotauth_ctx_t 获取的三元组信息
 *@param device_id 设备id
 *@param device_secret 设备秘钥
 *@param cur_timestamp 时间戳
 *@param ins_timestamp 是否校验时间戳
 *@return 成功为0，其他值失败
 */
int luat_iotda_token(iotauth_ctx_t* ctx,const char* device_id,const char* device_secret,long long cur_timestamp,int ins_timestamp);
/**
 *@brief 腾讯获取三元组信息
 *@param ctx iotauth_ctx_t 获取的三元组信息
 *@param product_id 产品id
 *@param device_name 设备名称
 *@param device_secret 设备秘钥
 *@param cur_timestamp 时间戳
 *@param method 加密方式
 *@param sdk_appid appid
 *@return 成功为0，其他值失败
 */
int luat_qcloud_token(iotauth_ctx_t* ctx,const char* product_id,const char* device_name,const char* device_secret,long long cur_timestamp,const char* method,const char* sdk_appid);
/**
 *@brief 涂鸦获取三元组信息
 *@param ctx iotauth_ctx_t 获取的三元组信息
 *@param device_id 设备id
 *@param device_secret 设备秘钥
 *@param cur_timestamp 时间戳
 *@return 成功为0，其他值失败
 */
int luat_tuya_token(iotauth_ctx_t* ctx,const char* device_id,const char* device_secret,long long cur_timestamp);
/**
 *@brief 腾讯获取三元组信息
 *@param ctx iotauth_ctx_t 获取的三元组信息
 *@param iot_core_id iot_core_idid
 *@param device_key 设备key
 *@param device_secret 设备秘钥
 *@param method 加密方式
 *@param cur_timestamp 时间戳
 *@return 成功为0，其他值失败
 */
int luat_baidu_token(iotauth_ctx_t* ctx,const char* iot_core_id,const char* device_key,const char* device_secret,const char* method,long long cur_timestamp);

#endif



















