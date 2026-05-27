#include "luat_ems_server.h"
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include "cJSON.h"

#define LUAT_LOG_TAG "ems"
#include "luat_log.h"

const char* ems_server_lua_code = "\
PROJECT = \"ems_svr_demo\"\
VERSION = \"1.0.0\"\
TAG = \"[EMS]\"\
sys = require(\"sys\")\
local post_body = {}\
local getip_data = {}\
local emg_svc_data = nil\
local interval = 10800000\
local function getip(getip_type)\
local key = post_body.reson_key..\"-\"..(post_body.device_id or \"\")\
local url = \"https://gps.openluat.com/iam/iot/getip?key=\"..key..\"&type=\"..getip_type\
log.info(TAG, \"getip url:\", url)\
local code,headers,body = http.request(\"GET\", url, nil, nil, nil, {timeout=5000}).wait()\
log.info(TAG, \"getip resp\", code, body)\
if not body then\
log.error(TAG, \"getip no response\")\
return false, \"no http response\"\
end\
if code ~= 200 then\
log.info(TAG, \"getip http error\", code)\
return false, \"http error: \" .. tostring(code)\
end\
local response_json = json.decode(body)\
if not response_json then\
return false, \"json decode fail: \" .. body\
end\
if not response_json.msg then\
log.error(TAG, \"getip no msg field\")\
return false, \"server response no msg\"\
end\
if response_json.msg ~= \"ok\" then\
log.error(TAG, \"server error\", response_json.msg)\
return false, \"server error: \" .. tostring(response_json.msg)\
end\
post_body.key = response_json.key\
return true, response_json\
end\
local function getip_with_retry(getip_type)\
local retry_count = 0\
local max_retry = 3\
local success, result\
while retry_count < max_retry do\
success, result = getip(getip_type)\
if success and result then\
return true, result\
end\
retry_count = retry_count + 1\
log.warn(TAG, \"getip retry\", retry_count, result)\
if retry_count < max_retry then\
sys.wait(5000)\
end\
end\
return false, \"getip max retry: \" .. (result or \"unknown\")\
end\
local function upload_report(message)\
if not getip_data.report_url or not getip_data.key then\
log.error(TAG, \"upload no url/key\")\
return\
end\
local report_body = {\
key = getip_data.key,\
device_id = post_body.device_id or \"unknown\",\
upload_time = os.date(\"%Y-%m-%d %H:%M:%S\"),\
project = PROJECT,\
device_version = rtos.version()..\"-\"..VERSION,\
server_version = rtos.version()..\"-\"..VERSION,\
msg = message\
}\
log.info(TAG, \"report\", getip_data.report_url, json.encode(report_body))\
local code,headers,body = http.request(\"POST\", getip_data.report_url, nil, json.encode(report_body)).wait()\
log.info(\"report\", code, body)\
end\
local function fota_cb(ret)\
log.info(TAG, \"fota\", ret)\
upload_report(\"fotabin ret: \" .. tostring(ret))\
if ret == 0 then\
upload_report(\"upgrade ok\")\
log.info(TAG, \"upgrade ok, reboot\")\
emg_svc_data.power_normal = emg_svc_data.normal_max_count\
io.writeFile(\"/emg_svc\", json.encode(emg_svc_data))\
rtos.reboot()\
end\
end\
local function fota_request()\
local success, getip_result = getip_with_retry(8)\
if not success then\
upload_report(\"getip fail: \" .. getip_result)\
log.error(TAG, \"getip fail\", getip_result)\
else\
log.info(TAG, \"getip ok\", getip_result.msg)\
getip_data.url = getip_result.url\
getip_data.report_url = getip_result.report_url\
getip_data.key = getip_result.key\
getip_data.msg = getip_result.msg\
log.info(TAG, \"getip_data\", getip_data.url)\
local code,headers,body = http.request(\"POST\", getip_data.url, nil, json.encode(post_body)).wait()\
log.info(\"http\", code, body)\
if code == 200 then\
local response = json.decode(body)\
if not response then\
upload_report(\"fotabin json fail\")\
log.error(TAG, \"fotabin json fail\")\
return\
end\
log.info(TAG, \"fotabin resp\", json.encode(response))\
if response.code == 10 then\
upload_report(\"request fota bin\")\
log.info(\"fota\", \"start\")\
code, headers, body = http.request(\"GET\", response.fotabin, {[\"Host\"] = \"gps.openluat.com\"}, nil, {fota=true, timeout=10000}).wait()\
log.info(\"fota download\", code, body)\
local ret = 4\
if code == 200 or code == 206 then\
if body == 0 then\
ret = 4\
upload_report(\"fota body empty\")\
else\
ret = 0\
if type(body) == \"string\" then\
upload_report(\"fota ok, size: \" .. tostring(#body))\
elseif type(body) == \"number\" then\
upload_report(\"fota ok, size: \" .. tostring(body))\
else\
upload_report(\"fota ok, type: \" .. type(body))\
end\
elseif code == -4 then\
ret = 1\
elseif code == -5 then\
ret = 3\
else\
ret = 4\
end\
fota_cb(ret)\
end\
else\
log.error(TAG, \"fotabin url error\", response.code)\
upload_report(\"fotabin url error: \" .. tostring(response.code))\
end\
end\
end\
sys.taskInit(function()\
local reason1, reason2, reason3 = pm.lastReson()\
while true do\
sys.wait(10000)\
if wlan and not wlan.ready() then\
wlan.connect(emg_svc_data.wifi_ssid, emg_svc_data.wifi_password)\
end\
log.info(TAG, \"ver\", VERSION)\
log.info(TAG, \"net status\", mobile.status() == 1 and \"reg\" or \"not reg\")\
adc.open(adc.CH_VBAT)\
adc.open(adc.CH_CPU)\
post_body.reson_key = \"StWtlHHhrPkNdELu2MDSaNMMYMXCZ2Mx\"\
post_body.core_ver = rtos.version()\
post_body.hw_ver = hmeta.hwver() or \"unknown\"\
post_body.model = rtos.bsp()\
post_body.power_reson = reason3 or 0\
post_body.vbat = adc.get(adc.CH_VBAT)\
post_body.cpu_temp = adc.get(adc.CH_CPU)\
adc.close(adc.CH_VBAT)\
adc.close(adc.CH_CPU)\
if mobile then\
local server_cell = mobile.scell()\
post_body.device_id = mobile.imei()\
post_body.muid = mobile.muid()\
post_body.iccid = mobile.iccid()\
post_body.imsi = mobile.imsi()\
post_body.rssi = mobile.rssi()\
post_body.rsrq = mobile.rsrq()\
post_body.rsrp = mobile.rsrp()\
post_body.snr = mobile.snr()\
post_body.band = server_cell.band or 0\
post_body.mcc = server_cell.mcc or 0\
post_body.mnc = server_cell.mnc or 0\
post_body.cid = server_cell.cid or 0\
post_body.earfcn = server_cell.earfcn or 0\
post_body.pci = server_cell.pci or 0\
post_body.tac = server_cell.tac or 0\
elseif wlan then\
post_body.device_id = wlan.getMac()\
post_body.wifi_ssid = wlan.getSsid() or \"unknown ssid\"\
post_body.wifi_password = wlan.getPassword() or \"unknown password\"\
post_body.wifi_bssid = wlan.getBssid() or \"unknown bssid\"\
post_body.wifi_ip = wlan.getIp() or \"unknown ip\"\
end\
log.info(TAG, \"device_info\", json.encode(post_body))\
if not post_body.key then\
getip_with_retry(8)\
end\
end\
end)\
sys.taskInit(function()\
local data = io.readFile(\"/emg_svc\")\
if data then\
log.info(TAG, \"emg_svc\", data)\
emg_svc_data = json.decode(data)\
if emg_svc_data and emg_svc_data.interval then\
interval = emg_svc_data.interval * 60000\
end\
end\
while true do\
log.info(TAG, \"emg_svc interval\", interval / 60000, \"min\")\
sys.wait(interval)\
fota_request()\
end\
end)\
sys.run()\
";

