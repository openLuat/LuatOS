#ifndef __LUAT_MOBILE_H__
#define __LUAT_MOBILE_H__

#include "luat_base.h"
/**
 * @defgroup luatos_mobile 移动网络相关接口
 * @{
 */
/**
 * @example  example_mobile/src/example_mobile.c
 * mobile接口示例
 */
/**
 * @example  example_https/src/example_main.c
 * https接口示例
 */
/**
 * @example  example_linksdk/src/example_mqtt_basic.c
 * @example  example_linksdk/src/example_sysdep_api_test.c
 * linkssdk接口示例
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
 * @brief 获取SN，并不一定存在
 * 
 * @param buff[OUT] SN数据
 * @param buf_len 用户传入缓存的大小，如果底层数据量大于buf_len，只会传出buf_len大小的数据
 * @return int <= 0错误 >0实际传出的大小
 */
int luat_mobile_get_sn(char* buff, size_t buf_len);

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
 * @brief 当前使用的SIM卡的位置，并不一定支持
 * 
 * @param id[OUT] sim位置，对于双卡双待的设备，输出0或者1，其他设备输出0
 * @return int =0成功，其他失败
 */
int luat_mobile_get_sim_id(int *id);

/**
 * @brief 改变使用的SIM卡的位置，并不一定支持
 * 
 * @param id sim位置，对于双卡双待的设备，选0或者1，其他设备不支持
 * @return int =0成功，其他失败
 */
int luat_mobile_set_sim_id(int id);

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
 * @brief 获取默认CID的apn name，并不一定支持
 * 
 * @param sim_id sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param buff[OUT] apn name 
 * @param buf_len 用户传入缓存的大小，如果底层数据量大于buf_len，只会传出buf_len大小的数据
 * @return int <= 0错误 >0实际传出的大小
 */
int luat_mobile_get_default_apn(int sim_id, char* buff, size_t buf_len);


/**
 * @brief 进出飞行模式
 * 
 * @param index sim位置，对于双卡双待的设备，选0或者1，其他设备随意
 * @param mode 飞行模式，0进入，1退出
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

/* -------------------------------------------------- cell info begin -------------------------------------------------- */
#define LUAT_MOBILE_CELL_MAX_NUM 9

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
    uint32_t earfcn;        /**E-UTRA absolute radio frequency channel number of the cell. RANGE: 0 TO 65535. */
    int16_t rsrp;
	int16_t rsrq;
	int16_t snr;
}luat_mobile_lte_cell_info_t;

typedef struct luat_mobile_cell_info
{
    luat_mobile_gsm_service_cell_info_t gsm_service_info;
    luat_mobile_gsm_cell_info_t    gsm_info[LUAT_MOBILE_CELL_MAX_NUM];    /**<   GSM cell information (Serving and neighbor. */
    luat_mobile_lte_service_cell_info_t lte_service_info;
    luat_mobile_lte_cell_info_t    lte_info[LUAT_MOBILE_CELL_MAX_NUM];    /**<   LTE cell information (Serving and neighbor). */
    uint8_t                         gsm_info_valid;                         /**< Must be set to TRUE if gsm_info is being passed. */
    uint8_t                         gsm_neighbor_info_num;                           /**< Must be set to the number of elements in entry*/
    uint8_t                         lte_info_valid;                         /**< Must be set to TRUE if lte_info is being passed. */
    uint8_t                     	lte_neighbor_info_num;                           /**< Must be set to the number of elements in entry*/
}luat_mobile_cell_info_t;

int luat_mobile_get_cell_info(luat_mobile_cell_info_t  *info);
int luat_mobile_get_last_notify_cell_info(luat_mobile_cell_info_t  *info);


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
	LUAT_MOBILE_EVENT_SMS, 	/**< 新短信消息*/
	LUAT_MOBILE_EVENT_CSCON, /**< RRC状态，0 idle 1 active*/
}LUAT_MOBILE_EVENT_E;

typedef enum LUAT_MOBILE_CFUN_STATUS
{
	LUAT_MOBILE_CFUN_OFF = 0,
	LUAT_MOBILE_CFUN_ON,
	LUAT_MOBILE_CFUN_NO_RF = 4,
}LUAT_MOBILE_CFUN_STATUS_E;

typedef enum LUAT_MOBILE_SIM_STATUS
{
	LUAT_MOBILE_SIM_READY = 0,
	LUAT_MOBILE_NO_SIM,
	LUAT_MOBILE_SIM_NEED_PIN,
}LUAT_MOBILE_SIM_STATUS_E;

typedef enum LUAT_MOBILE_REGISTER_STATUS
{
	LUAT_MOBILE_STATUS_UNREGISTER,  /**< 网络未注册*/
	LUAT_MOBILE_STATUS_REGISTERED,  /**< 网络已注册*/
	LUAT_MOBILE_STATUS_DENIED,  	/**< 网络注册被拒绝，或者正在搜网中*/
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
/* ------------------------------------------------- mobile status end ------------------------------------------------ */

/**
 * @brief 设置RRC自动释放时间，在RRC active（见LUAT_MOBILE_EVENT_CSCON）后经过一段时间在适当的时机释放RRC
 * 
 * @param s 超时时间，单位秒，如果为0则是关闭功能
 * @note 没有在Air724上使用过AT*RTIME的，或者不明白RRC的含义，请不要使用RRC相关API
 */
void luat_mobile_set_rrc_auto_release_time(uint8_t s);

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

/**
 * @brief 重新底层网络协议栈，本质是快速的进出飞行模式，注意和设置飞行模式是冲突的，一定时间内只能用一个。
 * 
 * @return int =0成功，其他失败
 */
int luat_mobile_reset_stack(void);

/**
 * @brief 设置周期性辅助工作，包括周期性搜索小区基站，SIM卡短时间脱离卡槽后周期性尝试恢复，这个功能和luat_mobile_reset_stack是有可能冲突的。所有功能默认都是关闭的
 * 
 * @param get_cell_period 周期性搜索小区基站的时间间隔，单位ms，这个会增加低功耗，尽量的长，或者写0关闭这个功能，用上面的手段搜索
 * @param check_sim_period SIM卡短时间脱离卡槽后尝试恢复的时间间隔，单位ms，建议在5000~10000，或者写0，当SIM卡移除的消息上来后手动重启协议栈
 * @param serach_cell_time 启动周期性搜索小区基站后，每次搜索的最大时间，单位s，1~8
 * @return int 
 */
int luat_mobile_set_period_work(uint32_t get_cell_period, uint32_t check_sim_period, uint8_t serach_cell_time);
/** @}*/
#endif
