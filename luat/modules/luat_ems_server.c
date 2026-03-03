#include "luat_ems_server.h"
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include "cjson.h"

#define LUAT_LOG_TAG "ems"
#include "luat_log.h"

const char* ems_server_lua_code = "\
PROJECT = \"ems_svr_demo\"\n\
VERSION = \"1.0.0\"\n\
TAG = \"[EMS]\"\n\
\n\
sys = require(\"sys\")\n\
\n\
local post_body = {}\n\
local getip_data = {}\n\
local emg_svc_data = nil\n\
local interval = 10800000 -- 3小时上报一次\n\
\n\
-- 获取急救服务器地址\n\
local function getip(getip_type)\n\
    local key = post_body.reson_key..\"-\"..(post_body.device_id or \"\")\n\
    local url = \"https://gps.openluat.com/iam/iot/getip?key=\"..key..\"&type=\"..getip_type\n\
    log.info(TAG, \"getip请求URL:\", url)\n\
    -- 执行HTTP请求\n\
    local code,headers,body = http.request(\"GET\", url, nil, nil, nil, {timeout=5000}).wait()\n\
    log.info(TAG, \"getip响应\", \"HTTP Code:\", code, \"Body:\", body)\n\
    -- 添加对HTTP响应为空值的处理\n\
    if not body then\n\
        log.error(TAG, \"getip请求失败\", \"HTTP响应为空\")\n\
        return false, \"HTTP响应为空\"\n\
    end\n\
\n\
    -- 处理HTTP错误码\n\
    if code ~= 200 then\n\
        log.info(TAG, \"getip请求失败\", \"HTTP Code:\", code)\n\
        return false, \"HTTP请求失败: \" .. tostring(code)\n\
    end\n\
\n\
    -- 解析JSON响应,添加对解析失败的处理\n\
    local response_json = json.decode(body)\n\
    if not response_json then\n\
        return false, \"JSON解析失败: \" .. body\n\
    end\n\
\n\
    -- 检查服务器返回状态\n\
    if not response_json.msg then\n\
        log.error(TAG, \"getip响应格式错误\", \"缺少msg字段\")\n\
        return false, \"服务器响应格式错误: 缺少msg字段\"\n\
    end\n\
\n\
    if response_json.msg ~= \"ok\" then\n\
        log.error(TAG, \"服务器返回错误\", \"消息:\", response_json.msg)\n\
        return false, \"服务器返回错误: \" .. tostring(response_json.msg)\n\
    end\n\
    post_body.key = response_json.key\n\
\n\
    return true, response_json\n\
end\n\
\n\
-- 带重试的getip请求\n\
local function getip_with_retry(getip_type)\n\
    local retry_count = 0\n\
    local max_retry = 3\n\
    local success, result\n\
\n\
    while retry_count < max_retry do\n\
        success, result = getip(getip_type)\n\
        if success and result then\n\
            log.info(TAG, \"getip\", \"成功:\", success, \"结果:\", json.encode(result))\n\
            return true, result\n\
        end\n\
\n\
        retry_count = retry_count + 1\n\
        log.warn(TAG, \"getip重试\", \"次数:\", retry_count, \"错误:\", result)\n\
\n\
        if retry_count < max_retry then\n\
            sys.wait(5000) -- 等待5秒后重试\n\
        end\n\
    end\n\
\n\
    return false, \"getip请求失败, 已达最大重试次数 3次: \" .. (result or \"未知错误\")\n\
end\n\
\n\
-- 上报结果到服务器\n\
local function upload_report(message)\n\
    if not getip_data.report_url or not getip_data.key then\n\
        log.error(TAG, \"上报失败\", \"缺少report_url或key\")\n\
        return\n\
    end\n\
\n\
    local report_body = {\n\
        key = getip_data.key,\n\
        device_id = post_body.device_id or \"unknown\",\n\
        upload_time = os.date(\"%Y-%m-%d %H:%M:%S\"),\n\
        project = PROJECT,\n\
        device_version = rtos.version()..\"-\"..VERSION,\n\
        server_version = rtos.version()..\"-\"..VERSION,\n\
        msg = message\n\
    }\n\
    log.info(TAG, \"report\", getip_data.report_url, json.encode(report_body))\n\
    local code,headers,body = http.request(\"POST\", getip_data.report_url, nil, json.encode(report_body)).wait()\n\
    log.info(\"report\", code, json.encode(headers), body)\n\
end\n\
\n\
-- 处理FOTA升级回调\n\
local function fota_cb(ret)\n\
    log.info(TAG, \"fota\", ret)\n\
    upload_report(\"请求fotabin结果: \" .. tostring(ret))\n\
    if ret == 0 then\n\
        upload_report(\"升级成功\")\n\
        log.info(TAG, \"升级包下载成功,重启模块\")\n\
        emg_svc_data.power_normal = emg_svc_data.normal_max_count\n\
        io.writeFile(\"/emg_svc\", json.encode(emg_svc_data))\n\
        rtos.reboot()\n\
    end\n\
end\n\
\n\
-- 发起FOTA升级请求\n\
local function fota_request()\n\
    -- 获取getip服务\n\
    local success, getip_result = getip_with_retry(8)\n\
    if not success then\n\
        upload_report(\"获取getip服务失败, 错误信息: \" .. getip_result)\n\
        log.error(TAG, \"获取getip服务失败, \", getip_result)\n\
    else\n\
        log.info(TAG, \"获取getip服务成功, \", getip_result.msg)\n\
        getip_data.url = getip_result.url\n\
        getip_data.report_url = getip_result.report_url\n\
        getip_data.key = getip_result.key\n\
        getip_data.msg = getip_result.msg\n\
        log.info(TAG, \"getip_data\", getip_data.url, json.encode(post_body))\n\
        local code,headers,body = http.request(\"POST\", getip_data.url, nil, json.encode(post_body)).wait()\n\
        log.info(\"http\", code, json.encode(headers), body)\n\
        if code == 200 then\n\
            local response = json.decode(body)\n\
            if not response then\n\
                upload_report(\"fotabin error: JSON解析失败\")\n\
                log.error(TAG, \"fotabin error: JSON解析失败\")\n\
                return\n\
            end\n\
            log.info(TAG, \"fotabin response\", json.encode(response))\n\
            if response.code == 10 then\n\
                upload_report(\"请求下载升级文件\")\n\
                log.info(\"fota\", \"开始升级\")\n\
                -- fotabin\n\
                code, headers, body = http.request(\"GET\", response.fotabin, {[\"Host\"] = \"gps.openluat.com\"}, nil, {fota=true, timeout=10000}).wait()\n\
                log.info(\"fota download\", code, headers, body)\n\
                local ret = 4\n\
                if code == 200 or code == 206 then\n\
                    if body == 0 then\n\
                        ret = 4\n\
                        upload_report(\"升级文件内容为空\")\n\
                    else\n\
                        ret = 0\n\
                        if type(body) == \"string\" then\n\
                            upload_report(\"升级文件请求正常,文件大小: \" .. tostring(#body))\n\
                        elseif type(body) == \"number\" then\n\
                            upload_report(\"升级文件请求正常,文件大小: \" .. tostring(body))\n\
                        else\n\
                            upload_report(\"升级文件请求正常,body类型: \" .. type(body))\n\
                        end\n\
                    end\n\
                elseif code == -4 then\n\
                    ret = 1\n\
                elseif code == -5 then\n\
                    ret = 3\n\
                else\n\
                    ret = 4\n\
                end\n\
                fota_cb(ret)\n\
            end\n\
        else\n\
            log.error(TAG, \"获取fotabin url error: \" .. tostring(response.code), \", \", body)\n\
            upload_report(\"获取fotabin url error: \" .. tostring(response.code))\n\
        end\n\
    end\n\
end\n\
\n\
sys.taskInit(function()\n\
    local reason1, reason2, reason3 = pm.lastReson()\n\
    while true do\n\
        sys.wait(10000)\n\
        if wlan and not wlan.ready() then\n\
            wlan.connect(emg_svc_data.wifi_ssid, emg_svc_data.wifi_password)\n\
        end\n\
        log.info(TAG, \"version\", VERSION)\n\
        -- 当前网络状态\n\
        log.info(TAG, \"当前网络状态\", mobile.status() == 1 and \"已注册\" or \"未注册到网络\")\n\
        adc.open(adc.CH_VBAT)\n\
        adc.open(adc.CH_CPU)\n\
        post_body.reson_key = \"StWtlHHhrPkNdELu2MDSaNMMYMXCZ2Mx\"\n\
        post_body.core_ver = rtos.version()\n\
        post_body.hw_ver = hmeta.hwver() or \"unknown\"\n\
        post_body.model = rtos.bsp()\n\
        post_body.power_reson = reason3 or 0\n\
        post_body.vbat = adc.get(adc.CH_VBAT)\n\
        post_body.cpu_temp = adc.get(adc.CH_CPU)\n\
        adc.close(adc.CH_VBAT)\n\
        adc.close(adc.CH_CPU)\n\
        if mobile then\n\
            local server_cell = mobile.scell()\n\
            post_body.device_id = mobile.imei()\n\
            post_body.muid = mobile.muid()\n\
            post_body.iccid = mobile.iccid()\n\
            post_body.imsi = mobile.imsi()\n\
            post_body.rssi = mobile.rssi()\n\
            post_body.rsrq = mobile.rsrq()\n\
            post_body.rsrp = mobile.rsrp()\n\
            post_body.snr = mobile.snr()\n\
            post_body.band = server_cell.band or 0\n\
            post_body.mcc = server_cell.mcc or 0\n\
            post_body.mnc = server_cell.mnc or 0\n\
            post_body.cid = server_cell.cid or 0\n\
            post_body.earfcn = server_cell.earfcn or 0\n\
            post_body.pci = server_cell.pci or 0\n\
            post_body.tac = server_cell.tac or 0\n\
        elseif wlan then\n\
            post_body.device_id = wlan.getMac()\n\
            post_body.wifi_ssid = wlan.getSsid() or \"unknown ssid\"\n\
            post_body.wifi_password = wlan.getPassword() or \"unknown password\"\n\
            post_body.wifi_bssid = wlan.getBssid() or \"unknown bssid\"\n\
            post_body.wifi_ip = wlan.getIp() or \"unknown ip\"\n\
        end\n\
        log.info(TAG, \"device_info\", json.encode(post_body))\n\
        if not post_body.key then\n\
            getip_with_retry(8)\n\
        end\n\
    end\n\
end)\n\
\n\
sys.taskInit(function()\n\
    local data = io.readFile(\"/emg_svc\")\n\
    if data then\n\
        log.info(TAG, \"emg_svc\", data)\n\
        emg_svc_data = json.decode(data)\n\
        if emg_svc_data and emg_svc_data.interval then\n\
            interval = emg_svc_data.interval * 60000 -- 分钟转换为毫秒\n\
        end\n\
    end\n\
    while true do\n\
        log.info(TAG, \"emg_svc\", \"紧急服务 间隔\", interval / 60000, \"分钟请求一次升级\")\n\
        sys.wait(interval)\n\
        fota_request()\n\
    end\n\
end)\n\
\n\
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
                cJSON_SetStringValue(item, (const char*)value);
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

