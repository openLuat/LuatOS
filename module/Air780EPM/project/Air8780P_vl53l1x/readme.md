# Air8780P + VL53L1X 激光测距传感器低功耗数据采集与上报 Demo

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责 PRODUCT_KEY 定义、errDump 开启、网络驱动加载和业务模块调度
2. **app_vl53l1x_main.lua** - 业务逻辑主协调模块，实现双任务架构（PSM+超时管理 + 业务逻辑），调用各模块完成完整流程
3. **sensor_vl53l1x.lua** - VL53L1X 传感器驱动封装模块，含初始化、数据采集、关闭接口
4. **aircloud.lua** - 云平台数据上报模块，封装 excloud 和 MQTT 双通道上报，含 payload 构建
5. **fota_mgr.lua** - FOTA 远程升级管理模块，含版本文件管理、首次启动检测、升级检查
6. **psm_mgr.lua** - PSM+ 低功耗模式管理模块，含 LED 指示控制和深度休眠入口
7. **netdrv_device.lua** - 网络驱动设备模块
8. **netdrv/netdrv_4g.lua** - 4G 网卡驱动

### 1.2 扩展库模块

1. **exs_vl53l1x** - VL53L1X 激光测距传感器扩展库
2. **libfota2** - 远程升级扩展库
3. **excloud** - 合宙 IoT 平台数据交互扩展库

## 二、演示流程介绍

本 demo 采用双任务架构：

- **任务1（PSM+超时管理）**：到设定时间就进入 PSM+，期间等待 FOTA 消息，收到后等待升级结果（最长 10 分钟），超时或失败也进入 PSM+ 下次再试
- **任务2（业务逻辑）**：传感器采集 → 联网 → 双通道上报 → FOTA 检查 → PSM+

开机 → GPIO27 拉高(LED亮) → 检查FOTA后首次启动 → 传感器初始化 → 采集3次测距数据 → 关闭传感器 → 等待4G网络 → excloud连接 → 双通道(aircloud+MQTT)上报 → FOTA检查 → 进入PSM+模式休眠 → 定时唤醒后重复

## 三、硬件准备

### 3.1 硬件清单

- Air8780P 工业模组 × 1
- VL53L1X 激光测距传感器模块 × 1
- SIM 卡 × 1（4G 联网）
- 母对母杜邦线 × 4
- TYPE-C 数据线 × 1

### 3.2 接线配置

#### 3.2.1 VL53L1X 传感器接线

| Air8780P | VL53L1X |
|----------|---------|
| 3.3V | VIN |
| GND | GND |
| GPIO1 | SCL |
| GPIO2 | SDA |

> 说明：VL53L1X 传感器 I2C 地址默认 0x29，支持软件 I2C 和硬件 I2C 两种模式，本 demo 使用 GPIO1/GPIO2 软件 I2C 模式。

