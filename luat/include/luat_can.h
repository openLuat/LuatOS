#ifndef LUAT_CAN_H
#define LUAT_CAN_H
#include "luat_base.h"
/**
 * 不明确的部分参考SJA1000
 */

/**
 * @brief can总线工作模式
 */
typedef enum LUAT_CAN_WORK_MODE
{
    LUAT_CAN_WORK_MODE_NORMAL,/**< 正常收发 */
    LUAT_CAN_WORK_MODE_ONLY_LISTEN,/**< 监听模式，一般用于自适应时序 */
	LUAT_CAN_WORK_MODE_SELF_TEST,/**< 自收自发，仅用于测试 */
	LUAT_CAN_WORK_MODE_SLEEP,/**< 休眠模式，只能被接收唤醒 */
}LUAT_CAN_WORK_MODE_E;

/**
 * @brief can节点状态
 */
typedef enum LUAT_CAN_STATE
{
	LUAT_CAN_STOP, /**< 未工作状态 */
    LUAT_CAN_ACTIVE_ERROR,/**< 主动错误 */
    LUAT_CAN_PASSIVE_ERROR,/**< 被动错误 */
	LUAT_CAN_BUS_OFF,/**< 总线关闭 */
	LUAT_CAN_ONLY_LISTEN,/**< 监听状态 */
	LUAT_CAN_SELF_TEST,/**< 自测试状态 */
	LUAT_CAN_SLEEP, /**< 休眠状态 */

}LUAT_CAN_STATE_E;

/**
 * @brief can中断回调
 */
typedef enum LUAT_CAN_CB
{
    LUAT_CAN_CB_NEW_MSG,/**< 有新的消息到来 */
    LUAT_CAN_CB_TX_OK,/**< 发送成功 */
	LUAT_CAN_CB_TX_FAILED,/**< 发送失败 */
	LUAT_CAN_CB_ERROR_REPORT,/**< 总线错误报告 */
	LUAT_CAN_CB_STATE_CHANGE,/**< 总线状态变更 */
}LUAT_CAN_CB_E;

typedef struct
{
	uint32_t id:30;			//消息ID
	uint32_t is_extend:1;	//是否是扩展帧ID
	uint32_t RTR:1;			//是否是遥控帧
	uint8_t len;			//数据长度
	uint8_t data[8];		//数据
}luat_can_message_t;


/**
 * @brief 回调函数
 *
 */
typedef void (*luat_can_callback_t)(int can_id, LUAT_CAN_CB_E cb_type, void *cb_param);
/**
 * @brief can总线基础初始化
 *
 * @param can_id 总线序号，如果只有一条，填0，有多条的根据实际情况填写
 * @param rx_msg_cache_max 最大接收消息缓存数量，如果写0则是使用平台默认值
 * @return 0成功，其他失败
 */
int luat_can_base_init(uint8_t can_id, uint32_t rx_msg_cache_max);

/**
 * @brief 设置中断回调
 *
 * @param can_id 总线序号，如果只有一条，填0，有多条的根据实际情况填写
 * @param callback 回调函数
 * @return 0成功，其他失败
 */
int luat_can_set_callback(uint8_t can_id, luat_can_callback_t callback);

/**
 * @brief 设置can总线工作模式，一般情况下应设置LUAT_CAN_WORK_MODE_NORMAL
 * @param can_id 总线序号，如果只有一条，填0，有多条的根据实际情况填写
 * @param mode 工作模式
 * @return 0成功，其他失败
 */
int luat_can_set_work_mode(uint8_t can_id, LUAT_CAN_WORK_MODE_E mode);

/**
 * @brief 设置can总线时序
 * @param can_id 总线序号
 * @param bit_rate 期望波特率
 * @param PTS 传播时间段，范围1~8
 * @param PBS1 相位缓冲段1，范围1~8
 * @param PBS2 相位缓冲段2，范围2~8
 * @param SJW 同步补偿宽度值，范围1~4
 * @return 0成功，其他失败
 */
int luat_can_set_timing(uint8_t can_id, uint32_t bit_rate, uint8_t PTS, uint8_t PBS1, uint8_t PBS2, uint8_t SJW);

/**
 * @brief 设置can总线节点id，即只接收完全匹配node_id的消息
 * @param can_id 总线序号
 * @param node_id 节点id，标准格式11位或者扩展格式29位，根据is_extend决定，id值越小，优先级越高
 * @param is_extend_id 是否为扩展模式的ID号，写0标准格式11位，写1扩展格式29位
 * @return 0成功，其他失败
 */
int luat_can_set_node(uint8_t can_id, uint32_t node_id, uint8_t is_extend_id);

/**
 * @brief 设置can总线接收消息的过滤模式，当luat_can_set_node不能满足时使用才使用这个函数，过滤模式比较复杂，请参考SJA1000的Pelican模式下滤波
 * @param can_id 总线序号
 * @param is_dual_mode 是否为双过滤模式，0否，1是
 * @param ACR 接收代码寄存器，一共4个
 * @param AMR 接收屏蔽码，一共4个，对应bit写0表示需要检测，写1表示不检测，如果需要接收全部消息，AMR写0xffffffff
 * @return 0成功，其他失败
 */
int luat_can_set_filter(uint8_t can_id, uint8_t is_dual_mode, uint8_t ACR[4], uint8_t AMR[4]);

/**
 * @brief 往数据总线上发送一个消息，类型为数据帧或者遥控帧
 * @param can_id 总线序号
 * @param message_id 帧ID，标准格式11位或者扩展格式29位，根据is_extend_id决定
 * @param is_extend_id 是否是扩展帧ID，写0标准格式11位，写1扩展格式29位
 * @param is_RTR，是否是遥控帧，0不是，1是
 * @param need_ack，是否需要应答，0不需要，只发送1次，1需要，如果没有应答，会有发送失败回调
 * @param data_len，帧数据区长度0~8
 * @param data，帧数据
 * @return 0成功，其他失败
 */
int luat_can_tx_message(uint8_t can_id, uint32_t message_id, uint8_t is_extend_id, uint8_t is_RTR, uint8_t need_ack, uint8_t data_len, uint8_t *data);

/**
 * @brief 停止未完成的消息发送
 * @param can_id 总线序号
 * @return 0成功，其他失败，没有正在发送的消息也返回成功
 */
int luat_can_tx_stop(uint8_t can_id);

/**
 * @brief 从接收缓存里读出1条消息
 * @param can_id 总线序号
 * @param message 消息
 * @return >=0成功，其他失败，当没有消息时返回0
 */
int luat_can_rx_message_from_cache(uint8_t can_id, luat_can_message_t *message);

/**
 * @brief can总线复位，一般用于从总线关闭状态恢复成主动错误
 * @param can_id 总线序号
 * @return
 */
int luat_can_reset(uint8_t can_id);

/**
 * @brief 完全关闭can总线
 * @param can_id 总线序号
 * @return 0成功，其他失败
 */
int luat_can_close(uint8_t can_id);

/**
 * @brief 获取当前can状态
 * @param can_id 总线序号
 * @return >=0 成功并返回状态值，其他失败，状态值见LUAT_CAN_STATE_E
 */
int luat_can_get_state(uint8_t can_id);

#endif
