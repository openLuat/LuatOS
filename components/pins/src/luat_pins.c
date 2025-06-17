
#include "luat_base.h"
#include "luat_pins.h"
#include "luat_mcu.h"
#include <stdlib.h>
#include "luat_fs.h"
#include "luat_mem.h"
#include "luat_pm.h"
#include "luat_hmeta.h"

#define LUAT_LOG_TAG "pins"
#include "luat_log.h"

#include "cJSON.h"

uint8_t g_pins_debug;

static inline int luat_isdigit(char c)
{
	return (c >= '0' && c <= '9');
}

static int search(char *string, size_t string_len, const char **table, uint8_t len)
{
	for(int i = 0; i < len; i++)
	{
		if (strnstr(string, table[i], string_len))
		{
			return i;
		}
	}
	return -1;
}

static luat_pin_peripheral_function_description_u luat_pin_function_analyze(char *string, size_t len)
{
	luat_pin_peripheral_function_description_u description;
	char *old = string;
	size_t org_len = len;
	size_t offset = 0;
	const char *peripheral_names[LUAT_MCU_PERIPHERAL_QTY] = {
			"UART","I2C","SPI","PWM","CAN","GPIO","I2S","SDIO","LCD","CAMERA","ONEWIRE","KEYBORAD"
	};
	const char *function0_names[3] = {
			"RX","SCL","MOSI"
	};
	const char *function1_names[3] = {
			"TX","SDA","MISO"
	};
	const char *function2_names[3] = {
			"RTS","CLK","BCLK"
	};
	const char *function3_names[3] = {
			"CTS","CS","LRCLK"
	};
	const char *function4_names[2] = {
			"MCLK","CMD"
	};
	const char *function5_names[1] = {
			"SCLK"
	};
	description.code = 0;
	for(description.peripheral_type = 0; description.peripheral_type < LUAT_MCU_PERIPHERAL_QTY; description.peripheral_type++)
	{
		offset = strlen(peripheral_names[description.peripheral_type]);
		if (!memcmp(string, peripheral_names[description.peripheral_type], offset))
		{
			int function_id;
			string += offset;
			len -= offset;
			if (description.peripheral_type != LUAT_MCU_PERIPHERAL_GPIO)
			{
				description.peripheral_id = 0;
				while(luat_isdigit(string[0]))
				{
					description.peripheral_id = description.peripheral_id * 10 + (string[0] - '0');
					string++;
					len--;
				}
			}
			switch(description.peripheral_type)
			{
			case LUAT_MCU_PERIPHERAL_UART:
				function_id = search(string, len, function0_names, sizeof(function0_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 0;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function1_names, sizeof(function1_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 1;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function2_names, sizeof(function2_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 2;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function3_names, sizeof(function3_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 3;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_I2C:
				function_id = search(string, len, function0_names, sizeof(function0_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 0;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function1_names, sizeof(function1_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 1;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_SPI:
				function_id = search(string, len, function0_names, sizeof(function0_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 0;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function1_names, sizeof(function1_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 1;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function2_names, sizeof(function2_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 2;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function3_names, sizeof(function3_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 3;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_PWM:
				if (!string[0])
				{
					description.function_id = 0;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				if (string[0] == 'n')
				{
					description.function_id = 1;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_CAN:
				function_id = search(string, len, function0_names, sizeof(function0_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 0;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function1_names, sizeof(function1_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 1;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function2_names, sizeof(function2_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 2;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_GPIO:
				if (luat_isdigit(string[0]))
				{
					function_id = 0;
					while(luat_isdigit(string[0]))
					{
						function_id = function_id * 10 + (string[0] - '0');
						string++;
						len--;
					}
					description.code |= (function_id & 0x00ff);
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_I2S:
				function_id = search(string, len, function0_names, sizeof(function0_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 0;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function1_names, sizeof(function1_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 1;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function2_names, sizeof(function2_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 2;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function3_names, sizeof(function3_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 3;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function4_names, sizeof(function4_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 4;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_SDIO:
				if (strnstr(string, "_DATA", len))
				{
					if (string[5] >= '0' && string[5] <= '3')
					{
						function_id = string[5] - '0';
					}
					break;
				}
				function_id = search(string, len, function4_names, sizeof(function4_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 4;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				function_id = search(string, len, function5_names, sizeof(function5_names)/4);
				if (function_id >= 0)
				{
					description.function_id = 5;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			case LUAT_MCU_PERIPHERAL_ONEWIRE:
				if (!string[0])
				{
					description.function_id = 0;
					goto LUAT_PIN_FUNCTION_ANALYZE_DONE;
				}
				break;
			default:
				break;
			}
		}
	}
	LLOGE("%.*s不是可配置的外设功能", len, string);
	description.code = 0xffff;
LUAT_PIN_FUNCTION_ANALYZE_DONE:
	if (!description.is_no_use)
	{
		if (g_pins_debug) {
			LLOGD("%.*s find %d,%d,%d", org_len, old, description.peripheral_type, description.peripheral_id, description.function_id);
		}
	}
	return description;
}

int luat_pins_setup(uint16_t pin, const char* func_name, size_t name_len, int altfun_id) {
	luat_pin_function_description_t pin_description = {0};
	luat_pin_peripheral_function_description_u func_description = {0};
	luat_pin_iomux_info pin_list[LUAT_PIN_FUNCTION_MAX] = {0};
	int result = 0;
	// 需要忽略部分特定名称的pin
	#ifdef CHIP_EC718
	if (name_len < 4) {
		return 0;
	}
	if (memcmp("DBG_", func_name, 4) == 0 
		|| memcmp("LCD_", func_name, 4) == 0 
		|| memcmp("USIM_", func_name, 5) == 0 
		|| memcmp("VBUS", func_name, 4) == 0
		|| memcmp("USB_", func_name, 4) == 0
		|| memcmp("CHG_", func_name, 4) == 0
		|| memcmp("CAM_", func_name, 4) == 0
		|| memcmp("SPI", func_name, 3) == 0
		|| memcmp("WAKEUP", func_name, 5) == 0
		|| memcmp("ADC", func_name, 3) == 0
		|| memcmp("PWR_KEY", func_name, 7) == 0
		|| memcmp("I2S", func_name, 3) == 0){
		return 1;
	}
	if (pin == 57 || pin == 58) {
		char buff[32] = {0};
		luat_hmeta_model_name(buff);
		if (0 == memcmp("Air780EHV", buff, 9)) {
			LLOGE("pin%d不支持修改", pin);
			goto LUAT_PIN_SETUP_DONE;
		}
	}
	#endif
	if (luat_pin_get_description_from_num(pin, &pin_description))
	{
		LLOGE("pin%d不支持修改", pin);
		goto LUAT_PIN_SETUP_DONE;
	}
	if (func_name != NULL)
	{
		if (name_len < 2)
		{
			LLOGE("%.*s外设功能描述不正确", name_len, func_name);
			goto LUAT_PIN_SETUP_DONE;
		}

		func_description = luat_pin_function_analyze(func_name, name_len);
		if (func_description.code == 0xffff)
		{
			goto LUAT_PIN_SETUP_DONE;
		}
		altfun_id = luat_pin_get_altfun_id_from_description(func_description.code, &pin_description);
		if (altfun_id == 0xff)
		{
			LLOGE("%.*s不是pin%d的可配置功能", name_len, func_name, pin);
			goto LUAT_PIN_SETUP_DONE;
		}
	}
	else
	{
		if (altfun_id < LUAT_PIN_ALT_FUNCTION_MAX)
		{
			func_description.code = pin_description.function_code[altfun_id];
			if (func_description.code == 0xffff)
			{
				LLOGE("没有altfunction%d", altfun_id);
				goto LUAT_PIN_SETUP_DONE;
			}
		}
		else
		{
			LLOGE("没有altfunction%d", altfun_id);
			goto LUAT_PIN_SETUP_DONE;
		}
	}
	if (!luat_pin_get_iomux_info(func_description.peripheral_type, (func_description.peripheral_type != LUAT_MCU_PERIPHERAL_GPIO)?(func_description.peripheral_id):(func_description.code & 0x00ff), pin_list))
	{
		if (func_description.peripheral_type != LUAT_MCU_PERIPHERAL_GPIO)
		{
			pin_list[func_description.function_id].altfun_id = altfun_id;
			pin_list[func_description.function_id].uid = pin_description.uid;
		}
		else
		{
			pin_list[0].altfun_id = altfun_id;
			pin_list[0].uid = pin_description.uid;
		}
		result = luat_pin_set_iomux_info(func_description.peripheral_type, (func_description.peripheral_type != LUAT_MCU_PERIPHERAL_GPIO)?(func_description.peripheral_id):(func_description.code & 0x00ff), pin_list);
		if (result >= 0)
		{
			result = 1;
			goto LUAT_PIN_SETUP_DONE;
		}
		else {
			LLOGD("luat_pin_set_iomux_info fail! pin %d tp %d id %d", pin, func_description.peripheral_type, func_description.peripheral_id);
		}
	}
	else {
		LLOGD("luat_pin_get_iomux_info fail! pin %d tp %d id %d", pin, func_description.peripheral_type, func_description.peripheral_id);
	}
	if (func_name)
	{
		LLOGE("%.*s不可配置，请确认硬件手册上该功能可以复用在2个及以上的pin", name_len, func_name);
	}
	else
	{
		LLOGE("altfunction%d不可配置，请确认硬件手册上该功能可以复用在2个及以上的pin", altfun_id);
	}
LUAT_PIN_SETUP_DONE:
	return result;
}

// 加载过程
static int luat_pins_load_from_json(cJSON *root)
{
	cJSON *pins = cJSON_GetObjectItem(root, "pins");
	cJSON *item = NULL;
	cJSON *pin_item = NULL;
	cJSON *func_item = NULL;
	uint16_t pin = 0;
	const char* func = NULL;
	if (pins == NULL) {
		LLOGE("json without pins item!!!");
		return -101;
	}
	int pins_count = cJSON_GetArraySize(pins);
	if (pins_count < 1) {
		LLOGE("invaild pins item!!!");
		return -102;
	}
	if (pins_count == 0) {
		LLOGD("pins is emtry!!!");
		return -103;
	}
	for (size_t i = 0; i < pins_count; i++)
	{
		item = cJSON_GetArrayItem(pins, i);
		if (item == NULL) {
			LLOGW("emtry pins item[%d]??", i);
			continue;
		}
		if (!cJSON_IsArray(item)) {
			LLOGW("pins item[%d] is not array", i);
			continue;
		}
		pin_item = cJSON_GetArrayItem(item, 0);
		func_item = cJSON_GetArrayItem(item, 1);
		if (pin_item == NULL || func_item == NULL) {
			LLOGW("pins item[%d] is not vaild!!!", i);
			continue;
		}
		if (!cJSON_IsNumber(pin_item)) {
			LLOGW("pins item[%d] pin is not number", i);
			continue;
		}
		if (!cJSON_IsString(func_item) || func_item->valuestring == NULL) {
			LLOGW("pins item[%d] func is not string", i);
			continue;
		}
		pin = pin_item->valueint;
		func = func_item->valuestring;
		if (luat_pins_setup(pin, func, strlen(func), 0) != 1) {
			LLOGW("pins %d %s setup failed", pin, func);
			continue;
		}
	}
	

	return 0;
}

static int luat_pins_load_from_bin(const uint8_t *data, size_t len)
{
	LLOGE("not support bin file yet");
	return -5;
}

int luat_pins_load_from_file(const char* path) {
	size_t flen;
	int ret = -100;
	flen = luat_fs_fsize(path);
	if (flen < 1) {
		LLOGW("%s not exist!!", path);
		return -1;
	}
	if (flen > 16 * 1024) {
		LLOGW("%s too large!!", path);
		return -2;
	}
	uint8_t *data = (uint8_t *)luat_heap_malloc(flen);
	if (data == NULL) {
		LLOGW("no memory for loading %s", path);
		return -3;
	}
	FILE* fd = luat_fs_fopen(path, "rb");
	if (fd == NULL) {
		LLOGW("open %s failed", path);
		luat_heap_free(data);
		return -4;
	}
	if (luat_fs_fread(data, 1, flen, fd) != flen) {
		LLOGW("read %s failed", path);
		luat_heap_free(data);
		return -4;
	}
	luat_fs_fclose(fd);
	if (memcmp(path + strlen(path) - 4, ".bin", 4) == 0) {
		ret = luat_pins_load_from_bin(data, flen);
	}
	else if (memcmp(path + strlen(path) - 5, ".json", 5) == 0) {
		cJSON * root = cJSON_ParseWithLength((const char *)data, flen);
		if (root == NULL) {
			LLOGE("not valid json %s", path);
		}
		else {
			// 是否为debug模式
			if (cJSON_HasObjectItem(root, "pins_debug")) {
				cJSON *item = cJSON_GetObjectItem(root, "pins_debug");
				g_pins_debug = item->valueint;
				if (g_pins_debug) {
					LLOGI("pins debug模式开启");
				}
			}
			// 检查io电平配置
			if (cJSON_HasObjectItem(root, "iovolt")) {
				cJSON *item = cJSON_GetObjectItem(root, "iovolt");
				if(item->valueint >= 1800 && item->valueint <= 3300) {
					luat_pm_iovolt_ctrl(LUAT_PM_ALL_GPIO, item->valueint);
				}
			}
			ret = luat_pins_load_from_json((cJSON *)root);
			cJSON_Delete(root);
		}
	}
	else {
		LLOGE("unknown file type %s", path);
	}
	if (data) {
		luat_heap_free(data);
		data = NULL;
	}
	return ret;
}