![](https://docs.openluat.com/cdn/image/Air8780P_vl53l1x.png)

#### 3.2.2 指示灯说明

| Air8780P | 功能 |
|----------|------|
| GPIO27 | LED 指示灯，正常工作状态拉高点亮，进入 PSM+ 前拉低熄灭 |

## 四、演示软件环境

### 4.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air780egh/luatos/common/download/) - 固件烧录和代码调试

### 4.2 内核固件

- [点击下载Air780EPM系列最新版本内核固件](https://docs.openluat.com/air780epm/luatos/firmware/780epm_version/)，demo所使用的是 LuatOS-SoC_V2046_Air780EPM 1号固件

### 4.3 脚本文件

1. **main.lua** - 主程序入口
2. **prj/prj_vl53l1x.lua** - 项目编排模块（业务协调/事件驱动）
3. **drv/netdrv_device.lua** - 网络驱动设备模块
4. **drv/drv_led.lua** - LED指示灯驱动（事件订阅：LED_SET_HIGH/LED_SET_LOW）
5. **drv/drv_psm.lua** - PSM+低功耗模式驱动（事件订阅：DRV_SET_PSM）
6. **sensor/sensor_vl53l1x.lua** - VL53L1X 传感器驱动封装模块
7. **cloud/aircloud.lua** - 云平台(excloud + MQTT)数据上报模块
8. **fota/fota_mgr.lua** - FOTA 远程升级管理模块
9. **netdrv/netdrv_4g.lua** - 4G 网卡驱动
9. **exs_vl53l1x** (扩展库) - VL53L1X 测距传感器驱动
10. **libfota2** (扩展库) - 远程升级
11. **excloud** (扩展库) - 合宙 IoT 平台

## 五、演示核心步骤

### 5.1 硬件准备

1. 按照接线表将 VL53L1X 传感器模块连接到 Air8780P 模组
2. 确认 SIM 卡已正确安装
3. 通过 TYPE-C USB 口供电
4. 检查所有接线无误，避免短路

### 5.2 软件配置

在 `main.lua` 中配置 PRODUCT_KEY：

```lua
PRODUCT_KEY = "PhbD7kCQg9Jt7vwCGgtdjQ6jIscQ2gJJ"  -- 请改为实际的PRODUCT_KEY
```

在 `app_vl53l1x_main.lua` 中可根据需求调整以下参数：

```lua
local CFG = {
    psm_entry_max_s   = 90,     -- 开机到进入PSM+的超时上限(秒)
    psm_sleep_min_s   = 15,     -- PSM+休眠时间(分钟)，唤醒后重新开始循环
    fota_wait_max_s   = 600,    -- FOTA等待最长时间(秒)，默认10分钟
    sensor_samples    = 3,      -- 每次唤醒后采集传感器的次数
}
```

如需更换 MQTT 服务器，修改 `app_vl53l1x_main.lua` 中 CFG 的 `mqtt_broker` 和 `mqtt_port`。

### 5.3 软件烧录

1. 使用 Luatools 选择最新内核固件
2. 下载本项目所有脚本文件
3. 将固件和脚本一起烧录到设备
4. 烧录成功后设备自动重启后开始运行

### 5.4 功能流程说明

#### 5.4.1 双任务架构

本 demo 同时运行两个任务：

**任务1（PSM+超时管理）**：开机后立即启动计时，最大等待 `psm_entry_max_s` 秒。期间等待 FOTA 消息：
- 未收到 FOTA 消息 → 到时间直接进入 PSM+
- 收到 `FOTA_UPGRADING` → 延长等待 FOTA 结果，最长 `fota_wait_max_s` 秒（默认 10 分钟）
  - FOTA 成功 → 上报升级结果后重启
  - FOTA 失败或超时 → 进入 PSM+，下次唤醒再试

**任务2（业务逻辑）**：完成传感器采集、联网上报、FOTA 检查后进入 PSM+

> 两个任务任意一个先到 PSM+ 入口时，系统在所有任务都阻塞后自动进入深度休眠。

#### 5.4.2 开机自检

1. 设备启动后，GPIO27 拉高（LED 点亮），表示进入正常工作状态
2. 检查版本标记文件：如果检测到 FOTA 升级后的首次启动，会在日志中打印升级前后版本信息
3. 初始化 VL53L1X 传感器，等待固件就绪、写入预设模式配置

#### 5.4.2 数据采集

1. 传感器初始化成功后，开始采集测距数据，默认采集 3 次
2. 每次采集间隔 500ms，日志中会打印每次采集的距离值和状态
3. 计算有效数据的平均值作为本次上报的测距结果

#### 5.4.3 数据上报

1. 等待 4G 网络就绪
2. 连接合宙 IoT 平台（aircloud）
3. 通过 aircloud 和 MQTT 双通道上报传感器数据：
   - aircloud：上报平均距离
   - MQTT：上报 JSON 格式完整数据，Topic 为 `IMEI/vl53l1x/up`

#### 5.4.4 FOTA 升级

1. 非 FOTA 后首次启动时，任务2检查 libfota2 远程升级，同时发布 `FOTA_UPGRADING` 消息通知任务1
2. 任务1收到消息后延长 PSM+ 等待时间，最长 `fota_wait_max_s` 秒（默认 10 分钟）
3. 任务2上报"FOTA: 正在检查/升级中"状态
4. 升级包下载成功后上报升级结果，然后重启模块
5. 重启后首次运行会上报升级前后版本对比信息，上报完成后删除版本标记文件
6. FOTA 超时（如网络不好）→ 进入 PSM+，下次唤醒再试

#### 5.4.5 PSM+ 低功耗

1. 所有业务处理完成后，配置深度休眠定时器
2. GPIO27 拉低（LED 熄灭）
3. 调用 `pm.power(pm.WORK_MODE, 3)` 进入 PSM+ 模式
4. 定时唤醒后系统重新启动，从 main.lua 开始执行

### 5.5 预期效果

- **数据采集**：每次开机自动采集 3 次距离数据，日志实时打印
- **联网上报**：aircloud 和 MQTT 双通道同时上报，数据格式完整
- **低功耗**：上报完成后进入 PSM+ 模式，功耗降至 uA 级别
- **定时唤醒**：默认 15 分钟（可配置）后唤醒，重复整个流程
- **日志如下：**

```
[2026-07-21 16:50:57.264][000000000.000] main_entry 708:SDK base line V017_p001.026
[2026-07-21 16:50:57.267][000000000.007] am_service_init 1372:Air780EPM_A11
[2026-07-21 16:50:57.268][000000000.007] am_get_chip_type 868:6bef6,8,4,31,8,EC718PM
[2026-07-21 16:50:57.270][000000000.007] am_service_init 1380:APB MP 102400000
[2026-07-21 16:50:57.273][000000000.048] bsp_user_init_io 417:io volt 3.3v 21
[2026-07-21 16:50:57.276][000000000.048] BSP_CustomInit 558:hardfault mode init 4
[2026-07-21 16:50:57.278][000000000.049] Uart_ChangeBR 1461:uart0, 6000000 6028985 26000000 69
[2026-07-21 16:50:57.284][000000000.070] I/pm poweron: Power/Reset
[2026-07-21 16:50:57.287][000000000.070] luat_pm_get_poweron_reason 336:ap 1, cp 1
[2026-07-21 16:50:57.290][000000000.070] I/pm poweron reason: 0 0 0
[2026-07-21 16:50:57.293][000000000.178] self_info 125:model Air780EPM_A11 imei 864317083866528 dbversion 0x405e3b06
[2026-07-21 16:50:57.295][000000000.178] self_info 127:firmware[1] BASIC fs 168kbyte script 256kbyte
[2026-07-21 16:50:57.300][000000000.178] I/main LuatOS@Air780EPM base 26.04 bsp V2046 32bit
[2026-07-21 16:50:57.304][000000000.178] I/main ROM Build: Jul  7 2026 20:39:17
[2026-07-21 16:50:57.307][000000000.180] W/pins /luadb/pins_air780epm.json not exist!!
[2026-07-21 16:50:57.311][000000000.182] D/main loadlibs luavm 1048568 14784 14784
[2026-07-21 16:50:57.315][000000000.183] D/main loadlibs sys   2366664 82956 89556
[2026-07-21 16:50:57.318][000000000.183] D/main loadlibs psram 2366664 82956 89556
[2026-07-21 16:50:57.320][000000000.200] I/user.main Air8780P_VL53L1X 001.999.000
[2026-07-21 16:50:57.322][000000000.236] D/user.libfota2 version -> 202607021200
[2026-07-21 16:50:57.327][000000000.272] D/user.httpplus version -> 202607021200
[2026-07-21 16:50:57.330][000000000.284] D/user.exmtn version -> 202607021200
[2026-07-21 16:50:57.332][000000000.289] D/user.excloud version -> 202607091431
[2026-07-21 16:50:57.334][000000000.293] I/user.app_vl53l1x ========== Air8780P VL53L1X 主任务启动 ==========
[2026-07-21 16:50:57.337][000000000.294] I/user.app_vl53l1x 配置: wait=60s psm=5min samples=3
[2026-07-21 16:50:57.343][000000000.294] I/user.app_vl53l1x GPIO27 HIGH
[2026-07-21 16:50:57.347][000000000.301] I/user.app_vl53l1x 保存版本信息到文件: 001.999.000,Air8780P_VL53L1X
[2026-07-21 16:50:57.373][000000000.302] I/user.app_vl53l1x 正在初始化VL53L1X传感器...
[2026-07-21 16:50:57.384][000000000.318] I/user.exs_vl53l1x 固件就绪 0x00E5=0x03
[2026-07-21 16:50:57.394][000000000.436] I/user.exs_vl53l1x 预设模式配置写入完成 (mode=standard)
[2026-07-21 16:50:57.402][000000000.440] I/user.exs_vl53l1x 芯片 MID=0xEA MT=0xCC
[2026-07-21 16:50:57.418][000000000.642] I/user.exs_vl53l1x 初始化完成，Standard Ranging 测距已启动
[2026-07-21 16:50:57.424][000000000.643] I/user.app_vl53l1x VL53L1X初始化成功
[2026-07-21 16:50:57.429][000000000.643] I/user.app_vl53l1x 开始采集传感器数据，采集次数=3
[2026-07-21 16:50:57.878][000000001.195] I/user.app_vl53l1x 采集[1/3] 距离=267mm 状态=测距成功
[2026-07-21 16:50:58.147][000000001.704] I/user.app_vl53l1x 采集[2/3] 距离=261mm 状态=测距成功
[2026-07-21 16:50:58.158][000000002.215] I/user.app_vl53l1x 采集[3/3] 距离=267mm 状态=测距成功
[2026-07-21 16:50:58.166][000000002.215] I/user.app_vl53l1x 采集完成: 有效3帧, 平均距离=265mm
[2026-07-21 16:50:58.177][000000002.216] I/user.app_vl53l1x 测距结果 = 265 mm (有效3帧, 原始数据=267,261,267)
[2026-07-21 16:50:58.188][000000002.216] I/user.app_vl53l1x 关闭VL53L1X传感器
[2026-07-21 16:50:58.196][000000002.222] I/user.exs_vl53l1x 传感器已关闭
[2026-07-21 16:50:58.208][000000002.222] I/user.app_vl53l1x 等待4G网络就绪...
[2026-07-21 16:50:58.214][000000002.222] W/user.app_vl53l1x 等待IP_READY 1 1
[2026-07-21 16:50:58.465][000000002.250] I/mobile sim0 sms ready
[2026-07-21 16:50:58.474][000000002.251] D/mobile cid1, state0
[2026-07-21 16:50:58.483][000000002.252] D/mobile bearer act 0, result 0
[2026-07-21 16:50:58.493][000000002.252] D/mobile NETIF_LINK_ON -> IP_READY
[2026-07-21 16:50:58.503][000000002.253] I/user.netdrv_4g IP_READY 10.51.56.19 255.255.255.255 0.0.0.0 nil
[2026-07-21 16:50:58.522][000000002.254] I/user.app_vl53l1x 4G网络已就绪 10.51.56.19 255.255.255.255 0.0.0.0 nil
[2026-07-21 16:50:58.538][000000002.255] I/user.app_vl53l1x 正在初始化excloud...
[2026-07-21 16:50:58.549][000000002.255] W/user.excloud.setup 不再需要主动配置use_getip
[2026-07-21 16:50:58.562][000000002.255] W/user.excloud.setup 不再需要主动配置device_type
[2026-07-21 16:50:58.582][000000002.257] I/mobile l_mobile_muid called
[2026-07-21 16:50:58.587][000000002.263] I/mobile l_mobile_muid ret=32
[2026-07-21 16:50:58.600][000000002.263] I/user.[excloud]4G设备 IMEI: 864317083866528 MUID: 20260702152525A860510A9885483051
[2026-07-21 16:50:58.613][000000002.265] I/user.[excloud]setup 初始化成功 设备ID: 864317083866528
[2026-07-21 16:50:58.626][000000002.265] I/user.[excloud]首次连接，获取服务器信息...
[2026-07-21 16:50:58.635][000000002.266] I/mobile l_mobile_muid called
[2026-07-21 16:50:58.652][000000002.267] I/mobile l_mobile_muid ret=32
[2026-07-21 16:50:58.670][000000002.268] I/user.[excloud]getip 类型: 3 key: unusedkey-864317083866528-20260702152525A860510A9885483051
[2026-07-21 16:50:58.680][000000002.278] D/socket connect to gps.openluat.com,443
[2026-07-21 16:50:58.694][000000002.279] dns_run 676:gps.openluat.com state 0 id 1 ipv6 0 use dns server0, try 0
[2026-07-21 16:50:58.707][000000002.297] D/mobile TIME_SYNC 0 tm 1784623860
[2026-07-21 16:50:58.716][000000002.321] dns_run 693:dns all done ,now stop
[2026-07-21 16:50:58.936][000000003.217] I/user.httpplus 服务器已完成响应
[2026-07-21 16:50:58.945][000000003.219] I/user.[excloud]getip响应 HTTP: 200 Body: 
[2026-07-21 16:50:58.950][000000003.220] {"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108,"auth_key":"PhbD7kCQg9Jt7vwCGgtdjQ6jIscQ2gJJ"},"imginfo":{"url":"https://api.luatos.com/iot/air_up/image","data_key":"f","data_param":{"key":"7nTSPfh2Pcporb2dNDrS2jforVJaacDWfQbuA","tip":""}},"audinfo":{"url":"https://api.luatos.com/iot/air_up/audio","data_key":"f","data_param":{"key":"7nTSPfh2Pcporb2dNDrS2jforVJaacDWfQbuA","tip":""}},"mtninfo":{"url":"https://api.luatos.com/iot/air_up/file","data_key":"f","data_param":{"key":"7nTSPfh2Pcporb2dNDrS2jforVJaacDWfQbuA","tip":""}}}
[2026-07-21 16:50:58.968][000000003.221] I/user.[excloud]TCP/UDP连接信息 host: 124.71.128.165 port: 9108 key: nil
[2026-07-21 16:50:58.973][000000003.221] I/user.[excloud]获取到图片上传信息
[2026-07-21 16:50:58.979][000000003.222] I/user.[excloud]获取到音频上传信息
[2026-07-21 16:50:58.994][000000003.222] I/user.[excloud]获取到运维日志上传信息
[2026-07-21 16:50:59.005][000000003.222] W/user.[excloud]未获取到二维码信息
[2026-07-21 16:50:59.012][000000003.223] I/user.[excloud]自动获取到auth_key
[2026-07-21 16:50:59.022][000000003.223] I/user.[excloud]getip 更新配置: 124.71.128.165 9108
[2026-07-21 16:50:59.029][000000003.223] I/user.[excloud]getip 成功: true
[2026-07-21 16:50:59.038][000000003.224] I/user.[excloud]服务器信息获取成功 host: 124.71.128.165 port: 9108 transport: tcp
[2026-07-21 16:50:59.043][000000003.224] I/user.[excloud]创建TCP连接
[2026-07-21 16:50:59.056][000000003.225] D/socket connect to 124.71.128.165,9108
[2026-07-21 16:50:59.067][000000003.227] I/user.[excloud]TCP连接结果 true false
[2026-07-21 16:50:59.071][000000003.227] I/user.[excloud]excloud service started
[2026-07-21 16:50:59.081][000000003.228] I/user.[excloud]excloud 自动心跳已启动，间隔 300 秒
[2026-07-21 16:50:59.088][000000003.282] I/user.[excloud]TCP socket cb userdata: 0C185A00 33554449 0
[2026-07-21 16:50:59.093][000000003.282] I/user.[excloud]TCP socket TCP连接成功
[2026-07-21 16:50:59.103][000000003.283] I/user.app_vl53l1x excloud连接成功
[2026-07-21 16:50:59.111][000000003.283] I/mobile l_mobile_muid called
[2026-07-21 16:50:59.117][000000003.285] I/mobile l_mobile_muid ret=32
[2026-07-21 16:50:59.120][000000003.285] I/user.[excloud] 发送鉴权请求
[2026-07-21 16:50:59.126][000000003.286] I/user.[excloud]构建发送数据 field: 16 type: 3 value: PhbD7kCQg9Jt7vwCGgtdjQ6jIscQ2gJJ-864317083866528-20260702152525A860510A9885483051
[2026-07-21 16:50:59.134][000000003.287] I/user.[excloud]tlv发送数据长度4 85
[2026-07-21 16:50:59.137][000000003.287] I/user.[excloud]构建消息头 seq: 2 len: 85 flags: 18 dev: 0186431708386652
[2026-07-21 16:50:59.147][000000003.290] I/user.app_vl53l1x excloud发送成功, 流水号: 2
[2026-07-21 16:50:59.151][000000003.290] I/user.[excloud]数据发送成功 101 字节
[2026-07-21 16:50:59.155][000000003.351] I/user.[excloud]TCP socket cb userdata: 0C185A00 33554450 0
[2026-07-21 16:50:59.161][000000003.352] I/user.[excloud]TCP socket 发送完成
[2026-07-21 16:50:59.165][000000003.411] I/user.[excloud]TCP socket cb userdata: 0C185A00 33554452 0
[2026-07-21 16:50:59.171][000000003.412] I/user.[excloud]TCP socket 收到数据 22 字节 01864317083866520001000600000000301100026F6B 44
[2026-07-21 16:50:59.181][000000003.413] I/user.[excloud]解析消息头 设备ID: 864317083866528 序列号: 1 消息长度: 6 协议版本: 0 需要回复: false UDP承载: false 包含auth_key: false
[2026-07-21 16:50:59.187][000000003.414] I/user.[excloud]鉴权成功 ok
[2026-07-21 16:50:59.193][000000003.415] I/user.app_vl53l1x excloud认证成功
[2026-07-21 16:50:59.198][000000003.417] I/user.[excloud]构建发送数据 field: 20 type: 5 value: 265
[2026-07-21 16:50:59.204][000000003.418] I/user.[excloud]tlv发送数据长度4 7
[2026-07-21 16:50:59.207][000000003.419] I/user.[excloud]构建消息头 seq: 3 len: 7 flags: 2 dev: 0186431708386652
[2026-07-21 16:50:59.211][000000003.421] I/user.app_vl53l1x excloud发送成功, 流水号: 3
[2026-07-21 16:50:59.215][000000003.421] I/user.[excloud]数据发送成功 23 字节
[2026-07-21 16:50:59.222][000000003.422] I/user.app_vl53l1x excloud数据上报成功
[2026-07-21 16:50:59.227][000000003.424] I/user.app_vl53l1x MQTT上报数据到: 864317083866528/vl53l1x/up
[2026-07-21 16:50:59.231][000000003.428] dns_run 676:lbsmqtt.airm2m.com state 0 id 2 ipv6 0 use dns server0, try 0
[2026-07-21 16:50:59.238][000000003.461] I/user.[excloud]TCP socket cb userdata: 0C185A00 33554450 0
[2026-07-21 16:50:59.243][000000003.462] I/user.[excloud]TCP socket 发送完成
[2026-07-21 16:50:59.247][000000003.471] dns_run 693:dns all done ,now stop
[2026-07-21 16:50:59.313][000000003.599] I/user.app_vl53l1x MQTT事件: conack nil
[2026-07-21 16:50:59.322][000000003.599] I/user.app_vl53l1x MQTT连接成功
[2026-07-21 16:50:59.328][000000003.601] I/user.app_vl53l1x MQTT已发布: {"distance_mm":265,"project":"Air8780P_VL53L1X","distances":[267,261,267],"imei":"864317083866528","valid_samples":3,"ts":1784623861,"version":"001.999.000"}
[2026-07-21 16:50:59.391][000000003.679] I/user.app_vl53l1x MQTT事件: sent 1
[2026-07-21 16:50:59.399][000000003.679] I/user.app_vl53l1x MQTT数据发送成功
[2026-07-21 16:50:59.405][000000003.681] I/mqtt mqtt closing socket netc:c1b7f28 mqtt_state:3
[2026-07-21 16:50:59.414][000000003.682] I/user.app_vl53l1x MQTT事件: disconnect 0
[2026-07-21 16:50:59.418][000000003.682] W/user.app_vl53l1x MQTT断开
[2026-07-21 16:50:59.429][000000003.683] I/user.app_vl53l1x MQTT事件: close nil
[2026-07-21 16:50:59.899][000000004.181] W/mqtt network_tx ret -1, closing socket
[2026-07-21 16:50:59.903][000000004.182] I/mqtt mqtt closing socket netc:c1b7f28 mqtt_state:0
[2026-07-21 16:50:59.907][000000004.182] I/mqtt mqtt closing socket netc:c1b7f28 mqtt_state:0
[2026-07-21 16:50:59.912][000000004.183] I/user.app_vl53l1x MQTT短连接结束，发送 成功
[2026-07-21 16:50:59.919][000000004.183] I/user.app_vl53l1x 开始检查FOTA升级...
[2026-07-21 16:50:59.924][000000004.186] I/user.app_vl53l1x 保存版本信息到文件: 001.999.000,Air8780P_VL53L1X
[2026-07-21 16:50:59.929][000000004.186] I/user.[excloud]构建发送数据 field: 20 type: 5 value: FOTA: 正在检查/升级中
[2026-07-21 16:50:59.940][000000004.188] I/user.[excloud]tlv发送数据长度4 32
[2026-07-21 16:50:59.944][000000004.188] I/user.[excloud]构建消息头 seq: 4 len: 32 flags: 2 dev: 0186431708386652
[2026-07-21 16:50:59.949][000000004.190] I/user.app_vl53l1x excloud发送成功, 流水号: 4
[2026-07-21 16:50:59.953][000000004.191] I/user.[excloud]数据发送成功 48 字节
[2026-07-21 16:50:59.957][000000004.191] I/user.app_vl53l1x 已上报FOTA升级状态
[2026-07-21 16:50:59.962][000000004.192] I/user.app_vl53l1x FOTA期间同时上报传感器数据: 265 mm
[2026-07-21 16:50:59.970][000000004.194] I/user.libfota2.url GET http://iot.openluat.com/api/site/firmware_upgrade?imei=864317083866528&project_key=PhbD7kCQg9Jt7vwCGgtdjQ6jIscQ2gJJ&firmware_name=Air8780P_VL53L1X_LuatOS-SoC_Air780EPM&version=2046.001.000
[2026-07-21 16:50:59.974][000000004.194] I/user.libfota2.imei/mac imei=864317083866528
[2026-07-21 16:50:59.978][000000004.195] I/user.libfota2.project_key PhbD7kCQg9Jt7vwCGgtdjQ6jIscQ2gJJ
[2026-07-21 16:50:59.982][000000004.195] I/user.libfota2.firmware_name Air8780P_VL53L1X_LuatOS-SoC_Air780EPM
[2026-07-21 16:50:59.985][000000004.195] I/user.libfota2.version 2046.001.000
[2026-07-21 16:50:59.988][000000004.197] dns_run 676:iot.openluat.com state 0 id 3 ipv6 0 use dns server0, try 0
[2026-07-21 16:50:59.995][000000004.241] dns_run 693:dns all done ,now stop
[2026-07-21 16:51:00.003][000000004.243] I/user.[excloud]TCP socket cb userdata: 0C185A00 33554450 0
[2026-07-21 16:51:00.006][000000004.243] I/user.[excloud]TCP socket 发送完成
[2026-07-21 16:51:00.149][000000004.393] I/fota write common data
[2026-07-21 16:51:00.573][000000004.809] I/fota common data done, now checking 0
[2026-07-21 16:51:00.583][000000004.815] I/fota common data md5 ok
[2026-07-21 16:51:00.586][000000004.815] I/fota only common data
[2026-07-21 16:51:00.590][000000004.815] I/fota 脚本地址匹配
[2026-07-21 16:51:00.594][000000004.849] I/fota fota type 0 ok!, wait reboot
[2026-07-21 16:51:00.599][000000004.852] I/http http close c1d7174
[2026-07-21 16:51:00.604][000000004.853] I/user.app_vl53l1x FOTA回调 ret= 0
[2026-07-21 16:51:00.611][000000004.853] I/user.app_vl53l1x FOTA升级包下载成功，准备重启
[2026-07-21 16:51:00.615][000000004.854] I/user.app_vl53l1x FOTA升级包已下载，重启模块
[2026-07-21 16:51:00.619][000000004.855] I/user.[excloud]构建发送数据 field: 20 type: 5 value: FOTA升级包下载成功, 升级前版本: 001.999.000
[2026-07-21 16:51:00.623][000000004.856] I/user.[excloud]tlv发送数据长度4 59
[2026-07-21 16:51:00.627][000000004.856] I/user.[excloud]构建消息头 seq: 5 len: 59 flags: 2 dev: 0186431708386652
[2026-07-21 16:51:00.633][000000004.859] I/user.app_vl53l1x excloud发送成功, 流水号: 5
[2026-07-21 16:51:00.646][000000004.859] I/user.[excloud]数据发送成功 75 字节
[2026-07-21 16:51:00.650][000000004.859] I/user.app_vl53l1x excloud数据上报成功
[2026-07-21 16:51:00.654][000000004.901] I/user.[excloud]TCP socket cb userdata: 0C185A00 33554450 0
[2026-07-21 16:51:00.657][000000004.902] I/user.[excloud]TCP socket 发送完成
[2026-07-21 16:51:01.663] 工具提示: diag com USB 断开连接 COM12 CommError,[WinError 22] 设备不识别此命令。
[2026-07-21 16:51:03.048] 工具提示: soc log port COM10打开成功
[2026-07-21 16:51:03.147] 工具提示: ap log port COM12打开成功
[2026-07-21 16:51:03.170] 工具提示: 用户虚拟串口 COM11
[2026-07-21 16:51:04.039][000000000.000] main_entry 708:SDK base line V017_p001.026
[2026-07-21 16:51:04.045][000000000.007] am_service_init 1372:Air780EPM_A11
[2026-07-21 16:51:04.050][000000000.007] am_get_chip_type 868:6bef6,8,4,31,8,EC718PM
[2026-07-21 16:51:04.064][000000000.007] am_service_init 1380:APB MP 102400000
[2026-07-21 16:51:04.078][000000000.048] bsp_user_init_io 417:io volt 3.3v 21
[2026-07-21 16:51:04.088][000000000.049] BSP_CustomInit 558:hardfault mode init 4
[2026-07-21 16:51:04.098][000000000.049] Uart_ChangeBR 1461:uart0, 6000000 6028985 26000000 69
[2026-07-21 16:51:04.105][000000000.070] I/pm poweron: Power/Reset
[2026-07-21 16:51:04.110][000000000.071] luat_pm_get_poweron_reason 336:ap 3, cp 2
[2026-07-21 16:51:04.121][000000000.071] I/pm poweron reason: 0 0 3
[2026-07-21 16:51:04.129][000000000.180] self_info 125:model Air780EPM_A11 imei 864317083866528 dbversion 0x405e3b06
[2026-07-21 16:51:04.144][000000000.180] self_info 127:firmware[1] BASIC fs 168kbyte script 256kbyte
[2026-07-21 16:51:04.151][000000000.181] I/main LuatOS@Air780EPM base 26.04 bsp V2046 32bit
[2026-07-21 16:51:04.156][000000000.181] I/main ROM Build: Jul  7 2026 20:39:17
[2026-07-21 16:51:04.161][000000000.183] W/pins /luadb/pins_air780epm.json not exist!!
[2026-07-21 16:51:04.177][000000000.185] D/main loadlibs luavm 1048568 14784 14784
[2026-07-21 16:51:04.184][000000000.185] D/main loadlibs sys   2366664 82956 89556
[2026-07-21 16:51:04.191][000000000.185] D/main loadlibs psram 2366664 82956 89556
[2026-07-21 16:51:04.206][000000000.203] I/user.main Air8780P_VL53L1X 001.999.001
[2026-07-21 16:51:04.216][000000000.241] D/user.libfota2 version -> 202607021200
[2026-07-21 16:51:04.228][000000000.276] D/user.httpplus version -> 202607021200
[2026-07-21 16:51:04.236][000000000.290] D/user.exmtn version -> 202607021200
[2026-07-21 16:51:04.249][000000000.294] D/user.excloud version -> 202607091431
[2026-07-21 16:51:04.272][000000000.298] I/user.app_vl53l1x ========== Air8780P VL53L1X 主任务启动 ==========
[2026-07-21 16:51:04.286][000000000.299] I/user.app_vl53l1x 配置: wait=60s psm=5min samples=3
[2026-07-21 16:51:04.300][000000000.299] I/user.app_vl53l1x GPIO27 HIGH
[2026-07-21 16:51:04.308][000000000.302] I/user.app_vl53l1x 检测到FOTA升级后的首次启动 升级前: PROJECT=Air8780P_VL53L1X VERSION=001.999.000 ; 升级后: PROJECT=Air8780P_VL53L1X VERSION=001.999.001
[2026-07-21 16:51:04.314][000000000.308] I/user.app_vl53l1x 保存版本信息到文件: 001.999.001,Air8780P_VL53L1X
[2026-07-21 16:51:04.321][000000000.309] I/user.app_vl53l1x FOTA升级后首次启动: 升级前: PROJECT=Air8780P_VL53L1X VERSION=001.999.000 ; 升级后: PROJECT=Air8780P_VL53L1X VERSION=001.999.001
[2026-07-21 16:51:04.336][000000000.309] I/user.app_vl53l1x 正在初始化VL53L1X传感器...
[2026-07-21 16:51:04.342][000000000.327] I/user.exs_vl53l1x 固件就绪 0x00E5=0x03
[2026-07-21 16:51:04.347][000000000.446] I/user.exs_vl53l1x 预设模式配置写入完成 (mode=standard)
[2026-07-21 16:51:04.361][000000000.449] I/user.exs_vl53l1x 芯片 MID=0xEA MT=0xCC
[2026-07-21 16:51:04.369][000000000.652] I/user.exs_vl53l1x 初始化完成，Standard Ranging 测距已启动
[2026-07-21 16:51:04.375][000000000.652] I/user.app_vl53l1x VL53L1X初始化成功
[2026-07-21 16:51:04.382][000000000.652] I/user.app_vl53l1x 开始采集传感器数据，采集次数=3
[2026-07-21 16:51:04.868][000000001.205] I/user.app_vl53l1x 采集[1/3] 距离=260mm 状态=测距成功
[2026-07-21 16:51:05.189][000000001.713] I/user.app_vl53l1x 采集[2/3] 距离=258mm 状态=测距成功
[2026-07-21 16:51:05.556][000000002.194] I/mobile sim0 sms ready
[2026-07-21 16:51:05.572][000000002.195] D/mobile cid1, state0
[2026-07-21 16:51:05.585][000000002.196] D/mobile bearer act 0, result 0
[2026-07-21 16:51:05.593][000000002.196] D/mobile NETIF_LINK_ON -> IP_READY
[2026-07-21 16:51:05.614][000000002.197] I/user.netdrv_4g IP_READY 10.32.104.76 255.255.255.255 0.0.0.0 nil
[2026-07-21 16:51:05.619][000000002.227] I/user.app_vl53l1x 采集[3/3] 距离=257mm 状态=测距成功
[2026-07-21 16:51:05.628][000000002.228] I/user.app_vl53l1x 采集完成: 有效3帧, 平均距离=258mm
[2026-07-21 16:51:05.640][000000002.229] I/user.app_vl53l1x 测距结果 = 258 mm (有效3帧, 原始数据=260,258,257)
[2026-07-21 16:51:05.654][000000002.229] I/user.app_vl53l1x 关闭VL53L1X传感器
[2026-07-21 16:51:05.669][000000002.234] I/user.exs_vl53l1x 传感器已关闭
[2026-07-21 16:51:05.682][000000002.234] I/user.app_vl53l1x 等待4G网络就绪...
[2026-07-21 16:51:05.695][000000002.234] I/user.app_vl53l1x 4G网络已就绪 10.32.104.76 255.255.255.255 0.0.0.0 nil
[2026-07-21 16:51:05.712][000000002.235] I/user.app_vl53l1x 正在初始化excloud...
[2026-07-21 16:51:05.724][000000002.235] W/user.excloud.setup 不再需要主动配置use_getip
[2026-07-21 16:51:05.734][000000002.236] W/user.excloud.setup 不再需要主动配置device_type
[2026-07-21 16:51:05.745][000000002.237] I/mobile l_mobile_muid called
[2026-07-21 16:51:05.753][000000002.239] I/mobile l_mobile_muid ret=32
[2026-07-21 16:51:05.768][000000002.239] I/user.[excloud]4G设备 IMEI: 864317083866528 MUID: 20260702152525A860510A9885483051
[2026-07-21 16:51:05.775][000000002.242] I/user.[excloud]setup 初始化成功 设备ID: 864317083866528
[2026-07-21 16:51:05.782][000000002.242] I/user.[excloud]首次连接，获取服务器信息...
[2026-07-21 16:51:05.794][000000002.243] I/mobile l_mobile_muid called
[2026-07-21 16:51:05.801][000000002.244] I/mobile l_mobile_muid ret=32
[2026-07-21 16:51:05.816][000000002.245] I/user.[excloud]getip 类型: 3 key: unusedkey-864317083866528-20260702152525A860510A9885483051
[2026-07-21 16:51:05.822][000000002.252] D/socket connect to gps.openluat.com,443
[2026-07-21 16:51:05.827][000000002.253] dns_run 676:gps.openluat.com state 0 id 1 ipv6 0 use dns server0, try 0
[2026-07-21 16:51:05.836][000000002.254] D/mobile TIME_SYNC 0 tm 1784623867
[2026-07-21 16:51:05.842][000000002.290] dns_run 693:dns all done ,now stop
[2026-07-21 16:51:05.848][000000003.123] I/user.httpplus 服务器已完成响应
[2026-07-21 16:51:05.862][000000003.125] I/user.[excloud]getip响应 HTTP: 200 Body: 
[2026-07-21 16:51:05.867][000000003.126] {"msg":"ok","conninfo":{"ipv4":"124.71.128.165","port":9108,"auth_key":"PhbD7kCQg9Jt7vwCGgtdjQ6jIscQ2gJJ"},"imginfo":{"url":"https://api.luatos.com/iot/air_up/image","data_key":"f","data_param":{"key":"7nTSPfh2Pcporb2dNDrS2jforVJaacDWfQbuA","tip":""}},"audinfo":{"url":"https://api.luatos.com/iot/air_up/audio","data_key":"f","data_param":{"key":"7nTSPfh2Pcporb2dNDrS2jforVJaacDWfQbuA","tip":""}},"mtninfo":{"url":"https://api.luatos.com/iot/air_up/file","data_key":"f","data_param":{"key":"7nTSPfh2Pcporb2dNDrS2jforVJaacDWfQbuA","tip":""}}}
[2026-07-21 16:51:05.877][000000003.127] I/user.[excloud]TCP/UDP连接信息 host: 124.71.128.165 port: 9108 key: nil
[2026-07-21 16:51:05.888][000000003.127] I/user.[excloud]获取到图片上传信息
[2026-07-21 16:51:05.898][000000003.128] I/user.[excloud]获取到音频上传信息
[2026-07-21 16:51:05.912][000000003.128] I/user.[excloud]获取到运维日志上传信息
[2026-07-21 16:51:05.917][000000003.129] W/user.[excloud]未获取到二维码信息
[2026-07-21 16:51:05.923][000000003.129] I/user.[excloud]自动获取到auth_key
[2026-07-21 16:51:05.944][000000003.129] I/user.[excloud]getip 更新配置: 124.71.128.165 9108
[2026-07-21 16:51:05.951][000000003.130] I/user.[excloud]getip 成功: true
[2026-07-21 16:51:05.958][000000003.130] I/user.[excloud]服务器信息获取成功 host: 124.71.128.165 port: 9108 transport: tcp
[2026-07-21 16:51:05.977][000000003.131] I/user.[excloud]创建TCP连接
[2026-07-21 16:51:05.981][000000003.132] D/socket connect to 124.71.128.165,9108
[2026-07-21 16:51:05.987][000000003.133] I/user.[excloud]TCP连接结果 true false
[2026-07-21 16:51:05.997][000000003.133] I/user.[excloud]excloud service started
[2026-07-21 16:51:06.008][000000003.134] I/user.[excloud]excloud 自动心跳已启动，间隔 300 秒
[2026-07-21 16:51:06.018][000000003.170] I/user.[excloud]TCP socket cb userdata: 0C1859C8 33554449 0
[2026-07-21 16:51:06.024][000000003.170] I/user.[excloud]TCP socket TCP连接成功
[2026-07-21 16:51:06.028][000000003.171] I/user.app_vl53l1x excloud连接成功
[2026-07-21 16:51:06.038][000000003.171] I/mobile l_mobile_muid called
[2026-07-21 16:51:06.048][000000003.173] I/mobile l_mobile_muid ret=32
[2026-07-21 16:51:06.053][000000003.173] I/user.[excloud] 发送鉴权请求
[2026-07-21 16:51:06.056][000000003.173] I/user.[excloud]构建发送数据 field: 16 type: 3 value: PhbD7kCQg9Jt7vwCGgtdjQ6jIscQ2gJJ-864317083866528-20260702152525A860510A9885483051
[2026-07-21 16:51:06.061][000000003.175] I/user.[excloud]tlv发送数据长度4 85
[2026-07-21 16:51:06.069][000000003.175] I/user.[excloud]构建消息头 seq: 2 len: 85 flags: 18 dev: 0186431708386652
[2026-07-21 16:51:06.082][000000003.177] I/user.app_vl53l1x excloud发送成功, 流水号: 2
[2026-07-21 16:51:06.087][000000003.178] I/user.[excloud]数据发送成功 101 字节
[2026-07-21 16:51:06.090][000000003.230] I/user.[excloud]TCP socket cb userdata: 0C1859C8 33554450 0
[2026-07-21 16:51:06.094][000000003.230] I/user.[excloud]TCP socket 发送完成
[2026-07-21 16:51:06.104][000000003.275] I/user.[excloud]TCP socket cb userdata: 0C1859C8 33554452 0
[2026-07-21 16:51:06.109][000000003.276] I/user.[excloud]TCP socket 收到数据 22 字节 01864317083866520001000600000000301100026F6B 44
[2026-07-21 16:51:06.115][000000003.277] I/user.[excloud]解析消息头 设备ID: 864317083866528 序列号: 1 消息长度: 6 协议版本: 0 需要回复: false UDP承载: false 包含auth_key: false
[2026-07-21 16:51:06.120][000000003.278] I/user.[excloud]鉴权成功 ok
[2026-07-21 16:51:06.124][000000003.279] I/user.app_vl53l1x excloud认证成功
[2026-07-21 16:51:06.127][000000003.281] I/user.[excloud]构建发送数据 field: 20 type: 5 value: 258
[2026-07-21 16:51:06.137][000000003.282] I/user.[excloud]构建发送数据 field: 20 type: 5 value: FOTA升级成功: 升级前: PROJECT=Air8780P_VL53L1X VERSION=001.999.000 ; 升级后: PROJECT=Air8780P_VL53L1X VERSION=001.999.001
[2026-07-21 16:51:06.140][000000003.283] I/user.[excloud]tlv发送数据长度4 142
[2026-07-21 16:51:06.149][000000003.284] I/user.[excloud]构建消息头 seq: 3 len: 142 flags: 2 dev: 0186431708386652
[2026-07-21 16:51:06.154][000000003.286] I/user.app_vl53l1x excloud发送成功, 流水号: 3
[2026-07-21 16:51:06.158][000000003.287] I/user.[excloud]数据发送成功 158 字节
[2026-07-21 16:51:06.166][000000003.287] I/user.app_vl53l1x excloud数据上报成功
[2026-07-21 16:51:06.170][000000003.289] I/user.app_vl53l1x MQTT上报数据到: 864317083866528/vl53l1x/up
[2026-07-21 16:51:06.174][000000003.293] dns_run 676:lbsmqtt.airm2m.com state 0 id 2 ipv6 0 use dns server0, try 0
[2026-07-21 16:51:06.181][000000003.339] I/user.[excloud]TCP socket cb userdata: 0C1859C8 33554450 0
[2026-07-21 16:51:06.186][000000003.340] I/user.[excloud]TCP socket 发送完成
[2026-07-21 16:51:06.191][000000003.356] dns_run 693:dns all done ,now stop
[2026-07-21 16:51:06.196][000000003.476] I/user.app_vl53l1x MQTT事件: conack nil
[2026-07-21 16:51:06.200][000000003.476] I/user.app_vl53l1x MQTT连接成功
[2026-07-21 16:51:06.205][000000003.478] I/user.app_vl53l1x MQTT已发布: {"fota_info":"FOTA升级成功: 升级前: PROJECT=Air8780P_VL53L1X VERSION=001.999.000 ; 升级后: PROJECT=Air8780P_VL53L1X VERSION=001.999.001","distance_mm":258,"project":"Air8780P_VL53L1X","distances":[260,258,257],"imei":"864317083866528","valid_samples":3,"ts":1784623867,"version":"001.999.001"}
[2026-07-21 16:51:06.215][000000003.550] I/user.app_vl53l1x MQTT事件: sent 1
[2026-07-21 16:51:06.219][000000003.551] I/user.app_vl53l1x MQTT数据发送成功
[2026-07-21 16:51:06.229][000000003.552] I/mqtt mqtt closing socket netc:c1b7f28 mqtt_state:3
[2026-07-21 16:51:06.233][000000003.554] I/user.app_vl53l1x MQTT事件: disconnect 0
[2026-07-21 16:51:06.240][000000003.554] W/user.app_vl53l1x MQTT断开
[2026-07-21 16:51:06.244][000000003.555] I/user.app_vl53l1x MQTT事件: close nil
[2026-07-21 16:51:06.610][000000004.054] W/mqtt network_tx ret -1, closing socket
[2026-07-21 16:51:06.616][000000004.054] I/mqtt mqtt closing socket netc:c1b7f28 mqtt_state:0
[2026-07-21 16:51:06.621][000000004.054] I/mqtt mqtt closing socket netc:c1b7f28 mqtt_state:0
[2026-07-21 16:51:06.625][000000004.055] I/user.app_vl53l1x MQTT短连接结束，发送 成功
[2026-07-21 16:51:06.635][000000004.055] I/user.app_vl53l1x 发送完成，进入PSM+模式
[2026-07-21 16:51:06.639][000000004.055] I/user.app_vl53l1x 准备进入PSM+模式，休眠5分钟后唤醒
[2026-07-21 16:51:06.651][000000004.056] I/user.app_vl53l1x 关闭VL53L1X传感器
[2026-07-21 16:51:06.655][000000004.056] I/user.app_vl53l1x GPIO27 LOW
[2026-07-21 16:51:06.663][000000004.057] I/user.app_vl53l1x 深度休眠定时器已设置: 300000 ms
[2026-07-21 16:51:06.922][000000004.367] net_lwip_tcp_err_cb 662:adapter 1 socket 1 not closing, but error -13
```

### 5.6 故障排除

1. **VL53L1X 传感器初始化失败**：
   - 检查 I2C 接线是否正确（GPIO1-SCL、GPIO2-SDA、3.3V、GND）
   - 确认传感器供电正常（3.3V）
   - 检查传感器 I2C 地址是否默认 0x29（可通过读写 0x010F 寄存器验证，应返回 0xEA）

2. **测距数据一直为无效（串扰信号）**：
   - 传感器前方可能有遮挡物
   - 传感器距离目标过近（< 10mm）
   - 环境光太强或目标表面反射率过低
   - 可通过 `calibrate_xtalk()` API 进行串扰校准

3. **无法联网**：
   - 检查 SIM 卡是否正确安装、是否有流量
   - 检查天线是否连接
   - 检查网络信号强度

4. **无法进入 PSM+ 模式**：
   - 检查是否有其他任务未阻塞
   - 确认 `pm.power(pm.WORK_MODE, 3)` 已执行

5. **PSM+ 模式下传感器功耗偏高（320µA）**：
   - 传感器模块始终上电，软件待机下模块上的 LDO/电平转换芯片仍会消耗电流
   - 如需降低，可使用 VL53L1X 的 XSHUT 引脚（硬件断电），接线时把 XSHUT 接到模组空闲 GPIO，
     `setup` 时传入 `{xshut = GPIO号}`，进入 PSM+ 前会自动拉低 XSHUT 彻底关断传感器

5. **MQTT 数据未收到**：
   - 确认 Topic 正确（格式：`IMEI/vl53l1x/up`）
   - 检查 MQTT 服务器地址和端口配置是否正确
   - 日志中查看 `MQTT数据发送成功` 是否打印

### 5.7 扩展功能建议

- 串扰校准：使用 `exs_vl53l1x.calibrate_xtalk()` API 配合白纸板进行校准，校准值传入 `setup({xtalk_offset = value})` 即可
- 中断模式：VL53L1X 支持 GPIO1 中断，可配置为回调模式或轮询模式，详见 [exs_vl53l1x 扩展库说明](https://docs.openluat.com/osapi/ext/sensor/exs_vl53l1x/)
- 三档测距模式：支持 standard（约 2.9m）/ short（约 1.36m，抗强光）/ long（约 4.6m）三种模式，在 `setup` 时通过 `range_mode` 参数设置
