#ifndef _ESP32_BLE_H_
#define _ESP32_BLE_H_

#include "luat_msgbus.h"

#include "esp_bt.h"
#include "esp_gap_ble_api.h"
#include "esp_gatts_api.h"
#include "esp_bt_defs.h"
#include "esp_bt_main.h"
#include "esp_bt_device.h"


#define BLE_EVENT_BASE_MASK 0xffff0000
#define BLE_EVENT_GAP_BASE 0x10000
#define BLE_EVENT_GATTS_BASE 0x20000

#define BLE_EVENT_BASE_GET(event) (event&BLE_EVENT_BASE_MASK) 
#define BLE_EVENT_ID_GET(event) (event&(~BLE_EVENT_BASE_MASK))


typedef struct ble_cb_param_tag{
	int event;
	
	union {

		struct {
			esp_ble_gap_cb_param_t *p;
		} gap;
				
		struct {
			int gattsIf;
			esp_ble_gatts_cb_param_t *p;
		} gatts;
	} eventParam;
} ble_cb_param_t;

#define BLE_API extern

void bleEvevntParamFree(void *ptr);

BLE_API esp_err_t bleInit(void);

/*GATTS 接口*/
BLE_API esp_err_t bleGattsAppRegister(uint16_t appId);
BLE_API esp_err_t bleGattsCreateService(esp_gatt_if_t gattsIf, uint8_t *uuid, uint16_t uuidLen, uint16_t attrNum);
BLE_API esp_err_t bleGattsStartService(uint16_t serviceHandle);
BLE_API esp_err_t bleGattsAddChar(uint16_t serviceHandle, uint8_t *uuid, uint16_t uuidLen, uint8_t *charVal, uint16_t charValLen);
BLE_API esp_err_t bleGattsAddCharDescr(uint16_t serviceHandle, uint8_t *uuid, uint16_t uuidLen, uint8_t *charDescrVal, uint16_t charDescrValLen);
BLE_API esp_err_t bleGattsSendResponse(esp_gatt_if_t gattsIf, uint16_t attrHandle, uint16_t connId, uint32_t transId, uint8_t *rspVal, uint8_t rspValLen);
BLE_API esp_err_t bleGattsRead(esp_ble_gatts_cb_param_t *param);

/*GAP 接口*/
BLE_API esp_err_t bleGapExtAdvSetParams(uint8_t instance, uint32_t interval_min, uint32_t interval_max);
BLE_API esp_err_t bleGapExtAdvSetRandAddr(uint8_t instance, esp_bd_addr_t rand_addr);
BLE_API esp_err_t bleGapConfigExtAdvDataRaw(uint8_t instance, uint16_t length, const uint8_t *data);
BLE_API esp_err_t bleGapExtAdvStart(uint8_t instanceNum);

#endif
