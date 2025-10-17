/*
 * Copyright (c) 2022 OpenLuat & AirM2M
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#ifndef __LUAT_MOBILE_H__
#define __LUAT_MOBILE_H__

#include "luat_base.h"
/**
 * @defgroup luatos_mobile 移动网络相关接口
 * @{
 */
/**
 * @brief 获取IMEI
 * 
 * @param sim_id sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param buff[OUT] IMEI数据
 * @param buf_len 用户传入缓存的大小，如果底层数据量大于buf_len，只会传出buf_len大小的数据
 * @return int <= 0错误 >0实际传出的大小
 */
int luat_mobile_get_imei(int sim_id, char* buff, size_t buf_len);

/**
 * @brief 获取SN，如果用户没有调用luat_mobile_set_sn接口写过SN，默认值为空
 * 
 * @param buff[OUT] SN数据
 * @param buf_len 用户传入缓存的大小，Air780EXXX平台底层支持的最大长度为32字节，如果底层数据量大于buf_len，只会传出buf_len大小的数据
 * @return int <= 0错误 >0实际传出的大小
 */
int luat_mobile_get_sn(char* buff, size_t buf_len);

/**
 * @brief 设置SN
 * 
 * @param buff SN数据，必须是ascii值大于等于0x21小于等于0x7e的可见ascii字符
 * @param buf_len SN数据长度；Air780EXXX平台底层支持的最大长度为32字节，如果buf_len大于32，只会保存前32字节的数据
 * @return int = 0成功， = -1失败
 */
int luat_mobile_set_sn(char* buff, uint8_t buf_len);

/**
 * @brief 获取MUID，并不一定存在
 * 
 * @param buff[OUT] MUID数据
 * @param buf_len 用户传入缓存的大小，如果底层数据量大于buf_len，只会传出buf_len大小的数据
 * @return int <= 0错误 >0实际传出的大小
 */
int luat_mobile_get_muid(char* buff, size_t buf_len);

/**
 * @brief 获取SIM卡的ICCID
 * 
 * @param sim_id sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param buff[OUT] ICCID数据
 * @param buf_len 用户传入缓存的大小，如果底层数据量大于buf_len，只会传出buf_len大小的数据
 * @return int <= 0错误 >0实际传出的大小
 */
int luat_mobile_get_iccid(int sim_id, char* buff, size_t buf_len);

/**
 * @brief 获取SIM卡的IMSI
 * 
 * @param sim_id sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param buff[OUT] IMSI数据
 * @param buf_len 用户传入缓存的大小，如果底层数据量大于buf_len，只会传出buf_len大小的数据
 * @return int <= 0错误 >0实际传出的大小
 */
int luat_mobile_get_imsi(int sim_id, char* buff, size_t buf_len);

/**
 * @brief 当前使用的SIM卡的手机号，注意，只有写入了手机号才能读出，因此有可能读出来是空的
 *
 * @param sim_id sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param buff[OUT] sim_number数据
 * @param buf_len 用户传入缓存的大小，如果底层数据量大于buf_len，只会传出buf_len大小的数据
 * @return int <= 0错误 >0实际传出的大小
 */
int luat_mobile_get_sim_number(int sim_id, char* buff, size_t buf_len);

/**
 * @brief 当前使用的SIM卡的位置，并不一定支持
 *
 * @param id[OUT] sim位置，对于双卡双待的设备，输出0或者1，其他设备输出0
 * @return int =0成功，其他失败
 */
int luat_mobile_get_sim_id(int *id);

/**
 * @brief 改变使用的SIM卡的位置，并不一定支持
 * 
 * @param id sim位置，对于双卡的设备，选0或者1，其他为自动选择模式。非双卡的设备不支持
 * @return int =0成功，其他失败
 */
int luat_mobile_set_sim_id(int id);

typedef enum LUAT_MOBILE_SIM_PIN_OP
{
    LUAT_SIM_PIN_VERIFY = 0,       /* verify pin code */
	LUAT_SIM_PIN_CHANGE,       /* change pin code */
	LUAT_SIM_PIN_ENABLE,       /* enable the pin1 state for verification */
	LUAT_SIM_PIN_DISABLE,      /* disable the pin1 state */
	LUAT_SIM_PIN_UNBLOCK,      /* unblock pin code */
//	LUAT_SIM_PIN_QUERY,        /* query pin1 state, enable or disable */
}LUAT_MOBILE_SIM_PIN_OP_E;

/**
 * @brief 对SIM卡的pin码做操作
 *
 * @param id sim位置，对于双卡的设备，选0或者1，其他为自动选择模式，但是0和1的优先级是一致的。非双卡的设备不支持
 * @param operation 操作码，见LUAT_MOBILE_SIM_PIN_OP_E
 * @param pin1 旧的pin码，或者验证的pin码，解锁pin码时的PUK，参考手机操作
 * @param pin2 更换pin码操作时的新的pin码，解锁pin码时的新PIN，参考手机操作
 * @return int =0成功，其他失败
 */
int luat_mobile_set_sim_pin(int id, uint8_t operation, char pin1[9], char pin2[9]);

/**
 * @brief 检查SIM卡是否准备好
 *
 * @param id sim位置，对于双卡双待的设备，选0或者1，其他设备忽略
 * @return =1准备好，其他未准备好，或者SIM卡不在位
 */
uint8_t luat_mobile_get_sim_ready(int id);

/**
 * @brief 在自动选择模式时，开机后优先用sim0
 *
 */
void luat_mobile_set_sim_detect_sim0_first(void);

/**
 * @brief 设置默认PDN激活时是否要IPV6网络，现在默认情况下不开
 * @param onoff 1开 0关
 * @return uint8_t 1开 0关
 */
void luat_mobile_set_default_pdn_ipv6(uint8_t onoff);
/**
 * @brief 设置默认PDN激活时是否只支持IPV6网络，现在默认情况下不开
 * @param onoff 1开 0关
 * @return uint8_t 1开 0关
 */