// 写入emergency service配置文件（单个字段）
void luat_ems_server_write_config(uint8_t config_type, void* value)
{
    FILE* fp = NULL;
    cJSON* root = NULL;
    
    // 首先读取现有配置
    if (luat_fs_fexist(EMG_SVC_FILE)) {
        char buf[EMG_SVC_FILE_SIZE] = {0};
        fp = luat_fs_fopen(EMG_SVC_FILE, "r");
        if (fp) {
            luat_fs_fread(buf, 1, sizeof(buf) - 1, fp);
            luat_fs_fclose(fp);
            root = cJSON_Parse(buf);
        }
    }
    
    // 如果文件不存在或解析失败，创建新对象
    if (!root) {
        root = cJSON_CreateObject();
    }
    
    // 根据config_type写入对应配置
    switch (config_type) {
        case EMS_SERVER_ENABLE: {
            cJSON* item = cJSON_GetObjectItem(root, "enable");
            if (item) {
                cJSON_SetNumberValue(item, *((uint8_t*)value));
            } else {
                cJSON_AddNumberToObject(root, "enable", *((uint8_t*)value));
            }
            break;
        }
        case EMS_SERVER_KEY: {
            cJSON* item = cJSON_GetObjectItem(root, "key");
            if (item) {
                cJSON_SetValuestring(item, (const char*)value);
            } else {
                cJSON_AddStringToObject(root, "key", (const char*)value);
            }
            break;
        }
        case EMS_SERVER_INTERVAL: {
            cJSON* item = cJSON_GetObjectItem(root, "interval");
            if (item) {
                cJSON_SetNumberValue(item, *((uint32_t*)value));
            } else {
                cJSON_AddNumberToObject(root, "interval", *((uint32_t*)value));
            }
            break;
        }
        case EMS_SERVER_EXCEPTION_MAX_COUNT: {
            cJSON* item = cJSON_GetObjectItem(root, "exception_max_count");
            if (item) {
                cJSON_SetNumberValue(item, *((uint8_t*)value));
            } else {
                cJSON_AddNumberToObject(root, "exception_max_count", *((uint8_t*)value));
            }
            break;
        }
        case EMS_SERVER_NORMAL_MAX_COUNT: {
            cJSON* item = cJSON_GetObjectItem(root, "normal_max_count");
            if (item) {
                cJSON_SetNumberValue(item, *((uint8_t*)value));
            } else {
                cJSON_AddNumberToObject(root, "normal_max_count", *((uint8_t*)value));
            }
            break;
        }
        case EMS_SERVER_POWER_EXCEPTION: {
            cJSON* item = cJSON_GetObjectItem(root, "power_exception");
            if (item) {
                cJSON_SetNumberValue(item, *((uint8_t*)value));
            } else {
                cJSON_AddNumberToObject(root, "power_exception", *((uint8_t*)value));
            }
            break;
        }
        case EMS_SERVER_POWER_NORMAL: {
            cJSON* item = cJSON_GetObjectItem(root, "power_normal");
            if (item) {
                cJSON_SetNumberValue(item, *((uint8_t*)value));
            } else {
                cJSON_AddNumberToObject(root, "power_normal", *((uint8_t*)value));
            }
            break;
        }
    }
    
    // 写入文件
    char* json_str = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    if (json_str) {
        fp = luat_fs_fopen(EMG_SVC_FILE, "w");
        if (fp) {
            luat_fs_fwrite(json_str, 1, strlen(json_str), fp);
            luat_fs_fclose(fp);
        }
        luat_heap_free(json_str);
    }
}

