#ifndef __LUAT_MOBILE_H__
#define __LUAT_MOBILE_H__

#include "luat_base.h"

int luat_mobile_get_imei(int sim_id, char* buff, size_t* len);
int luat_mobile_get_sn(char* buff, size_t* len);
int luat_mobile_get_muid(char* buff, size_t* len);
int luat_mobile_get_iccid(int sim_id, char* buff, size_t* len);
int luat_mobile_get_imsi(int sim_id, char* buff, size_t* len);

int luat_mobile_get_sim_id(int *id);
int luat_mobile_set_sim_id(int id);


int luat_mobile_get_apn(int sim_id, int cid, char* buff, size_t* len);
int luat_mobile_get_default_apn(int sim_id, char* buff, size_t* len);


// 进出飞行模式
int luat_mobile_set_flymode(int index, int mode);
int luat_mobile_get_flymode(int index);

/* -------------------------------------------------- cell info begin -------------------------------------------------- */
#define LUAT_MOBILE_CELL_MAX_NUM 9

typedef struct luat_mobile_gsm_service_cell_info
{
    int cid;        /**Cell ID, (0 indicates information is not represent).*/
    int mcc;        /**This field should be ignored when cid is not present*/
    int mnc;        /**This field should be ignored when cid is not present*/
    int lac;        /**Location area code.(This field should be ignord when cid is not present). */
    int arfcn;      /**Absolute RF channel number. */
    int bsic;       /**Base station identity code. (0 indicates information is not present). */
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
    int16_t rssi;		   /**< Receive signal strength, Value range: rsrp-140 for dbm format */
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

uint8_t luat_mobile_rssi_to_csq(int8_t rssi);
int luat_mobile_get_signal_strength_info(luat_mobile_signal_strength_info_t *info);
int luat_mobile_get_signal_strength(uint8_t *csq);
int luat_mobile_get_last_notify_signal_strength_info(luat_mobile_signal_strength_info_t *info);
int luat_mobile_get_last_notify_signal_strength(uint8_t *csq);
/* --------------------------------------------------- cell info end --------------------------------------------------- */


/* ------------------------------------------------ mobile status begin ----------------------------------------------- */
typedef enum LUAT_MOBILE_EVENT
{
	/*!< CFUN消息*/
	LUAT_MOBILE_EVENT_CFUN = 0,
	/*!< SIM卡消息*/
	LUAT_MOBILE_EVENT_SIM,
    /*!< 移动网络注册消息*/
	LUAT_MOBILE_EVENT_REGISTER_STATUS,
	/*!< 小区基站信号变更消息*/
	LUAT_MOBILE_EVENT_CELL_INFO,
	/*!< PDP状态消息*/
	LUAT_MOBILE_EVENT_PDP,
	/*!< internet状态*/
	LUAT_MOBILE_EVENT_NETIF,
	/*!< 通过基站同步时间完成*/
	LUAT_MOBILE_EVENT_TIME_SYNC,
	/*!< 新短信消息*/
	LUAT_MOBILE_EVENT_SMS,
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

    /*!< 网络未注册*/
	LUAT_MOBILE_STATUS_UNREGISTER,
    /*!< 网络已注册*/
	LUAT_MOBILE_STATUS_REGISTERED,
	/*!< 网络注册被拒绝*/
	LUAT_MOBILE_STATUS_DENIED,
	/*!< 网络状态未知*/
	LUAT_MOBILE_STATUS_UNKNOW,
	/*!< 网络已注册，漫游*/
	LUAT_MOBILE_STATUS_REGISTERED_ROAMING,
	LUAT_MOBILE_STATUS_SMS_ONLY_REGISTERED,
	LUAT_MOBILE_STATUS_SMS_ONLY_REGISTERED_ROAMING,
	LUAT_MOBILE_STATUS_EMERGENCY_REGISTERED,
	LUAT_MOBILE_STATUS_CSFB_NOT_PREFERRED_REGISTERED,
	LUAT_MOBILE_STATUS_CSFB_NOT_PREFERRED_REGISTERED_ROAMING,
}LUAT_MOBILE_REGISTER_STATUS_E;

typedef enum LUAT_MOBILE_CELL_INFO_STATUS
{
	LUAT_MOBILE_CELL_INFO_UPDATE = 0,
	LUAT_MOBILE_SIGNAL_UPDATE,
}LUAT_MOBILE_CELL_INFO_STATUS_E;

typedef enum LUAT_MOBILE_PDP_STATUS
{
	LUAT_MOBILE_PDP_ACTIVED = 0,
	LUAT_MOBILE_PDP_DEACTIVING,
	LUAT_MOBILE_PDP_DEACTIVED,
}LUAT_MOBILE_PDP_STATUS_E;

typedef enum LUAT_MOBILE_NETIF_STATUS
{
	LUAT_MOBILE_NETIF_LINK_ON = 0,
	LUAT_MOBILE_NETIF_LINK_OFF,
	LUAT_MOBILE_NETIF_LINK_OOS,	//失去网络连接，尝试恢复中，等同于LUAT_MOBILE_NETIF_LINK_OFF
}LUAT_MOBILE_NETIF_STATUS_E;

LUAT_MOBILE_REGISTER_STATUS_E luat_mobile_get_register_status(void);

typedef void (*luat_mobile_event_callback_t)(LUAT_MOBILE_EVENT_E event, uint8_t index, uint8_t status);
int luat_mobile_event_register_handler(luat_mobile_event_callback_t callback_fun);
int luat_mobile_event_deregister_handler(void);
/* ------------------------------------------------- mobile status end ------------------------------------------------ */

int luat_mobile_reset_stack(void);
#endif