void luat_mobile_set_default_pdn_only_ipv6(uint8_t onoff);
/**
 * @brief 返回默认PDN激活时是否要IPV6网络
 * @return uint8_t 1开 0关
 */
uint8_t luat_mobile_get_default_pdn_ipv6(void);


/**
 * @brief 获取配置的apn name，并不一定支持
 * 
 * @param sim_id sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param cid cid位置 1~6
 * @param buff[OUT] apn name
 * @param buf_len 用户传入缓存的大小，如果底层数据量大于buf_len，只会传出buf_len大小的数据
 * @return int <= 0错误 >0实际传出的大小
 */
int luat_mobile_get_apn(int sim_id, int cid, char* buff, size_t buf_len);

/**
 * @brief 用户控制APN激活过程。只有使用了本函数后，才能通过手动激活用户的APN并加装网卡。只有Air780EXXX支持，不建议使用
 */
void luat_mobile_user_ctrl_apn(void);
/**
 * @brief 解除用户控制APN激活过程
 */
void luat_mobile_user_ctrl_apn_stop(void);
/**
 * @brief 手动设置APN激活所需的最小信息，如果需要更详细的设置，可以自行修改本函数。只有Air780EXXX支持，不建议使用
 *
 * @param sim_id sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param cid cid位置 2~6
 * @param type 激活类型 1 IPV4 2 IPV6 3 IPV4V6
 * @param apn_name apn name
 * @param name_len apn name 长度
 * @return int <= 0错误 >0实际传出的大小
 */
int luat_mobile_set_apn_base_info(int sim_id, int cid, uint8_t type, uint8_t* apn_name, uint8_t name_len);


/**
 * @brief 手动设置APN激活所需的加密信息，如果需要更详细的设置，可以自行修改本函数。大部分情况下不需要加密信息，定向卡可能需要。只有Air780EXXX支持，不建议使用
 *
 * @param sim_id sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param cid cid位置 2~6
 * @param protocol 加密协议 1~3，0和0xff表示不需要
 * @param user_name 用户名
 * @param user_name_len 用户名长度
 * @param password 密码
 * @param password_len 密码长度
 * @return int <= 0错误 >0实际传出的大小
 */
int luat_mobile_set_apn_auth_info(int sim_id, int cid, uint8_t protocol, uint8_t *user_name, uint8_t user_name_len, uint8_t *password, uint8_t password_len);

/**
 * @brief 手动激活/去激活APN。只有Air780EXXX支持，不建议使用
 *
 * @param sim_id sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param cid cid位置 2~6
 * @param state 1激活 0去激活
 * @return int <= 0错误 >0实际传出的大小
 */
int luat_mobile_active_apn(int sim_id, int cid, uint8_t state);

/**
 * @brief 手动激活网卡。只有Air780EXXX支持，不建议使用
 *
 * @param sim_id sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param cid cid位置 2~6
 * @return int <= 0错误 >0实际传出的大小
 */
int luat_mobile_active_netif(int sim_id, int cid);

/**
 * @brief 用户设置APN的基本信息，并且自动激活，注意不能和上述手动操作APN的API共用，专网卡如果不能用公网apn激活默认承载的必须用这个，推荐使用
 *
 * @param sim_id sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param cid cid位置 1~6
 * @param ip_type 激活类型 1 IPV4 2 IPV6 3 IPV4V6
 * @param protocol 加密协议 1~3，0和0xff表示不需要
 * @param apn_name apn name，如果留空则使用默认APN
 * @param apn_name_len apn name 长度
 * @param user_name 用户名
 * @param user_name_len 用户名长度
 * @param password 密码
 * @param password_len 密码长度
 * @return 无
 */
void luat_mobile_user_apn_auto_active(int sim_id, uint8_t cid,
		uint8_t ip_type,
		uint8_t protocol_type,
		uint8_t *apn_name, uint8_t apn_name_len,
		uint8_t *user, uint8_t user_len,
		uint8_t *password, uint8_t password_len);

/**
 * @brief 获取默认CID的apn name，并不一定支持
 * 
 * @param sim_id sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param buff[OUT] apn name 
 * @param buf_len 用户传入缓存的大小，如果底层数据量大于buf_len，只会传出buf_len大小的数据
 * @return int <= 0错误 >0实际传出的大小
 */
int luat_mobile_get_default_apn(int sim_id, char* buff, size_t buf_len);

/**
 * @brief 删除定义好的apn
 *
 * @param sim_id sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param cid cid位置 1~6
 * @param is_dedicated 是否是专用的,不清楚的写0
 * @return int =0成功，其他失败
 */
int luat_mobile_del_apn(int sim_id, uint8_t cid, uint8_t is_dedicated);

/**
 * @brief 进出飞行模式
 * 
 * @param index sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param mode 飞行模式，1进入，0退出
 * @return int =0成功，其他失败
 */
int luat_mobile_set_flymode(int index, int mode);

/**
 * @brief 飞行模式当前状态
 * 
 * @param index sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @return int <0 异常 =0飞行模式 =1正常工作 =4射频关闭
 */
int luat_mobile_get_flymode(int index);

#if (!defined __LUATOS__) || ((defined __LUATOS__) && (defined LUAT_USE_LWIP))
#include "lwip/opt.h"
#include "lwip/netif.h"
#include "lwip/inet.h"

/**
 * @brief 获取已激活承载分配的本地ip地址
 * 
 * @param sim_id sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param cid cid位置 1~6，没有使用专网APN的话，就是用1
 * @param ip_v4, ipv4的IP地址
 * @param ip_v6, ipv6的IP地址
 * @return int =0成功，其他失败
 */
int luat_mobile_get_local_ip(int sim_id, int cid, ip_addr_t *ip_v4, ip_addr_t *ip_v6);
#endif
/* -------------------------------------------------- cell info begin -------------------------------------------------- */
#define LUAT_MOBILE_CELL_MAX_NUM 21

