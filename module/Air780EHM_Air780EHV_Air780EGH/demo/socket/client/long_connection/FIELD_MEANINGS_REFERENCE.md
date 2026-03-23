# FIELD_MEANINGS 字段含义对照表(Aircloud字段表)

本文档基于 `libs/excloud.lua` 中的 FIELD_MEANINGS 定义整理。

---

## 一、控制信令类型 (16-255)

| 字段名称 | 数值 | 含义 |
|---------|------|------|
| AUTH_REQUEST | 16 | 鉴权请求 |
| AUTH_RESPONSE | 17 | 鉴权回复 |
| REPORT_RESPONSE | 18 | 上报回应 |
| CONTROL_COMMAND | 19 | 控制命令 |
| CONTROL_RESPONSE | 20 | 控制回应 |
| IRTU_DOWN | 21 | iRTU下行命令 |
| IRTU_UP | 22 | iRTU上行回复 |

---

## 二、文件上传控制信令 (23-24)

| 字段名称 | 数值 | 含义 |
|---------|------|------|
| FILE_UPLOAD_START | 23 | 文件上传开始通知 |
| FILE_UPLOAD_FINISH | 24 | 文件上传完成通知 |

---

## 三、运维日志控制信令 (25-27)

| 字段名称 | 数值 | 含义 |
|---------|------|------|
| MTN_LOG_UPLOAD_REQ_SIGNAL | 25 | 运维日志上传请求 - 下行（信令类型） |
| MTN_LOG_UPLOAD_RESP_SIGNAL | 26 | 运维日志上传响应 - 上行（信令类型） |
| MTN_LOG_UPLOAD_STATUS_SIGNAL | 27 | 运维日志上传状态 - 上行（信令类型） |

---

## 四、传感类 (256-511)

| 字段名称 | 数值 | 含义 |
|---------|------|------|
| TEMPERATURE | 256 | 温度 |
| HUMIDITY | 257 | 湿度 |
| PARTICULATE | 258 | 颗粒数 |
| ACIDITY | 259 | 酸度 |
| ALKALINITY | 260 | 碱度 |
| ALTITUDE | 261 | 海拔 |
| WATER_LEVEL | 262 | 水位 |
| ENV_TEMPERATURE | 263 | CPU温度/环境温度 |
| POWER_METERING | 264 | 电量计量 |

---

## 五、资产管理类 (512-767)

| 字段名称 | 数值 | 含义 |
|---------|------|------|
| GNSS_LONGITUDE | 512 | GNSS经度 |
| GNSS_LATITUDE | 513 | GNSS纬度 |
| SPEED | 514 | 行驶速度 |
| GNSS_CN | 515 | 最强的4颗GNSS卫星的CN |
| SATELLITES_TOTAL | 516 | 搜到的所有卫星数 |
| SATELLITES_VISIBLE | 517 | 可见卫星数 |
| HEADING | 518 | 航向角 |
| LOCATION_METHOD | 519 | 基站定位/GNSS定位标识 |
| GNSS_INFO | 520 | GNSS芯片型号和固件版本号 |
| DIRECTION | 521 | 方向 |

---

## 六、设备参数类 (768-1023)

| 字段名称 | 数值 | 含义 |
|---------|------|------|
| HEIGHT | 768 | 高度 |
| WIDTH | 769 | 宽度 |
| ROTATION_SPEED | 770 | 转速 |
| BATTERY_LEVEL | 771 | 电量(mV) |
| SERVING_CELL | 772 | 驻留频段 |
| CELL_INFO | 773 | 驻留小区和邻区 |
| COMPONENT_MODEL | 774 | 元器件型号 |
| GPIO_LEVEL | 775 | GPIO高低电平 |
| BOOT_REASON | 776 | 开机原因 |
| BOOT_COUNT | 777 | 开机次数 |
| SLEEP_MODE | 778 | 休眠模式 |
| WAKE_INTERVAL | 779 | 定时唤醒间隔 |
| NETWORK_IP_TYPE | 780 | 设备入网的IP类型 |
| NETWORK_TYPE | 781 | 当前联网方式 |
| SIGNAL_STRENGTH_4G | 782 | 4G信号强度 |
| SIM_ICCID | 783 | SIM卡ICCID |
| FILE_UPLOAD_TYPE | 784 | 文件上传类型（1:图片, 2:音频） |
| FILE_NAME | 785 | 文件名称 |
| FILE_SIZE | 786 | 文件大小 |
| UPLOAD_RESULT_STATUS | 787 | 上传结果状态 |
| MTN_LOG_FILE_INDEX | 788 | 运维日志文件序号 |
| MTN_LOG_FILE_TOTAL | 789 | 运维日志文件总数 |
| MTN_LOG_FILE_SIZE | 790 | 运维日志文件大小 |
| MTN_LOG_UPLOAD_STATUS_FIELD | 791 | 运维日志上传状态 |
| MTN_LOG_FILE_NAME | 792 | 运维日志文件名称 |
| BADGE_TOTAL_DISK | 793 | 工牌总磁盘空间 |
| BADGE_AVAILABLE_DISK | 794 | 工牌剩余磁盘空间 |
| BADGE_TOTAL_MEM | 795 | 工牌总内存 |
| BADGE_AVAILABLE_MEM | 796 | 工牌剩余内存 |
| BADGE_RECORD_COUNT | 797 | 工牌录音数量 |
| **DEVICE_ID** | **798** | **设备号（4G模块使用IMEI，WiFi/蓝牙模块使用MAC地址）** |
| **VOLTAGE** | **799** | **电压** |

---

## 七、软件数据类 (1024-1279)

| 字段名称 | 数值 | 含义 |
|---------|------|------|
| LUA_CORE_ERROR | 1024 | Lua核心库错误上报 |
| LUA_EXT_ERROR | 1025 | Lua扩展卡错误上报 |
| LUA_APP_ERROR | 1026 | Lua业务错误上报 |
| FIRMWARE_VERSION | 1027 | 固件版本号 |
| SMS_FORWARD | 1028 | SMS转发 |
| CALL_FORWARD | 1029 | 来电转发 |

---

## 八、设备无关数据类 (1280-1535)

| 字段名称 | 数值 | 含义 |
|---------|------|------|
| TIMESTAMP | 1280 | 时间 |
| RANDOM_DATA | 1281 | 无意义数据 |

---

## 使用说明

在代码中使用时，需要先加载 excloud 模块：

```lua
local excloud = require "libs.excloud"
```

然后通过 `excloud.FIELD_MEANINGS.XXX` 访问对应的字段值，例如：

```lua
local device_id_field = excloud.FIELD_MEANINGS.DEVICE_ID  -- 值为 798
local voltage_field = excloud.FIELD_MEANINGS.VOLTAGE      -- 值为 799
```

---

## 数据类型参考 (DATA_TYPES)

| 类型名称 | 数值 | 说明 |
|---------|------|------|
| INTEGER | 0x0 | 整数 |
| FLOAT | 0x1 | 浮点数 |
| BOOLEAN | 0x2 | 布尔值 |
| ASCII | 0x3 | ASCII字符串 |
| BINARY | 0x4 | 二进制数据 |
| UNICODE | 0x5 | Unicode字符串 |

---

*文档生成时间：2026-03-20*
