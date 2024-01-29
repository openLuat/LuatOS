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

void luat_aliyun_token(const char* product_key,const char* device_name,const char* device_secret,long long cur_timestamp,const char* method,uint8_t is_tls,char* client_id, char* user_name, char* password);
int luat_onenet_token(const iotauth_onenet_t* onenet, char* token);
void luat_iotda_token(const char* device_id,const char* device_secret,long long cur_timestamp,int ins_timestamp,char* client_id,const char* password);
void luat_qcloud_token(const char* product_id,const char* device_name,const char* device_secret,long long cur_timestamp,const char* method,const char* sdk_appid,char* username,char* password);
void luat_tuya_token(const char* device_id,const char* device_secret,long long cur_timestamp,const char* password);
void luat_baidu_token(const char* iot_core_id,const char* device_key,const char* device_secret,const char* method,long long cur_timestamp,char* username,char* password);

#endif



