typedef struct luat_mobile_gsm_service_cell_info
{
    int cid;        /**< Cell ID, (0 indicates information is not represent).*/
    int mcc;        /**< This field should be ignored when cid is not present*/
    int mnc;        /**< This field should be ignored when cid is not present*/
    int lac;        /**< Location area code.(This field should be ignord when cid is not present). */
    int arfcn;      /**< Absolute RF channel number. */
    int bsic;       /**< Base station identity code. (0 indicates information is not present). */
	int rssi;		/**< Receive signal strength, Value range: rxlev-111 for dbm format */
}luat_mobile_gsm_service_cell_info_t;

typedef struct luat_mobile_gsm_cell_info
{
    int cid;        /**Cell ID, (0 indicates information is not represent).*/
    int mcc;        /**This field should be ignored when cid is not present*/
    int mnc;        /**This field should be ignored when cid is not present*/
    int lac;        /**Location area code.(This field should be ignord when cid is not present). */
    int arfcn;      /**Absolute RF channel number. */
    int bsic;       /**Base station identity code. (0 indicates information is not present). */
	int rssi;		/**< Receive signal strength, Value range: rxlev-111 for dbm format */
}luat_mobile_gsm_cell_info_t;

typedef struct luat_mobile_lte_service_cell_info
{
    uint32_t cid;           /**<Cell ID, (0 indicates information is not represent).*/
    uint16_t mcc;           /**This field should be ignored when cid is not present*/
    uint16_t mnc;           /**This field should be ignored when cid is not present*/
    uint16_t tac;           /**Tracing area code (This field should be ignored when cid is not present). */
    uint16_t pci;           /**Physical cell ID. Range: 0 to 503. */
    uint32_t earfcn;        /**E-UTRA absolute radio frequency channel number of the cell. RANGE: 0 TO 65535. */
    int16_t rssi;		   /**< Receive signal strength, Value range: rsrp-140 for dbm format */
	int16_t rsrp;
	int16_t rsrq;
	int16_t snr;
	uint8_t is_tdd;
	uint8_t band;
	uint8_t ulbandwidth;
	uint8_t dlbandwidth;
}luat_mobile_lte_service_cell_info_t;

typedef struct luat_mobile_lte_cell_info
{
	uint32_t cid;           /**<Cell ID, (0 indicates information is not represent).*/
	uint16_t mcc;           /**This field should be ignored when cid is not present*/
	uint16_t mnc;           /**This field should be ignored when cid is not present*/
	uint16_t tac;           /**Tracing area code (This field should be ignored when cid is not present). */
	uint16_t pci;           /**Physical cell ID. Range: 0 to 503. */
	union
	{
		uint32_t earfcn;        /**E-UTRA absolute radio frequency channel number of the cell. RANGE: 0 TO 65535. */
		uint32_t frequency;
	};
    uint16_t bandwidth;
    uint16_t celltype; /*0:intra lte ncell, 1:inter lte ncell */
    int16_t rsrp;
	int16_t rsrq;
	int16_t snr;
	int16_t rssi;
}luat_mobile_lte_cell_info_t;

typedef struct luat_mobile_cell_info
{
    luat_mobile_gsm_service_cell_info_t gsm_service_info;					/**<   GSM cell information (Serving). */
    luat_mobile_gsm_cell_info_t    gsm_info[LUAT_MOBILE_CELL_MAX_NUM];    /**<   GSM cell information (neighbor). */
    luat_mobile_lte_service_cell_info_t lte_service_info;					/**<   LTE cell information (Serving). */
    luat_mobile_lte_cell_info_t    lte_info[LUAT_MOBILE_CELL_MAX_NUM];    /**<   LTE cell information (neighbor). */
    uint32_t 						version;
    uint8_t                         gsm_info_valid;                         /**< Must be set to TRUE if gsm_info is being passed. */
    uint8_t                         gsm_neighbor_info_num;                           /**< Must be set to the number of elements in entry*/
    uint8_t                         lte_info_valid;                         /**< Must be set to TRUE if lte_info is being passed. */
    uint8_t                     	lte_neighbor_info_num;                           /**< Must be set to the number of elements in entry*/

}luat_mobile_cell_info_t;

/**
 * @brief 立刻搜索一次周围小区基站信息，并同步返回结果
 *
 * @param info 当前移动网络信号状态详细信息
 * @return int =0成功，其他失败
 */
int luat_mobile_get_cell_info(luat_mobile_cell_info_t  *info);

/**
 * @brief 立刻搜索一次周围小区基站信息，通过LUAT_MOBILE_CELL_INFO_UPDATE返回搜索完成消息，luat_mobile_get_last_notify_cell_info获取详细信息
 *
 * @param max_time 搜索的最大时间，单位秒
 * @return int =0成功，其他失败
 */
int luat_mobile_get_cell_info_async(uint8_t max_time);

/**
 * @brief 双卡双待设备，立刻搜索一次周围小区基站信息，通过LUAT_MOBILE_CELL_INFO_UPDATE返回搜索完成消息，luat_mobile_get_last_notify_cell_info获取详细信息
 *
 * @param sim_id sim卡槽
 * @return int =0成功，其他失败
 */
int luat_mobile_get_cell_info_async_with_sim_id(uint8_t sim_id);
/**
 * @brief 获取上一次异步搜索周围小区基站信息，包括周期性搜索和异步搜索，在LUAT_MOBILE_CELL_INFO_UPDATE到来后用本函数获取信息
 *
 * @param info 当前移动网络信号状态详细信息
 * @return int =0成功，其他失败
 */
