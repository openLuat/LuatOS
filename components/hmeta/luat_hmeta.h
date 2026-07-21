#ifndef LUAT_HMETA_H
#define LUAT_HMETA_H


// 获取模块的设备类型, 原始需求是区分Air780E和Air600E
int luat_hmeta_model_name(char* buff);
// 获取硬件版本号, 例如A11, A14
int luat_hmeta_hwversion(char* buff);

// 获取芯片组型号, 原始型号, 传入的buff最少要8字节空间
int luat_hmeta_chip(char* buff);


// 获取模组muid, 传入的buff最少要34字节空间
int luat_hmeta_muid(char* buf, size_t buf_len);

// 获取模组的识别id, 传入的buff最少要34字节空间
int luat_hmeta_devid(char* buf, size_t buf_len);

#endif
