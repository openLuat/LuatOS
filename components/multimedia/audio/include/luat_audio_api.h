#ifndef __LUAT_AUDIO_API__
#define __LUAT_AUDIO_API__

/**
 * @file luat_audio_api.h
 * @brief LuatOS 音频框架公共API头文件
 * 
 * 提供音频框架的初始化和核心接口声明。
 * 
 * @defgroup luat_audio_api 音频公共API
 * @ingroup audio
 * @{
 */

#include "luat_audio_define.h"
#include "luat_audio_channel.h"
#include "luat_audio_data_codec.h"
#include "luat_audio_driver.h"
#include "luat_audio_request.h"

/**
 * @brief 初始化音频框架基础模块
 * 
 * 此函数负责初始化音频框架的核心组件，包括通道管理、编解码器注册等。
 * 应在系统启动时调用一次。
 */
void luat_audio_base_init(void);

/**
 * @brief 注册音频驱动
 * 
 * 此函数用于向音频框架注册一个音频驱动，注册后该驱动可被音频通道使用。第一个注册的驱动会被默认使用。
 * 
 * @param opts 音频驱动操作接口结构体指针，包含驱动的具体实现函数
 * @param probe 音频驱动匹配结构，用于描述驱动的匹配条件
 * @param driver_data 驱动私有数据指针，用于存储驱动的私有数据
 * @return 0 表示成功，其他值表示失败
 */
int luat_audio_driver_register(const luat_audio_driver_opts_t *opts, struct luat_audio_driver_probe probe, void *driver_data);

/**
 * @brief 探测音频驱动
 * 
 * 此函数用于探测音频框架是否支持指定音频驱动。
 * 
 * @param probe 音频驱动匹配结构，用于描述驱动的匹配条件，如果为NULL，则返回第一个注册的驱动控制器。
 * @return 驱动控制器指针，成功返回非NULL，失败返回NULL
 */
luat_audio_driver_ctrl_t *luat_audio_driver_probe(struct luat_audio_driver_probe *probe);

/**
 * @brief 初始化音频请求
 * 
 * 此函数用于初始化音频请求结构体，为后续的音频处理做准备。
 * 
 * @param req 音频请求结构体指针，包含请求的详细信息
 * @return 0 表示成功，其他值表示失败
 */
int luat_audio_request_init(luat_audio_request_block_t *req);
/**
 * @brief 释放音频请求结构体指针
 * 
 * 此函数用于释放音频请求结构体指针，释放请求资源。
 * 
 * @param req 音频请求结构体指针，包含请求的详细信息
 * @return 0 表示成功，其他值表示失败
 */
int luat_audio_request_deinit(luat_audio_request_block_t *req);
/**
 * @brief 提交音频请求
 * 
 * 此函数用于提交音频请求，请求音频框架处理音频数据。
 * 
 * @param req 音频请求结构体指针，包含请求的详细信息
 * @return 0 表示成功，其他值表示失败
 */
int luat_audio_request(luat_audio_request_block_t *req);

/**
 * @brief 取消音频请求
 * 
 * 此函数用于取消已提交的音频请求，不释放请求资源。
 * 
 * @param req 音频请求结构体指针，包含请求的详细信息
 * @return 0 表示成功，其他值表示失败
 */
int luat_audio_request_cancel(luat_audio_request_block_t *req);

void luat_audio_driver_event_callback(uint32_t event, uint8_t *rx_data, uint32_t param, struct luat_audio_driver_ctrl *ctrl);
#endif

/** @} */