int luat_mobile_get_last_notify_cell_info(luat_mobile_cell_info_t  *info);
/**
 * @brief 双卡双待设备，获取上一次异步搜索周围小区基站信息，包括周期性搜索和异步搜索，在LUAT_MOBILE_CELL_INFO_UPDATE到来后用本函数获取信息
 *
 * @param sim_id sim卡槽
 * @param info 当前移动网络信号状态详细信息
 * @param max_time 搜索的最大时间
 * @return int =0成功，其他失败
 */
int luat_mobile_get_last_notify_cell_info_with_sim_id(uint8_t sim_id, luat_mobile_cell_info_t  *info);

/**
 * @brief 打印指定sim卡槽搜索到的详细基站信息，与平台有关
 *
 * @param sim_id sim卡槽
 * @return
 */
void luat_mobile_print_last_notify_cell_info_with_sim_id(uint8_t sim_id);

typedef struct luat_mobile_gw_signal_strength_info
{
    int rssi;
    int bitErrorRate;
    int rscp;
    int ecno;
}luat_mobile_gw_signal_strength_info_t;

typedef struct luat_mobile_lte_signal_strength_info
{
    int16_t rssi;		   /**< Receive signal strength, Value range: rsrp-140 for dbm format */
	int16_t rsrp;
	int16_t rsrq;
	int16_t snr;
}luat_mobile_lte_signal_strength_info_t;

typedef struct luat_mobile_signal_strength_info
{
    luat_mobile_gw_signal_strength_info_t   gw_signal_strength;
    luat_mobile_lte_signal_strength_info_t  lte_signal_strength;
    uint8_t luat_mobile_gw_signal_strength_vaild;
    uint8_t luat_mobile_lte_signal_strength_vaild;
}luat_mobile_signal_strength_info_t;

/**
 * @brief 从RSSI转换到CSQ，RSSI只能作为天线口状态的一个参考，而不能作为LTE网络信号状态的参考
 * 
 * @param rssi RSSI值
 * @return uint8_t CSQ值
 */
uint8_t luat_mobile_rssi_to_csq(int8_t rssi);

/**
 * @brief 获取当前移动网络信号状态详细信息
 * 
 * @param info 当前移动网络信号状态详细信息
 * @return int =0成功，其他失败
 */
int luat_mobile_get_signal_strength_info(luat_mobile_signal_strength_info_t *info);

/**
 * @brief 获取CSQ值 CSQ从RSSI转换而来，只能作为天线口状态的一个参考，而不能作为LTE网络信号状态的参考
 * 
 * @param csq CSQ值
 * @return int =0成功，其他失败
 */
int luat_mobile_get_signal_strength(uint8_t *csq);

/**
 * @brief 获取最近一次网络信号状态更新通知后的网络信号状态详细信息
 * 
 * @param info 网络信号状态详细信息
 * @return int =0成功，其他失败
 */
int luat_mobile_get_last_notify_signal_strength_info(luat_mobile_signal_strength_info_t *info);

/**
 * @brief 获取最近一次网络信号状态更新通知后的CSQ值
 * 
 * @param info CSQ值
 * @return int =0成功，其他失败
 */
int luat_mobile_get_last_notify_signal_strength(uint8_t *csq);

/**
 * @brief 获取当前服务小区的ECI
 * 
 * @param eci
 * @return int =0成功，其他失败
 */
int luat_mobile_get_service_cell_identifier(uint32_t *eci);

/**
 * @brief 获取当前服务小区的TAC或LAC
 * 
 * @param tac
 * @return int =0成功，其他失败
 */
int luat_mobile_get_service_tac_or_lac(uint16_t *tac);
/* --------------------------------------------------- cell info end --------------------------------------------------- */


/* ------------------------------------------------ mobile status begin ----------------------------------------------- */
/**
 * @brief 网络状态及相关功能状态发生更换的消息
 * 
 */
typedef enum LUAT_MOBILE_EVENT
{
	LUAT_MOBILE_EVENT_CFUN = 0, /**< CFUN消息 */
	LUAT_MOBILE_EVENT_SIM, /**< SIM卡消息*/
	LUAT_MOBILE_EVENT_REGISTER_STATUS,     /**< 移动网络注册消息*/
	LUAT_MOBILE_EVENT_CELL_INFO, 	/**< 小区基站信息和网络信号变更消息*/
	LUAT_MOBILE_EVENT_PDP, 	/**< PDP状态消息*/
	LUAT_MOBILE_EVENT_NETIF, 	/**< internet状态*/
	LUAT_MOBILE_EVENT_TIME_SYNC, 	/**< 通过基站同步时间完成*/
	LUAT_MOBILE_EVENT_CSCON, /**< RRC状态，0 idle 1 active*/
	LUAT_MOBILE_EVENT_BEARER,/**< PDP承载状态*/
	LUAT_MOBILE_EVENT_SMS,	/**< SMS短信 >*/
	LUAT_MOBILE_EVENT_NAS_ERROR,/**< NAS异常消息，air780exxx系列有效*/
	LUAT_MOBILE_EVENT_IMS_REGISTER_STATUS, /**< IMS注册状态，volte必须在注册成功情况下使用*/
	LUAT_MOBILE_EVENT_CC,	/**< 通话相关消息*/
	LUAT_MOBILE_EVENT_USB_ETH_ON,
	LUAT_MOBILE_EVENT_RRC,
	LUAT_MOBILE_EVENT_FATAL_ERROR = 0xff,/**< 网络遇到严重故障*/
}LUAT_MOBILE_EVENT_E;

typedef enum LUAT_MOBILE_CFUN_STATUS
{
	LUAT_MOBILE_CFUN_OFF = 0,
	LUAT_MOBILE_CFUN_ON,
	LUAT_MOBILE_CFUN_NO_RF = 4,
}LUAT_MOBILE_CFUN_STATUS_E;