// 写入emergency service配置文件（全部字段）
void luat_ems_server_write_config_all(uint8_t enable, const char* key, uint32_t interval, uint8_t exception_max_count, uint8_t normal_max_count, uint8_t power_exception, uint8_t power_normal)
{
    FILE* fp = NULL;
    cJSON* root = cJSON_CreateObject();
    cJSON_AddNumberToObject(root, "enable", enable);
    cJSON_AddStringToObject(root, "key", key);
    cJSON_AddNumberToObject(root, "interval", interval);
    cJSON_AddNumberToObject(root, "exception_max_count", exception_max_count);
    cJSON_AddNumberToObject(root, "normal_max_count", normal_max_count);
    cJSON_AddNumberToObject(root, "power_exception", power_exception);
    cJSON_AddNumberToObject(root, "power_normal", power_normal);
    char* json_str = cJSON_PrintUnformatted(root);
    LLOGD("json_str: %s", json_str);
    cJSON_Delete(root);
    if (json_str) {
        fp = luat_fs_fopen(EMG_SVC_FILE, "w");
        if (fp) {
            luat_fs_fwrite(json_str, 1, strlen(json_str), fp);
            luat_fs_fclose(fp);
        }
        luat_heap_free(json_str);
    }
}

// 读取emergency service配置文件
void luat_ems_server_read_config(uint8_t config_type, void* value)
{
    FILE* fp = NULL;
	if (luat_fs_fexist(EMG_SVC_FILE)) {
		char buf[EMG_SVC_FILE_SIZE] = {0};
		fp = luat_fs_fopen(EMG_SVC_FILE, "r");
		if (fp) {
			luat_fs_fread(buf, 1, sizeof(buf) - 1, fp);
			luat_fs_fclose(fp);
			cJSON* root = cJSON_Parse(buf);
            if (root) {
                switch (config_type) {
                    case EMS_SERVER_ENABLE: {
                        cJSON* item = cJSON_GetObjectItem(root, "enable");
                        if (item) *((uint8_t*)value) = (uint8_t)item->valueint;
                        break;
                    }
                    case EMS_SERVER_KEY: {
                        cJSON* item = cJSON_GetObjectItem(root, "key");
                        if (item && item->valuestring) {
                            strncpy((char*)value, item->valuestring, 31); // 假设key长度不超过32，留一个字节给结束符
                            ((char*)value)[31] = '\0'; // 确保字符串以结束符结尾
                        }
                        break;
                    }
                    case EMS_SERVER_INTERVAL: {
                        cJSON* item = cJSON_GetObjectItem(root, "interval");
                        if (item) *((uint32_t*)value) = (uint32_t)item->valueint;
                        break;
                    }
                    case EMS_SERVER_EXCEPTION_MAX_COUNT: {
                        cJSON* item = cJSON_GetObjectItem(root, "exception_max_count");
                        if (item) *((uint8_t*)value) = (uint8_t)item->valueint;
                        break;
                    }
                    case EMS_SERVER_NORMAL_MAX_COUNT: {
                        cJSON* item = cJSON_GetObjectItem(root, "normal_max_count");
                        if (item) *((uint8_t*)value) = (uint8_t)item->valueint;
                        break;
                    }
                    case EMS_SERVER_POWER_EXCEPTION: {
                        cJSON* item = cJSON_GetObjectItem(root, "power_exception");
                        if (item) *((uint8_t*)value) = (uint8_t)item->valueint;
                        break;
                    }
                    case EMS_SERVER_POWER_NORMAL: {
                        cJSON* item = cJSON_GetObjectItem(root, "power_normal");
                        if (item) *((uint8_t*)value) = (uint8_t)item->valueint;
                        break;
                    }
                }
                cJSON_Delete(root);
            }
		}
	}
}