typedef enum LUAT_MOBILE_SIM_STATUS
{
	LUAT_MOBILE_SIM_READY = 0,	/**< SIM卡已准备好*/
	LUAT_MOBILE_NO_SIM,			/**< 无SIM卡*/
	LUAT_MOBILE_SIM_NEED_PIN,	/**< 需要输入PIN码*/
	LUAT_MOBILE_SIM_ENTER_PIN_RESULT,	/**< PIN码输入结果*/
	LUAT_MOBILE_SIM_NUMBER,		/**< 获取到电话号码(不一定有值)*/
	LUAT_MOBILE_SIM_WC			/**< SIM卡的写入次数统计,掉电归0*/
}LUAT_MOBILE_SIM_STATUS_E;

typedef enum LUAT_MOBILE_REGISTER_STATUS
{
	LUAT_MOBILE_STATUS_UNREGISTER,  /**< 网络未注册*/
	LUAT_MOBILE_STATUS_REGISTERED,  /**< 网络已注册*/
	LUAT_MOBILE_STATUS_SEARCHING,  	/**< 网络搜索中*/
	LUAT_MOBILE_STATUS_DENIED,  	/**< 网络注册被拒绝*/
	LUAT_MOBILE_STATUS_UNKNOW,		/**< 网络状态未知*/
	LUAT_MOBILE_STATUS_REGISTERED_ROAMING, 	/**< 网络已注册，漫游*/
	LUAT_MOBILE_STATUS_SMS_ONLY_REGISTERED,
	LUAT_MOBILE_STATUS_SMS_ONLY_REGISTERED_ROAMING,
	LUAT_MOBILE_STATUS_EMERGENCY_REGISTERED,
	LUAT_MOBILE_STATUS_CSFB_NOT_PREFERRED_REGISTERED,
	LUAT_MOBILE_STATUS_CSFB_NOT_PREFERRED_REGISTERED_ROAMING,
}LUAT_MOBILE_REGISTER_STATUS_E;

typedef enum LUAT_MOBILE_CELL_INFO_STATUS
{
	LUAT_MOBILE_CELL_INFO_UPDATE = 0,	/**< 小区基站信息变更，只有设置了周期性搜索小区基站时才会有*/
	LUAT_MOBILE_SIGNAL_UPDATE,			/**< 网络信号状态变更，但是不一定是有变化*/
	LUAT_MOBILE_PLMN_UPDATE,			/**< 搜索到新的plmn*/
	LUAT_MOBILE_SERVICE_CELL_UPDATE,	/**< 服务小区信息变更*/
}LUAT_MOBILE_CELL_INFO_STATUS_E;

typedef enum LUAT_MOBILE_PDP_STATUS
{
	LUAT_MOBILE_PDP_ACTIVED = 0,
	LUAT_MOBILE_PDP_DEACTIVING,
	LUAT_MOBILE_PDP_DEACTIVED,
}LUAT_MOBILE_PDP_STATUS_E;

typedef enum LUAT_MOBILE_NETIF_STATUS
{
	LUAT_MOBILE_NETIF_LINK_ON = 0, /**< 已联网*/
	LUAT_MOBILE_NETIF_LINK_OFF,	/**< 断网*/
	LUAT_MOBILE_NETIF_LINK_OOS,	/**< 失去网络连接，尝试恢复中，等同于LUAT_MOBILE_NETIF_LINK_OFF*/
}LUAT_MOBILE_NETIF_STATUS_E;

typedef enum LUAT_MOBILE_BEARER_STATUS
{
	LUAT_MOBILE_BEARER_GET_DEFAULT_APN = 0,/**< 获取到默认APN*/
	LUAT_MOBILE_BEARER_APN_SET_DONE,/**< 设置APN信息完成*/
	LUAT_MOBILE_BEARER_AUTH_SET_DONE,/**< 设置APN加密状态完成*/
	LUAT_MOBILE_BEARER_DEL_DONE,/**< 删除APN信息完成*/
	LUAT_MOBILE_BEARER_SET_ACT_STATE_DONE,/**< APN激活/去激活完成*/
}LUAT_MOBILE_BEARER_STATUS_E;

typedef enum LUAT_MOBILE_SMS_STATUS
{
	LUAT_MOBILE_SMS_READY = 0, /**< 短信功能初始化完成*/
	LUAT_MOBILE_NEW_SMS, /**< 接收到新的短信*/
	LUAT_MOBILE_SMS_SEND_DONE, /**< 短信发送到运营商*/
	LUAT_MOBILE_SMS_ACK, /**< 短信已经被接收*/
}LUAT_MOBILE_SMS_STATUS_E;

typedef enum LUAT_MOBILE_IMS_REGISTER_STATUS
{
	LUAT_MOBILE_IMS_READY = 0,	 /**< IMS网络已注册*/
}LUAT_MOBILE_IMS_REGISTER_STATUS_E;

typedef enum LUAT_MOBILE_CC_STATUS
{
	LUAT_MOBILE_CC_READY = 0, /**< 通话准备完成，可以拨打电话了*/
	LUAT_MOBILE_CC_INCOMINGCALL, /**< 有来电*/
	LUAT_MOBILE_CC_CALL_NUMBER, /**< 有来电号码*/
	LUAT_MOBILE_CC_CONNECTED_NUMBER, /**< 已接通电话号码*/
	LUAT_MOBILE_CC_CONNECTED, /**< 电话已经接通*/
	LUAT_MOBILE_CC_DISCONNECTED, /**< 电话被对方挂断*/
	LUAT_MOBILE_CC_SPEECH_START, /**< 通话开始*/
	LUAT_MOBILE_CC_MAKE_CALL_OK, /**< 拨打电话请求成功*/
	LUAT_MOBILE_CC_MAKE_CALL_FAILED, /**< 拨打电话请求失败*/
	LUAT_MOBILE_CC_ANSWER_CALL_DONE, /**< 接听电话请求完成*/
	LUAT_MOBILE_CC_HANGUP_CALL_DONE, /**< 挂断电话请求完成*/
	LUAT_MOBILE_CC_LIST_CALL_RESULT, /**< 电话列表，未实现*/
	LUAT_MOBILE_CC_PLAY, /**< 电话功能相关音频控制*/
}LUAT_MOBILE_CC_STATUS_E;

typedef enum LUAT_MOBILE_CC_MAKE_CALL_RESULT
{
	LUAT_MOBILE_CC_MAKE_CALL_RESULT_OK = 0, /**< 电话相关请求成功*/
	LUAT_MOBILE_CC_MAKE_CALL_RESULT_NO_CARRIER, /**< 拨打电话无人接听或者已挂断*/
	LUAT_MOBILE_CC_MAKE_CALL_RESULT_BUSY, /**< 拨打电话对方正忙*/
	LUAT_MOBILE_CC_MAKE_CALL_RESULT_ERROR, /**< 拨打电话请求发生未知错误*/
}LUAT_MOBILE_CC_MAKE_CALL_RESULT_E;

typedef enum LUAT_MOBILE_CC_PLAY_IND
{
	LUAT_MOBILE_CC_PLAY_STOP, /**< 音频关闭*/
	LUAT_MOBILE_CC_PLAY_DIAL_TONE, /**< 播放dial音*/
	LUAT_MOBILE_CC_PLAY_RINGING_TONE, /**< 播放振铃*/
	LUAT_MOBILE_CC_PLAY_CONGESTION_TONE, /**< 播放振铃*/
	LUAT_MOBILE_CC_PLAY_BUSY_TONE, /**< 播放振铃*/
	LUAT_MOBILE_CC_PLAY_CALL_WAITING_TONE, /**< 播放振铃*/
	LUAT_MOBILE_CC_PLAY_MULTI_CALL_PROMPT_TONE, /**< 播放振铃*/
	LUAT_MOBILE_CC_PLAY_CALL_INCOMINGCALL_RINGING, /**< 播放来电铃声*/
}LUAT_MOBILE_CC_PLAY_IND_E;

typedef enum LUAT_MOBILE_RRC_IND
{
	LUAT_MOBILE_RRC_DRX_CYCLE_UPDATED,
	LUAT_MOBILE_RRC_IDLE_MEAS_THRESHOLD,
	LUAT_MOBILE_RRC_IDLE_MEAS_ACTION,
}LUAT_MOBILE_RRC_IND_E;
/**
 * @brief 获取当前SIM卡状态
 *
 * @return 见@enum LUAT_MOBILE_SIM_STATUS_E
 */
LUAT_MOBILE_SIM_STATUS_E luat_mobile_get_sim_status(void);

/**
 * @brief 获取当前移动网络注册状态
 * 
 * @return 见@enum LUAT_MOBILE_REGISTER_STATUS_E
 */
LUAT_MOBILE_REGISTER_STATUS_E luat_mobile_get_register_status(void);

/**
 * @brief 网络状态及相关功能状态发生更换时的回调函数，event是消息，index是CID，SIM卡号之类的序号，status是变更后的状态或者更具体的ENUM
 * 
 */
typedef void (*luat_mobile_event_callback_t)(LUAT_MOBILE_EVENT_E event, uint8_t index, uint8_t status);


/**
 * @brief 底层短信消息回调函数，event是消息，param是具体数据指针，暂时不同的平台需要独自处理
 *
 */
typedef void (*luat_mobile_sms_event_callback_t)(uint32_t event, void *param);


/**
 * @brief 注册网络状态及相关功能状态发生更换时的回调函数
 * 
 * @param callback_fun 网络状态及相关功能状态发生更换时的回调函数
 * @return int =0成功，其他失败
 */
int luat_mobile_event_register_handler(luat_mobile_event_callback_t callback_fun);

/**
 * @brief 注销网络状态及相关功能状态发生更换时的回调函数
 * 
 * @return int =0成功，其他失败
 */
int luat_mobile_event_deregister_handler(void);


/**
 * @brief 注册底层短信消息回调函数，后续改为统一消息处理
 *
 * @param callback_fun 短信消息回调函数，如果为NULL，则是注销
 * @return int =0成功，其他失败
 */
int luat_mobile_sms_sdk_event_register_handler(luat_mobile_sms_event_callback_t callback_fun);

/**
 * @brief 注册底层短信消息回调函数，后续改为统一消息处理(和luat_mobile_sms_sdk_event_register_handler一样，只是为了兼容老的BSP)
 *
 * @param callback_fun 短信消息回调函数，如果为NULL，则是注销
 * @return int =0成功，其他失败
 */
int luat_mobile_sms_event_register_handler(luat_mobile_sms_event_callback_t callback_fun);
/* ------------------------------------------------- mobile status end ------------------------------------------------ */

/**
 * @brief 设置RRC自动释放时间，在RRC active（见LUAT_MOBILE_EVENT_CSCON）后经过一段时间在适当的时机释放RRC
 * 
 * @param s 超时时间，单位秒，如果为0则是关闭功能
 * @note 没有在Air724上使用过AT*RTIME的，或者不明白RRC的含义，请不要使用RRC相关API
 */
void luat_mobile_set_rrc_auto_release_time(uint8_t s);

//实验性质API，请勿使用
void luat_mobile_set_auto_rrc(uint8_t s1, uint32_t s2);
void luat_mobile_set_auto_rrc_default(void);
/**
 * @brief RRC自动释放暂停/恢复
 * 
 * @param onoff 1暂停 0恢复
 * @note 没有在Air724上使用过AT*RTIME的，或者不明白RRC的含义，请不要使用RRC相关API
 */
void luat_mobile_rrc_auto_release_pause(uint8_t onoff);


/**
 * @brief RRC立刻释放一次，不能在luat_mobile_event_callback里使用
 * @note 没有在Air724上使用过AT*RTIME的，或者不明白RRC的含义，请不要使用RRC相关API
 */
void luat_mobile_rrc_release_once(void);