// 读取emergency service配置文件（全部字段）
void luat_ems_server_read_config_all(uint8_t* enable, char* key, uint32_t* interval, uint8_t* exception_max_count, uint8_t* normal_max_count, uint8_t* power_exception, uint8_t* power_normal)
{
    FILE* fp = NULL;
	if (luat_fs_fexist(EMG_SVC_FILE)) {
		char buf[EMG_SVC_FILE_SIZE] = {0};
		fp = luat_fs_fopen(EMG_SVC_FILE, "r");
		if (fp) {
			luat_fs_fread(buf, 1, sizeof(buf) - 1, fp);
			luat_fs_fclose(fp);
			cJSON* root = cJSON_Parse(buf);
            if (root) {
                cJSON* item = cJSON_GetObjectItem(root, "enable");
                if (item) *((uint8_t*)enable) = (uint8_t)item->valueint;
                item = cJSON_GetObjectItem(root, "key");
                if (item && item->valuestring) {
                    strncpy(key, item->valuestring, 31); // 假设key长度不超过32，留一个字节给结束符
                    key[31] = '\0'; // 确保字符串以结束符结尾
                }
                item = cJSON_GetObjectItem(root, "interval");
                if (item) *((uint32_t*)interval) = (uint32_t)item->valueint;
                item = cJSON_GetObjectItem(root, "exception_max_count");
                if (item) *((uint8_t*)exception_max_count) = (uint8_t)item->valueint;
                item = cJSON_GetObjectItem(root, "normal_max_count");
                if (item) *((uint8_t*)normal_max_count) = (uint8_t)item->valueint;
                item = cJSON_GetObjectItem(root, "power_exception");
                if (item) *((uint8_t*)power_exception) = (uint8_t)item->valueint;
                item = cJSON_GetObjectItem(root, "power_normal");
                if (item) *((uint8_t*)power_normal) = (uint8_t)item->valueint;
                cJSON_Delete(root);
                LLOGD("enable: %d, key: %s, interval: %d, exception_max_count: %d, normal_max_count: %d, power_exception: %d, power_normal: %d",
                    *enable, key, *interval, *exception_max_count, *normal_max_count, *power_exception, *power_normal);
            }
        }
    }
}