void luat_mobile_rrc_get_idle_meas_threshold(int16_t *sIntraSearchP, int16_t *sNonIntraSearchP, int16_t *sIntraSearchQ, int16_t *sNonIntraSearchQ);

/**
 * @brief 获取当前与基站的RRC状态，等于AT+CSCON
 *
 * @return uint8_t 1=CONNECT, 0=IDLE或者DISCONNECT
 */
uint8_t luat_mobile_get_rrc_state(void);

/**
 * @brief 重新底层网络协议栈，本质是快速的进出飞行模式，注意和设置飞行模式是冲突的，一定时间内只能用一个。
 * 
 * @return int =0成功，其他失败
 */
int luat_mobile_reset_stack(void);

/**
 * @brief 遇到网络严重错误时允许自动重启协议栈
 * @param onoff 0关闭 其他开启
 * @return void
 */
void luat_mobile_fatal_error_auto_reset_stack(uint8_t onoff);
/**
 * @brief 设置周期性辅助工作，包括周期性搜索小区基站，SIM卡短时间脱离卡槽后周期性尝试恢复，这个功能和luat_mobile_reset_stack是有可能冲突的。所有功能默认都是关闭的
 * 
 * @param get_cell_period 周期性搜索小区基站的时间间隔，单位ms，这个会增加低功耗，尽量的长，或者写0关闭这个功能，用上面的手段搜索
 * @param check_sim_period SIM卡短时间脱离卡槽后尝试恢复的时间间隔，单位ms，建议在5000~10000，或者写0，当SIM卡移除的消息上来后手动重启协议栈
 * @param search_cell_time 启动周期性搜索小区基站后，每次搜索的最大时间，单位s，1~8
 * @return int 
 */
int luat_mobile_set_period_work(uint32_t get_cell_period, uint32_t check_sim_period, uint8_t search_cell_time);
/**
 * @brief 设置SIM卡短时间脱离卡槽后周期性尝试恢复，luat_mobile_set_period_work的简化版本
 *
 * @param check_sim_period SIM卡短时间脱离卡槽后尝试恢复的时间间隔，单位ms，建议在5000~10000，或者写0，当SIM卡移除的消息上来后手动重启协议栈
 * @return int
 */
int luat_mobile_set_check_sim(uint32_t check_sim_period);
/**
 * @brief 设置定时检测网络是否正常并且在检测到长时间无网时通过重启协议栈来恢复，但是不能保证一定成功，这个功能和luat_mobile_reset_stack是有可能冲突的。所有功能默认都是关闭的
 *
 * @param period 无网时长，单位ms，不可以太短，建议60000以上，为网络搜索网络保留足够的时间
 * @return void
 */
void luat_mobile_set_check_network_period(uint32_t period);
/**
 * @brief 获取累计的IP流量数据
 * @param uplink 上行流量
 * @param downlink 下行流量
 * @return 无
 */
void luat_mobile_get_ip_data_traffic(uint64_t *uplink, uint64_t *downlink);
/**
 * @brief 清除IP流量数据
 * @param clear_uplink 清除上行流量
 * @param clear_downlink 清除下行流量
 * @return 无
 */
void luat_mobile_clear_ip_data_traffic(uint8_t clear_uplink, uint8_t clear_downlink);

/**
 * @brief 获取模块能支持的频段
 * @param band 存放输出频段值的缓存，至少需要CMI_DEV_SUPPORT_MAX_BAND_NUM字节的空间
 * @param total_num 频段数量
 * @return 成功返回0，其他失败
 */
int luat_mobile_get_support_band(uint8_t *band,  uint8_t *total_num);
/**
 * @brief 获取模块当前设置使用的频段
 * @param band 存放输出频段值的缓存，至少需要CMI_DEV_SUPPORT_MAX_BAND_NUM字节的空间
 * @param total_num 频段数量
 * @return 成功返回0，其他失败
 */
int luat_mobile_get_band(uint8_t *band,  uint8_t *total_num);
/**
 * @brief 设置模块使用的频段
 * @param band 设置的频段，需要至少total_num数量的空间
 * @param total_num 频段数量
 * @return 成功返回0，其他失败
 */
int luat_mobile_set_band(uint8_t *band,  uint8_t total_num);

/**
 * @brief LTE协议栈功能特殊配置
 * @param item 见MOBILE_CONF_XXX
 * @param value 配置值
 * @return 成功返回0，其他失败
 */
int luat_mobile_config(uint8_t item, uint32_t value);

/**
 * @brief RF测试模式
 * @param uart_id 测试结果输出的串口ID
 * @param on_off 进出测试模式，0退出 其他进入
 * @return 无
 */
void luat_mobile_rf_test_mode(uint8_t uart_id, uint8_t on_off);
/**
 * @brief RF测试的指令或者数据输入
 * @param data 数据，可以为空，只有为空的时候才会真正开始处理指令
 * @param data_len 数据长度，可以为0，只有为0的时候才会真正开始处理指令
 * @return 无
 */
void luat_mobile_rf_test_input(char *data, uint32_t data_len);

enum
{
	MOBILE_CONF_RESELTOWEAKNCELL = 1,
	MOBILE_CONF_STATICCONFIG,
	MOBILE_CONF_QUALITYFIRST,
	MOBILE_CONF_USERDRXCYCLE,
	MOBILE_CONF_T3324MAXVALUE,
	MOBILE_CONF_PSM_MODE,
	MOBILE_CONF_CE_MODE,
	MOBILE_CONF_SIM_WC_MODE,
	MOBILE_CONF_FAKE_CELL_BARTIME,
	MOBILE_CONF_RESET_TO_FACTORY,
	MOBILE_CONF_USB_ETHERNET,
	MOBILE_CONF_DISABLE_NCELL_MEAS,
	MOBILE_CONF_MAX_TX_POWER,
};

uint32_t luat_mobile_sim_write_counter(void);

enum
{
	LUAT_MOBILE_ISP_UNKNOW,
	LUAT_MOBILE_ISP_CMCC,	/*中国移动*/
	LUAT_MOBILE_ISP_CTCC,	/*中国电信*/
	LUAT_MOBILE_ISP_CUCC,	/*中国联通*/
	LUAT_MOBILE_ISP_CRCC,	/*中国广电*/
};



/**
 * @brief 通过PLMN判断运营商，目前只支持国内三大运营商及广电
 * @param mcc MCC码，3位10进制数字，目前只有中国460是支持的
 * @param mnc MNC码，2位10进制数字
 * @return < 0 发生错误，其他见LUAT_MOBILE_ISP_XXX
 */
int luat_mobile_get_isp_from_plmn(uint16_t mcc, uint8_t mnc);

/**
 * @brief 通过IMSI提取PLMN
 * @param imsi IMSI号码
 * @param mcc MCC码，3位10进制数字
 * @param mnc MNC码，2位10进制数字
 * @return =0成功，其他错误
 */
int luat_mobile_get_plmn_from_imsi(char *imsi, uint16_t *mcc, uint8_t *mnc);

/**
 * @brief 通过DL EARFCN查找对应频段
 * @param earfcn 下行频点
 * @return >0为对应频段，=0未找到对应频段
 */
int luat_mobile_get_band_from_earfcn(uint32_t earfcn);

/**
 * @brief 获取最近一次来电号码
 * @param buf 存放号码的缓存
 * @param buf_len 存放号码的缓存长度，推荐80
 * @return 无
 */
void luat_mobile_get_last_call_num(char *buf, uint8_t buf_len);
/**
 * @brief 主动拨打打电话
 * @param sim_id sim卡槽
 * @param number 字符串形式的电话号码
 * @param len 电话号码长度
 * @return =0成功，其他错误
 */
int luat_mobile_make_call(uint8_t sim_id, char *number, uint8_t len);
/**
 * @brief 主动挂断电话
 * @param sim_id sim卡槽
 * @return 无
 */
void luat_mobile_hangup_call(uint8_t sim_id);
/**
 * @brief 接听电话
 * @param sim_id sim卡槽
 * @return =0成功，其他错误
 */
int luat_mobile_answer_call(uint8_t sim_id);
/**
 * @brief 初始化电话功能
 * @param multimedia_id multimedia_id 多媒体通道，目前只有0
 * @param callback 下行通话数据回调函数
 * @return =0成功，其他错误
 */
int luat_mobile_speech_init(uint8_t multimedia_id,void *callback);
/**
 * @brief 上行通话数据
 * @param data 录音数据
 * @param len 录音数据长度
 * @return =0成功，其他错误
 */
int luat_mobile_speech_upload(uint8_t *data, uint32_t len);

/**
 * @brief 是否允许基站时间同步给本地时间
 * @param on_off 0不允许，其他允许
 */
void luat_mobile_set_sync_time(uint8_t on_off);

/**
 * @brief 查看当前是否允许基站时间同步给本地时间
 * @return =0不允许，其他允许
 */
uint8_t luat_mobile_get_sync_time(void);

int luat_mobile_softsim_onoff(uint8_t on_off);
int luat_mobile_sim_detect_onoff(uint8_t on_off);
void luat_mobile_softsim_init_default(void);
enum
{
	LUAT_MOBILE_LOCK_CELL_OP_UNLOCK_EARFCN,
	LUAT_MOBILE_LOCK_CELL_OP_LOCK_EARFCN,
	LUAT_MOBILE_LOCK_CELL_OP_LOCK_CELL,
	LUAT_MOBILE_LOCK_CELL_OP_UNLOCK_CELL,
};
int luat_mobile_lock_cell(uint32_t op, uint32_t earfcn, uint16_t pci);
typedef struct
{
	uint32_t earfcn;
	uint16_t pci;
	uint16_t mcc;
	uint16_t mnc;
}luat_mobile_scell_extern_info_t;
int luat_mobile_get_extern_service_cell_info(luat_mobile_scell_extern_info_t *info);
void luat_mobile_vsim_user_heartbeat_once(void);
uint32_t luat_mobile_get_search_plmn(void);
void luat_mobile_data_ip_mode(uint8_t on_off);

void luat_mobile_init_auto_apn_by_plmn(void);
void luat_mobile_init_auto_apn(void);
typedef struct
{
	char  *data;	//包含apn name,user,password信息
	uint8_t ip_type;
	uint8_t protocol;
	uint8_t name_len;
	uint8_t user_len;
	uint8_t password_len;
}apn_info_t;
/**
 * 添加一条APN信息到全球APN列表，列表每次重启后都需要重建
 * @param mcc
 * @param mnc
 * @param ip_type 激活的IP类型，以下参数参考luat_mobile_user_apn_auto_active
 * @param protocol
 * @param name
 * @param name_len
 * @param user
 * @param user_len
 * @param password
 * @param password_len
 * @param task_safe 是否做task安全保护，如果只输入一条写1，如果输入N条，可在开始和结束自行进行保护处理，这里写0
 */
void luat_mobile_add_auto_apn_item(uint16_t mcc, uint16_t mnc, uint8_t ip_type, uint8_t protocol, char *name, uint8_t name_len, char *user, uint8_t user_len, char *password, uint8_t password_len, uint8_t task_safe);
/**
 * 通过MCC,MNC查询APN信息
 * @param mcc
 * @param mnc
 * @param apn APN信息
 * @return =0找到匹配的信息，其他未找到
 */
int luat_mobile_find_apn_by_mcc_mnc(uint16_t mcc, uint16_t mnc, apn_info_t *apn);
/**
 * 通过MCC,MNC打印APN信息
 * @param mcc
 * @param mnc
 * @return
 */
void luat_mobile_print_apn_by_mcc_mnc(uint16_t mcc, uint16_t mnc);
/** @}*/
#endif
