# Air8101 微信语音 / 视频通话门禁界面（SmartDoor）

**微信功能还在实验阶段，后期需要搭配我们的小程序使用，小程序还在完善中，敬请期待**

**注意：当前项目只能显示UI，无法实际测试**

基于 Air8101B 整机的触屏通话工程，使用 HX8282 RGB 屏、GT911 触摸和 AirUI 构建门禁主页、语音通话页及视频通话页，通过固件内置 `tc_iot` 接入腾讯云 IoT 微信通话。设备可从屏幕发起呼叫，也可接听或拒接微信侧来电。

- 项目名（PROJECT）：`SmartDoor`
- 项目版本（VERSION）：`001.000.000`，定义于 [app/main.lua](app/main.lua)
- 硬件基准：Air8101B 整机，10.1 寸 HX8282 RGB 1024×600，GT911 触摸
- UI：AirUI，中文字体 `MiSans_gb2312.ttf`
- 网络：WiFi STA，2.4 GHz
- 通话后端：固件内置 `tc_iot`；可选择本地界面演示
- 摄像头：USB UVC；腾讯后端工作时由 SDK 接管
- 主要配置：[config/hw_config.lua](config/hw_config.lua)、[config/tc_iot_config.lua](config/tc_iot_config.lua)

**首次使用需替换两份配置中的占位符。** 当前默认 `demo_mode=false`、`wechat.local_demo=false`，没有可用通话后端时，点击外呼按钮会提示未就绪，不会自动模拟外呼接通。

**当前实现范围：** 工程包含设备侧界面、网络管理、通话状态机与 SDK 适配，不包含微信小程序源码或业务服务端。视频页的远端画面和本地预览目前是文字占位区，尚未在 UI 代码中绑定视频渲染；主页“已布防”和设备编号是固定展示文字，也未实现门锁控制。

## 阅读顺序

- 首次上机：第二节硬件 → 第三、四节配置 → 第五节烧录 → 第六节操作。
- 微信联调：第七节业务登记接口 → 第八节呼叫状态及事件 → 第九节摄像头。
- 仅看界面：第十节演示模式。
- 故障排查：第十一节日志与超时 → 第十二节验收及限制。

---

## 一、目录结构与模块职责

### 1.1 工程目录

```text
wx_call/
├── app/
│   └── main.lua                 入口、LCD / 触摸 / UI 初始化与服务启动
├── config/
│   ├── hw_config.lua            硬件、WiFi、界面和通话行为配置
│   └── tc_iot_config.lua        腾讯设备配置、小程序参数、业务后端配置
├── drivers/
│   ├── lcd_drv.lua              引脚复用、上电时序、LCD、AirUI、字体、背光
│   ├── tp_drv.lua               GT911 初始化、软件 I2C 回退及触摸绑定
│   └── usb_cam.lua              本地 UVC 状态探测、摄像头所有权切换
├── network/
│   └── net_mgr.lua              WiFi 扫描、连接、RSSI、IP 和校时
├── call/
│   ├── wx_call.lua              微信通道状态，供顶栏和主页显示
│   ├── call_service.lua         tc_iot 初始化、授权用户选择、登记与媒体控制
│   └── call_mgr.lua             外呼、来电、接听、拒接、挂断、计时及按钮状态
├── ui/
│   ├── ui_theme.lua             颜色主题
│   ├── ui_main.lua              页面总装、切换、消息订阅及提示浮层
│   ├── ui_status.lua            顶栏：网络、时间、摄像头、微信状态
│   ├── ui_idle.lua              首页状态卡和语音 / 视频入口
│   └── ui_call.lua              语音 / 视频通话页面及操作按钮
├── assets/
│   └── fonts/
│       └── MiSans_gb2312.ttf     中文字体
└── README.md                    本说明，不参与烧录
```

**入口实际在 `app/main.lua`，不是工程根目录。** 添加下载文件时必须包含此文件。子目录用于电脑端分类，当前脚本以 `require "hw_config"`、`require "call_mgr"` 等不带目录的名称加载，需按文件名打包到脚本区。

| 电脑端文件 | 运行时用途 |
| --- | --- |
| `app/main.lua` | 设备入口 `main.lua` |
| `config/hw_config.lua` | `require "hw_config"` |
| `config/tc_iot_config.lua` | `require "tc_iot_config"` |
| `drivers/lcd_drv.lua` | `require "lcd_drv"` |
| `assets/fonts/MiSans_gb2312.ttf` | `/luadb/MiSans_gb2312.ttf`，作为根目录字体的回退 |

不要因保留电脑端层级而将字体只放到 `/luadb/assets/fonts/`；当前字体加载器不会查找该路径。平铺文件时检查没有同名脚本冲突。

### 1.2 模块之间如何协作

| 层次 | 模块 | 职责 |
| --- | --- | --- |
| 启动 | `main.lua` | 输出版本、可选错误转储、初始化显示和触摸、构建 UI、启动通话服务 |
| 硬件 | `lcd_drv` / `tp_drv` | 确保上电与屏幕尺寸确定后，再绑定触摸并开背光 |
| 网络 | `net_mgr` | 更新联网状态并发布 `NET_STATUS`，供 UI 和通话服务使用 |
| 后端 | `call_service` | 加载内置 SDK、等待网络、设置时间、初始化设备与 VoIP、处理业务登记 |
| 业务 | `call_mgr` | 管理 `idle/dialing/ringing/connecting/talking`，将按钮操作转换为后端调用 |
| 状态 | `wx_call` | 将后端与呼叫状态转换为“未就绪 / 空闲 / 连接中 / 来电 / 通话中” |
| UI | `ui_main` 与各页面 | 订阅业务消息、切换页面、更新按钮与计时 |
| 摄像头 | `usb_cam` / `call_service` | 根据所有权选择本地探测或 SDK 状态轮询 |

耗时的 HTTP 登记、SDK 呼叫、接听和挂断由任务协程执行。AirUI 点击回调只触发业务操作，不直接等待 `http.request(...).wait()`。

### 1.3 启动顺序

```text
app/main.lua
  → 输出 SmartDoor / 001.000.000
  → errDump 存在时启用错误转储
  → 加载配置、UI、网络、摄像头和通话模块
  → 初始化任务等待 50 ms
  → 引脚复用、外设上电、LCD 初始化
  → AirUI、RGB565、帧缓冲、中文字体
  → GT911 初始化并绑定 AirUI
  → 打开背光，构建主页并发布 UI_READY
  → call_service.start()，等待约 200 ms 后初始化通话后端
  → sys.run() 事件循环持续运行
```

网络和摄像头任务在模块加载时创建，先等待 `UI_READY`，最长 8 秒。LCD 或 AirUI 初始化失败时，主初始化任务返回，不构建 UI，也不会从该任务启动通话服务。触摸初始化的返回值当前未被入口检查，触摸失败时仍可能看到完整界面。

当前 `main.lua` 直接使用全局 `sys`，没有显式 `sys = require "sys"`。烧录环境需确认已提供该全局；若启动报 `sys` 为 nil，应首先核对固件 / 入口的系统库初始化，不是通话参数问题。

---

## 二、硬件配置与上电时序

### 2.1 演示环境

| 项目 | 用途 / 要求 |
| --- | --- |
| Air8101B 整机及配套底板 | 当前硬件参数以 10 寸整机配置为基准 |
| HX8282 RGB 屏 | 1024×600，界面按这一尺寸设计 |
| GT911 触摸屏 | 默认硬件 I2C1，失败时尝试软件 I2C |
| USB UVC 摄像头 | 视频上行测试，接入实际硬件支持的 USB 端口 |
| 配套音频硬件 | 配置注释以外置 Air1103 音频为基准；本目录没有独立 Air1103 初始化模块 |
| 2.4 GHz WiFi 热点 | 数据联网和腾讯通话接入 |
| 具备授权关系的微信小程序及用户 | 真实来电 / 外呼验收 |
| 业务后端 | 接收设备外呼登记；本目录未提供其实现 |
| 电脑、下载连接线及稳定供电 | 烧录与完整串口日志采集 |

固件需支持本工程用到的 `lcd`、`airui`、`tp`、`gpio`、`i2c`、`wlan` 等核心库。真实微信通话还需配套 `tc_iot`；业务登记使用 `http` 和 `json`。`pins`、`pwm` 缺失时部分驱动路径会尝试降级，但仍需验证硬件实际可用。

本目录没有给出底层固件文件或明确的最低固件版本。不能仅因普通 UI 固件能显示页面，就判断其包含腾讯通话和媒体能力。

### 2.2 显示与触摸参数

| 项目 | 配置 |
| --- | --- |
| LCD 驱动 | `hx8282`，`lcd.RGB` |
| LCD 尺寸 | 1024×600，`direction=0` |
| LCD 复位 | GPIO5 |
| LCD 电源使能 | GPIO55，高电平后等待 200 ms |
| 背光使能 | GPIO8 |
| 背光调光 | PWM1，物理 pin14 复用，10 kHz；当前启动占空比参数为 100 |
| AirUI 颜色格式 | 优先显式使用 RGB565 |
| 帧缓冲 | `need_buffer=true`，`lcd.setupBuff(nil, true)` |
| 刷新 | `lcd.autoFlush(false)`，由 AirUI 控制 |
| 触摸驱动 | `gt911`，I2C1 |
| 触摸复位 / 中断 | GPIO28 / GPIO7 |
| 触摸坐标 | 1024×600，单点，`swap_xy=false`、`direction=0` |
| 触摸刷新参数 | `refresh_rate=5` |
| 软件 I2C 回退 | SCL GPIO38、SDA GPIO39、`delay_us=5` |

`pins.setup` 中的 pin 编号与 `gpio` 使用的编号不是同一列含义。下表按配置原值列出，不应把物理 pin7 与 GPIO7 混为一谈：

| `pins.setup` pin | 复用功能 | 配置备注 |
| --- | --- | --- |
| 69 | `I2C1_SDA` | 对应 GPIO39 |
| 7 | `I2C1_SCL` | 对应 GPIO38 |
| 14 | `PWM1` | 背光 |
| 72 | `SPI0_CLK` | 保留的 CH390H 硬件复用 |
| 71 | `SPI0_MOSI` | 同上 |
| 6 | `SPI0_MISO` | 同上 |

存在 SPI / LAN 引脚配置不代表当前网络模块实现了以太网；本工程 `net_mgr.lua` 使用 WLAN。

### 2.3 上电顺序

`hw_config.power_on` 按数组顺序执行：

| 顺序 | GPIO | 电平 | 意义 |
| --- | --- | --- | --- |
| 1 | 27 | 低 | 关闭板载功放，配置按外置 Air1103 音频考虑 |
| 2 | 52 | 低 | RS485_EN |
| 3 | 55 | 高 | LCD_EN，随后等待 200 ms |
| 4 | 53 | 高 | LAN_EN |
| 5 | 34 | 高 | SPI0_CS0 |

上电序列包含 `sys.wait`，所以 `lcd_drv.init()` 必须在任务中调用。GT911 在 LCD 初始化之后启动，避免供电尚未稳定时访问 I2C。

### 2.4 字体与换屏

字体先尝试 `/MiSans_gb2312.ttf`，失败后尝试 `/luadb/MiSans_gb2312.ttf`。默认字号 20、缓存 1024、抗锯齿参数 1；各 UI 控件还会指定自己的字号。

若中文显示方框，先检查字体是否下载、文件名大小写和 `font loaded` 日志。驱动字体加载失败后仍会继续构建页面，页面出现不代表字体加载成功。

换屏可先改 `hw_config.lcd`、`tp` 和上电配置；但首页、顶栏及按钮包含大量 1024×600 的固定坐标，**更换分辨率还需检查并调整 UI 布局**，不能只改 `w/h` 就认为适配完成。

---

## 三、WiFi、时间与界面配置

### 3.1 主用热点和备用热点

主用网络填写在 `hw_config.lua`：

```lua
cfg.wifi = {
    ssid = "YOUR_SSID",
    password = "YOUR_PASSWORD",
}
```

备用热点填写在 `tc_iot_config.lua`：

```lua
wifi_ssid = "YOUR_WIFI_SSID",
wifi_password = "YOUR_WIFI_PASSWORD",
```

主用热点由 `net_mgr` 初始化 WLAN、扫描并连接。通话服务等待 `net.ready` 最多 45 秒；仍未就绪且备用 SSID 非空时，使用备用配置再发起一次连接，继续等待最多 30 秒。备用配置可填同一个已确认可用的热点，也可按现场设置；占位符不会被自动识别为空配置。

### 3.2 扫描和联网判定

1. 等待 UI 就绪，初始化 WLAN 并切到 STATION 模式。
2. 等待约 300 ms，执行开机扫描，最多等 `WLAN_SCAN_DONE` 10 秒。
3. 日志打印前 12 个 AP 及扫描总数，提示目标 SSID 是否可见。
4. 主用 SSID 非空时调用 `wlan.connect(..., 1)`。
5. 每约 5 秒查询 `wlan.ready()`，更新 RSSI、IP 并广播 `NET_STATUS`。
6. 首次联网后尝试 SNTP。长时间未就绪时，按 12 次循环约 60 秒复扫，最多追加 3 次；扫描本身会使实际间隔变长。

`wlan.connect` 返回成功仅表示连接请求发起成功，验收以 `net.ready`、实际 IP 和后续腾讯服务就绪为准。循环主要做状态查询和诊断扫描，不应把它描述成应用层无限主动重连逻辑。

### 3.3 网络日志与信号格

以下断开原因是本项目 `net_mgr.lua` 的解释表：

| 原因码 | 日志说明 | 排查 |
| --- | --- | --- |
| 256 | 信号丢失 | 距离、天线、干扰和热点状态 |
| 257 | 找不到该 SSID | SSID 拼写、2.4 GHz、隐藏热点和距离 |
| 258 | 密码错误 | 核对热点密码 |
| 259 | 主动断开 | 检查是否正在切换或重新连接热点 |
| 260 | DHCP 超时 | 热点 DHCP、地址分配及网络环境 |

| RSSI 条件 | 信号格 |
| --- | --- |
| 大于 -55 dBm | 4 |
| 大于 -67、且不大于 -55 dBm | 3 |
| 大于 -78、且不大于 -67 dBm | 2 |
| 大于 -90、且不大于 -78 dBm | 1 |
| 不大于 -90 dBm 或数值无效 | 0 |

顶栏网络已就绪但暂时没有有效 RSSI 时，显示“已连接”和四格；不能仅用四格判断真实信号强度。

### 3.4 时间显示

`net_mgr` 首次联网会尝试 SNTP。腾讯通话初始化时还会订阅 `NTP_UPDATE`、再次发起校时，等待最多 10 秒，并调用 `tc.set_time(os.time())`。

当前通话服务在等待 NTP 超时后仍继续调用 `set_time`，没有像严格 TLS 启动流程那样立即退出。时间异常时应核对实际校时结果。UI 使用 `os.date("*t")` 显示系统时间，源码未在此处固定 UTC+8；时区以运行环境为准。

### 3.5 通话与界面配置

| 字段 | 默认值 | 实际用途 |
| --- | --- | --- |
| `cfg.call.peer` | `门口机访客` | 当前页面对端显示名称，不是微信 OpenID |
| `cfg.call.ring_ms` | `1200` | 本地模拟外呼延时，真实 SDK 外呼不用此值 |
| `cfg.wechat.enable` | `true` | 启动时是否尝试腾讯通话 |
| `cfg.wechat.auto_answer` | `false` | 来电约 800 ms 后自动调用接听，台架联调可用 |
| `cfg.wechat.video_on_incoming` | `true` | 来电使用视频页；当前依据本地配置，不是解析来电媒体类型 |
| `cfg.wechat.local_demo` | `false` | 后端不可用时，是否允许外呼模拟接通 |
| `cfg.wechat.require_register` | `false` | 外呼登记函数返回失败时是否中止呼叫 |
| `cfg.demo_mode` | `false` | 模拟网络和摄像头显示状态 |
| `cfg.version` | `001.000.000` | 首页显示版本，需与入口 VERSION 同步维护 |

---

## 四、腾讯通话配置与就绪流程

### 4.1 配置表

`tc_iot_config.lua` 需随脚本一起下载。下表只说明当前代码如何使用字段，不代表本目录包含腾讯控制台或小程序创建流程。

| 字段 | 当前代码使用方式 |
| --- | --- |
| `product_id` | `tc.init` 产品参数，必须为非空字符串 |
| `device_name` | `tc.init` 设备名称，必须为非空字符串 |
| `device_secret` | `tc.init` 设备密钥，必须为非空字符串 |
| `region` | 传给 `tc.init`，缺省为 `china` |
| `model_id` | `tc.voip_init` 参数，必须为非空字符串 |
| `wxa_appid` | `tc.voip_init` 小程序 AppID，必须为非空字符串 |
| `voip_type` | 传给 `tc.voip_init`，配置注释约定 0 正式 / 1 开发 / 2 体验，当前为 1 |
| `data_path` | 作为第二个参数传给 `tc.voip_init`；缺省 `/tc_iot/voip`，按配套 SDK 要求填写 |
| `wifi_ssid` / `wifi_password` | 主网络等待超时后的备用热点 |
| `call_status_url` | 用于推导业务后端 `/device-call` 地址，见第七节 |
| `call_status_token` | 业务请求 JSON 的 `deviceToken` |
| `call_open_id` | 指定外呼微信用户；空字符串时取授权列表第一位 |
| `auto_answer` | **当前 call_service 未读取**；实际自动接听改 `hw_config.wechat.auto_answer` |
| `caller_camera` / `callee_camera` | **当前业务代码未读取**；不能仅修改它们就认为媒体能力已改变 |

当前代码只检查五个必需字符串是否为空，不识别 `YOUR PRODUCT_ID` 等占位文本。因此“还没替换占位符”不会立刻按缺配置退出，而可能进入 SDK 初始化失败或等待流程。

### 4.2 固件内置 SDK

服务先查 `_G.tc_iot`，再以动态模块名尝试加载 `tc_iot`。这是固件内置模块，**不要为解决 Luatools 提示而自行创建空的 `tc_iot.lua`**。

真实通话主要依赖下列 SDK 能力：

| 接口 | 用途 |
| --- | --- |
| `set_time` | 更新 SDK 时间 |
| `init`、`online` | 设备接入和在线状态 |
| `voip_init` | 初始化微信通话能力 |
| `voip_get_user_list` | 查询已授权微信用户 |
| `voip_call` | 设备外呼 |
| `voip_join` | 接听、拒接、忙线处理 |
| `voip_hangup` | 挂断 |
| `media_controls` | 麦克风静音、扬声器、摄像头开关 |
| `camera_warmup`、`camera_status` | 可选的摄像头预热和状态查询 |
| `voip_is_busy` | 可选的外呼前忙线检查 |

部分接口通过存在性检查或 `pcall` 包装，但不能据此认定任意不完整 SDK 都能降级运行；应使用与当前业务接口匹配的配套固件。

### 4.3 初始化阶段

```text
UI 建好
  → 等待 200 ms
  → 检查 wechat.enable
  → 查找内置 tc_iot
  → 读取 tc_iot_config，检查五个必需字符串
  → CAM_OWNER=tc，先让本地探测任务让出摄像头
  → 等主 WiFi 最多 45 秒
  → 必要时备用热点连接，再等最多 30 秒
  → SNTP 等待最多 10 秒，设置 SDK 时间
  → tc.init：最多 6 次尝试，失败间隔 5 秒
  → 等待 tc.online() 为真
  → tc.voip_init：最多 6 次尝试，失败间隔 5 秒
  → backend=tc、ready=true，发布 CALL_SERVICE_READY("tc")
  → 按能力预热摄像头，每秒查询 SDK 摄像头状态
```

**等待 `tc.online()` 的循环当前没有超时。** 所以不能把“主网络 45 秒 + 备用 30 秒”当成整个服务的最大启动耗时。若一直未就绪，应判断卡在网络、设备在线还是 VoIP 初始化阶段。

后端初始化失败时，摄像头所有权交还本地探测，并发布 `CALL_SERVICE_READY("local")`。该事件表示使用本地后端路径，不自动开启模拟通话；是否允许外呼演示还由 `wechat.local_demo` 决定。当前 `start()` 失败退出后没有应用层定时重新初始化机制。

### 4.4 授权用户选择

外呼前调用 `tc.voip_get_user_list(0, 10)`，只在这次返回的用户数组内选择：

- `call_open_id` 非空：必须精确匹配数组中的 ID，否则返回 `no_user`。
- `call_open_id` 为空：取第一个非空字符串用户；多用户时日志提醒建议指定用户。
- 列表为空或查询异常：提示“没有已授权的微信用户”。

填入 OpenID 不会自动创建授权关系，也不会分页查找第一批列表之外的用户。先在配套小程序 / 服务流程完成设备用户授权，再进行外呼。

---

## 五、Luatools 烧录与启动验收

### 5.1 下载前准备

1. 选用匹配 Air8101B、RGB 屏与腾讯通话接口的底层固件。
2. 按硬件核对 LCD、触摸、上电顺序和音频配套。
3. 替换主用 / 备用热点占位符。
4. 填写真实腾讯设备与小程序参数，确认授权用户。
5. 配置业务登记地址及 token，或按第七节明确选择跳过登记的联调路径。
6. 真实联调保持 `demo_mode=false`、`wechat.local_demo=false`。

### 5.2 添加脚本和资源

| 内容 | 要求 |
| --- | --- |
| `app/main.lua` | 必须包含，按入口名称 `main.lua` 加载 |
| `config/` 下两份 Lua | 硬件和云配置都需要 |
| `drivers/`、`network/`、`call/`、`ui/` 下全部 Lua | 不能只添加入口和配置 |
| `MiSans_gb2312.ttf` | 下载到脚本区可使用的 `/luadb/MiSans_gb2312.ttf` |
| 系统库与依赖 | 核对 `sys` 全局及固件内置核心能力，标准脚本依赖由工具收集 |
| `tc_iot` | 从配套固件提供，不添加伪造 Lua 替代模块 |
| `README.md` | 阅读文件，取消勾选，不烧录 |

确保打包后的文件名与 `require` 名一致。若使用字节码，需在目标固件上验证加载；电脑端文件存在不代表进入了下载列表。

### 5.3 开机日志检查

| 阶段 | 关键词 | 验收 |
| --- | --- | --- |
| 入口 | `SmartDoor`、`001.000.000` | 确认为当前脚本 |
| 字体 | `font loaded` | 根路径或 `/luadb` 路径加载成功 |
| 显示 | `screen 1024 600`、`backlight on` | 尺寸、颜色和背光正常 |
| 触摸 | `touch ready (I2C1)`、`touch bound gt911` | 或软件 I2C 回退成功 |
| UI | `ui ready` | 首页出现，控件无明显错位 |
| 网络 | 扫描 AP、`connecting`、`wifi connected` | 进一步确认获得 IP |
| 摄像头归属 | `camera owner -> tc` 或 `self` | 与后端路径一致 |
| 腾讯服务 | `腾讯微信通话已就绪` | 后端已完成初始化 |
| 通话管理 | `微信通话后端已就绪` | 顶栏由未就绪变为空闲 |

主页底部“系统就绪”和“门禁已布防”是固定文字，不能用于证明腾讯服务、门锁或摄像头已工作。以对应动态状态和日志为准。

---

## 六、屏幕页面与通话操作

### 6.1 页面说明

| 页面 | 内容 | 操作 |
| --- | --- | --- |
| 顶部状态栏 | WLAN RSSI / 信号格、系统时间、USB CAM、微信通道状态 | 始终显示 |
| 首页 | 设备状态卡、固定设备编号 `DOOR-8101-01`、显示版本、两张通话卡片 | 点击语音或视频发起外呼 |
| 语音呼叫页 | 对端名、正在呼叫 / 连接 / 通话状态、计时 | 通话中静音、免提、挂断 |
| 视频呼叫页 | 远端画面占位、本地预览占位、状态、计时 | 通话中静音、摄像头、挂断 |
| 来电状态 | 对应语音或视频页面的来电按钮组 | 接听或拒接 |
| 提示浮层 | 未就绪、无授权用户、登记失败等 | 显示约 2.5 秒 |

媒体开关只在 `talking` 状态接受切换；摄像头开关还要求当前模式为 `video`。橙色表示对应状态已启用，静音按钮橙色表示“静音开启”。

### 6.2 设备主动呼叫微信

1. 确认网络真实在线，微信状态为“空闲”，日志有腾讯服务就绪。
2. 确认小程序版本与配置一致，用户已授权设备。
3. 首页点击“语音通话”或“视频通话”。
4. 页面进入 `dialing`，任务检查忙线并选择授权用户。
5. 生成业务呼叫 ID，向后端登记 `RINGING`；按登记策略决定继续或中止。
6. 设置初始媒体开关，再调用 SDK 外呼。
7. 微信侧接听后，收到匹配的 `TC_IOT_TALKING`，页面进入“通话中”并开始计时。
8. 分别在设备和微信端结束通话，验证两端都退出、下一通能正常建立。

SDK 外呼成功返回后，若 60 秒内页面仍处于同一通 `dialing`，自动挂断并提示“对方无应答”。SDK 返回 0 只表示此次调用成功，实际接通仍依赖后续事件。

### 6.3 微信呼叫设备

1. 从已授权的配套小程序发起设备呼叫。
2. 设备接收 `TC_IOT_INCOMING`，显示来电页。
3. 默认 `video_on_incoming=true`，因此使用视频页面；页面选择不等于已检测到真实视频媒体。
4. 点击“接听”，页面进入 `connecting`，调用 `tc.voip_join(room_id, 0)`。
5. 收到匹配的 talking 事件后开始计时。
6. 点击“拒接”时回主页并调用 `voip_join(room_id, 11)`。

开启 `hw_config.wechat.auto_answer` 后，来电约 800 ms 后自动尝试接听。当前 `tc_iot_config.auto_answer` 不控制此行为。

**当前代码限制：** 接听调用失败时，`call_mgr.answer()` 会走约 800 ms 的本地模拟接通，即使 `wechat.local_demo=false` 也未在此分支拦截。因此接听失败后页面开始计时不能证明真实接通，必须同时核对 SDK 返回值、talking 事件及双方音视频。

### 6.4 挂断、拒接与忙线

| 操作 / 事件 | 当前行为 |
| --- | --- |
| 点击挂断 / 取消外呼 | 先重置页面回首页，再在任务中调用 SDK 挂断 |
| 来电响铃时点击挂断 | 按拒接处理 |
| 普通来电到达但页面非 idle | 拒接新来电并提示正在通话 |
| `TC_IOT_INCOMING_BUSY` | 服务层调用 `voip_join(id, 9)` |
| 对端挂断 / 取消 / 失败 | 匹配当前 ID 时重置页面；失败时可提示数值错误码 |
| 媒体错误 | 转换为结束事件，当前页面收尾 |

页面已回主页不代表 SDK 资源一定已经完全释放。接着发起新呼叫时，服务层如提供 `voip_is_busy` 会做检查；连续拨号应作为独立验收项。

### 6.5 音视频控制

`call_service.set_media` 向 SDK 传递布尔参数 `muted`、`speaker`、`camera`，避免 Lua 的数值 0 被作为真值处理。

| 控件 | 作用 | 注意 |
| --- | --- | --- |
| 静音 | 切换 `muted` | 验收对端是否实际听不到设备麦克风 |
| 免提 | 切换 `speaker` | 语音页提供；需配套硬件与 SDK 支持 |
| 摄像头 | 切换 `camera` | 仅视频模式提供 |

UI 先修改按钮状态再调用 SDK，失败时当前代码没有回滚按钮。因此按钮颜色变化不证明硬件控制成功。真实外呼前 `call_service.dial` 会把 camera 参数设为是否视频；UI 的初始 `cam_on` 在语音模式也为 true，后续控制仍按当前状态传递，需结合实际 SDK 验证。

---

## 七、业务后端外呼登记接口

### 7.1 URL 推导规则

配置项名为 `call_status_url`，但当前函数通过它推导实际请求地址。例如：

```lua
call_status_url = "https://example.com/api/twecall/device-status",
call_status_token = "YOUR_DEVICE_TOKEN",
call_open_id = "",
```

代码要求非空 URL **以 `/device-status` 结尾**，去掉该后缀后追加 `/device-call`，实际请求：

```text
POST https://example.com/api/twecall/device-call
Content-Type: application/json
```

`example.com` 仅演示地址结构，不是本工程提供的服务。调用者应替换为自己的配套后端。

### 7.2 请求内容

外呼前登记示例，字段值为示意：

```json
{
  "deviceToken": "YOUR_DEVICE_TOKEN",
  "callId": "dev-<timestamp>-<ticks>",
  "openId": "AUTHORIZED_USER_OPENID",
  "roomType": "video",
  "state": "RINGING"
}
```

| 字段 | 来源 |
| --- | --- |
| `deviceToken` | `tc_iot_config.call_status_token`，放在 JSON 中，不是额外 Authorization 头 |
| `callId` | `dev-时间戳-ticks余数`，业务登记 ID |
| `openId` | 从授权用户列表选中的目标 |
| `roomType` | `voice` 或 `video` |
| `state` | 登记时 `RINGING`，本地挂断上报时 `ENDED` |

HTTP 请求超时参数为 3000 ms。函数只以 HTTP 状态码 200～299 判断成功，不解析响应正文的业务成功标记。

### 7.3 登记失败策略

| 条件 | 当前行为 |
| --- | --- |
| URL 缺失或空字符串 | 登记函数直接返回成功，跳过登记 |
| URL 非空但后缀错误 | 返回失败，打印后缀要求 |
| 固件缺 `http` 或 `json` | 打印警告，函数返回成功并跳过登记 |
| HTTP 异常 / 非 2xx | 返回失败 |
| 失败且 `require_register=false` | 警告后继续 SDK 呼叫，小程序业务提示可能缺失 |
| 失败且 `require_register=true` | 取消本次外呼，显示登记失败 |

**严格模式的边界：** 当前 `require_register=true` 只处理登记函数明确返回失败的情况，不会阻止“URL 为空”或“缺 http/json”这两种跳过路径。因此部署时还需核对 URL、token 和固件库，不能只打开开关就认为后端登记必定发生。

### 7.4 呼叫 ID 与结束上报

界面呼叫 ID 为 `ui-时间戳-ticks余数`，业务登记 ID 为 `dev-时间戳-ticks余数`，二者不同。SDK 外呼同时接收业务 ID 和界面 ID，通话管理器会按事件 ID 匹配当前呼叫；联调时应保留两个 ID 及事件参数。

`call_service.hangup()` 会向同一个 `/device-call` 地址发送 `state="ENDED"`。当前远端结束事件在 `call_mgr` 中主要重置页面，并不在该分支直接调用 `call_service.hangup()`；也未看到登记失败或 SDK 外呼失败后的完整服务端状态补偿流程。**不能把本文接口理解为所有结束路径都会可靠上报 ENDED。** 需要与配套后端共同验证取消、拒接、超时和远端挂断后的状态清理。

---

## 八、状态机、消息与接口参考

### 8.1 业务状态

| 状态 | 含义 | 典型进入条件 |
| --- | --- | --- |
| `idle` | 页面无活动呼叫 | 初始、挂断、结束或失败重置 |
| `dialing` | 设备正在外呼 | 点击首页通话卡片 |
| `ringing` | 设备收到来电等待处理 | incoming 事件 |
| `connecting` | 已请求接听，等待后续 | 点击接听 |
| `talking` | 通话页面计时 | talking 事件或本地模拟分支 |

```text
外呼：idle → dialing → talking → idle
来电：idle → ringing → connecting → talking → idle
拒接：idle → ringing → idle
失败：dialing / connecting / talking → idle（具体以当前分支为准）
```

`wx_call` 的通道状态是另一组值：`offline/idle/connecting/ringing/talking`。当后端未就绪时业务状态仍可为 `idle`，顶栏显示“未就绪”；不要混淆这两组状态。

### 8.2 SDK 事件映射

| SDK 消息 | 服务事件 / 动作 |
| --- | --- |
| `TC_IOT_INCOMING` | `CALL_SERVICE_EVENT("incoming", id)` |
| `TC_IOT_INCOMING_BUSY` | `voip_join(id, 9)` |
| `TC_IOT_TALKING` | `CALL_SERVICE_EVENT("talking", id)` |
| `TC_IOT_CALL_ENDED` | ended，原因 `remote` |
| `TC_IOT_CANCELLED` | ended，原因 `cancelled` |
| `TC_IOT_CALL_FAILED` | failed，携带错误码 |
| `TC_IOT_MEDIA_ERROR` | ended，原因 `media_error` |

### 8.3 应用内部消息

| 消息 | 参数 | 用途 |
| --- | --- | --- |
| `UI_READY` | 无 | 允许网络 / 摄像头任务继续 |
| `NET_STATUS` | `{ready, rssi, ip, ssid}` | 首页及顶栏刷新 |
| `CAM_OWNER` | `tc` / `self` | 摄像头控制权分配 |
| `USB_CAM` | 状态字符串 | 显示摄像头状态 |
| `CALL_SERVICE_READY` | `tc` / `local` | 后端初始化结果 |
| `CALL_SERVICE_EVENT` | `evt, id, code` | 后端到业务状态机 |
| `CALL_STATE` | `state, mode, peer` | 页面切换和通话文字 |
| `CALL_TICK` | 秒数 | 通话计时 |
| `CALL_MEDIA` | `muted, speaker, camera` | 更新媒体按钮 |
| `WX_CALL_STATE` | `state, peer` | 微信状态显示 |
| `UI_TOAST` | 文本 | 约 2.5 秒提示 |

### 8.4 业务层接口

| 接口 | 说明 |
| --- | --- |
| `call_mgr.dial("voice" / "video")` | 发起外呼；已有呼叫时拒绝 |
| `call_mgr.answer()` | 仅 ringing 状态处理 |
| `call_mgr.reject()` | 拒接来电 |
| `call_mgr.hangup()` | 挂断或取消；ringing 时转拒接 |
| `call_mgr.toggle_mute()` | talking 时切换静音 |
| `call_mgr.toggle_speaker()` | talking 时切换扬声器状态 |
| `call_mgr.toggle_camera()` | talking 且 video 时切换摄像头 |
| `call_mgr.snapshot()` | 返回 state、mode、peer、seconds、muted、speaker、camera |
| `call_service.is_ready()` | 仅腾讯后端 ready 时为真 |
| `wx_call.get()` / `wx_call.set()` | 获取 / 更新显示通道状态，不直接建立通话 |

这些是 Lua 内部接口，不是当前设备提供的 HTTP 或串口命令。修改 `wx_call.set("talking")` 只会影响状态显示，不能用它建立真实通话。

---

## 九、USB 摄像头与视频显示

### 9.1 本地探测参数

| 字段 | 默认值 | 作用 |
| --- | --- | --- |
| `cfg.camera.enable` | `true` | 本地探测是否启用 |
| `usb_port` | `1` | 本地 `camera.init` 参数 |
| `sensor_width` / `sensor_height` | `640` / `480` | 本地探测初始化尺寸，不代表云端实际视频协商结果 |
| `probe_interval` | `30000` ms | 本地探测循环间隔 |

本地模式调用 `camera.init` 后，仅把返回 0 或 1 认作合法 UVC ID，避免将错误码误判为设备 ID。成功后立即 `camera.stop(id)`，只做检测，不保持采集。

本地探测成功后，当前循环仅继续报告 online，未执行真正的设备在位查询。因此不能承诺该路径能可靠检测摄像头热拔出。

### 9.2 所有权切换

摄像头任务等待 UI 后延迟 300 ms，再最多等待 10 秒确定所有权。

- `self`：由 `usb_cam` 探测。
- `tc`：停止自行 `camera.init` 探测，由腾讯通话 SDK 接管。
- 腾讯初始化失败：服务发布 `CAM_OWNER="self"` 交还探测。
- 腾讯就绪：若存在预热接口则调用；随后每秒查询 `tc.camera_status()` 并发布 UI 状态。

`cfg.camera.enable` 只在本地探测函数中检查，当前腾讯路径没有使用它来禁止 SDK 摄像头预热。需要控制真实通话摄像头时应核对 SDK 和媒体控制流程，而不是只关闭本地探测开关。

### 9.3 SDK 状态映射

| SDK camera_status | UI 状态 | 显示 |
| --- | --- | --- |
| `ready` | `online` | 在线 |
| `warming` | `warming` | 预热中 |
| `off` / `failed` / `stalled` | `offline` | 未连接 |
| `unavailable` | `unsupported` | 不支持 |
| 其他值 | `offline` | 未连接 |

### 9.4 视频页的实际能力边界

`ui_call.lua` 创建了黑色远端区域、“等待视频画面…”文字和本地预览占位框，但没有将摄像头或 SDK 视频帧绑定到这些控件。摄像头按钮目前修改媒体开关和提示文字。

因此应分开验收：

1. SDK 是否收到摄像头并可用。
2. 微信侧是否实际收到设备视频。
3. 设备是否支持下行视频解码与显示。
4. 本工程页面是否接入显示输出。

前两项成功不能证明后两项已实现；显示“本地预览”文字也不代表已有实时预览。

---

## 十、本地演示模式

### 10.1 三个开关的区别

| 开关 | 作用 | 不会自动完成的事情 |
| --- | --- | --- |
| `demo_mode=true` | 模拟网络 ready、IP、RSSI 和摄像头在线 | 不建立真实 WiFi，不完成腾讯登录 |
| `wechat.local_demo=true` | 后端返回 local 时允许外呼延迟模拟接通 | 不拨微信、不传真实音视频 |
| `wechat.enable=false` | 不尝试初始化腾讯 SDK | 不自动打开以上两个演示开关 |

仅做无云界面演示时，可以在 `hw_config.lua` 配置：

```lua
cfg.demo_mode = true
cfg.wechat.enable = false
cfg.wechat.local_demo = true
```

此时仍需要真实可用的 LCD、AirUI、字体和触摸；不是电脑端模拟器模式。

### 10.2 模拟显示与测试边界

- 网络任务每 5 秒发布模拟数据：IP 为 `192.168.1.86`、SSID 为 `SmartDoor-2.4G`，RSSI 在预设序列中变化。
- 摄像头显示模拟在线，不代表存在 UVC 设备。
- 外呼延时默认 1200 ms 后进入 talking 并计时，不需要微信接听。
- 回到主页时，后端仍为 local，微信通道会回到“未就绪”。

真实测试恢复 `demo_mode=false` 和 `wechat.local_demo=false`，启用并配置腾讯服务。不要将模拟 `net.ready=true` 与真实腾讯初始化混用后，再用页面“在线”判断网络正常。

---

## 十一、超时参数与故障排查

### 11.1 时间参数

| 场景 | 当前值 |
| --- | --- |
| 主初始化任务延时 | 50 ms |
| LCD_EN 稳定等待 | 200 ms |
| UI 后通话服务启动延时 | 200 ms |
| 网络 / 摄像头等待 UI | 最多 8 秒 |
| 开机扫描等待 | 最多 10 秒 |
| 网络状态刷新 | 约 5 秒 |
| 失败诊断复扫 | 约 60 秒间隔，最多追加 3 次 |
| 通话服务等待主网络 | 最多 45 秒 |
| 备用热点等待 | 最多 30 秒 |
| 通话初始化等待 NTP | 最多 10 秒，超时仍继续 |
| `tc.init` / `tc.voip_init` | 各最多 6 次尝试，失败间隔 5 秒 |
| `tc.online()` 等待 | 当前无超时 |
| 外呼 HTTP 登记 | timeout 3000 ms |
| SDK 外呼成功后的无应答等待 | 60 秒 |
| 自动接听延时 | 800 ms |
| 接听失败后的模拟接通延时 | 800 ms |
| 模拟外呼接通 | 默认 1200 ms |
| SDK 摄像头状态查询 | 1 秒 |
| 本地摄像头探测循环 | 默认 30 秒 |
| 提示浮层 | 2.5 秒 |

### 11.2 常见现象

| 现象 | 首先检查 | 后续处理 |
| --- | --- | --- |
| 入口未执行 | 是否下载 `app/main.lua`，打包名称是否正确 | 核对项目名和版本日志 |
| `sys` 为 nil | 当前入口依赖全局 sys | 核对固件 / 启动系统库初始化 |
| 黑屏 | 电源、GPIO55、GPIO8、PWM、LCD 驱动 | 查 `lcd.init fail`、`airui.init fail` |
| 花屏 / 撕裂 | 分辨率、RGB565、帧缓冲、内存 | 查帧缓冲分配失败日志 |
| 中文方框 | 字体文件及加载路径 | 确认 `font loaded`，检查 `/luadb/MiSans_gb2312.ttf` |
| 有画面无触摸 | I2C 复用、供电等待、GPIO28 / GPIO7 | 看硬件 I2C 与软件 I2C 回退日志；可开 `cfg.tp.debug` |
| 触摸坐标偏移 | direction、swap_xy、实际屏幕尺寸 | 结合 touch 日志核对四角及按钮位置 |
| WiFi 连不上 | 2.4 GHz、SSID、密码、扫描结果 | 按 256～260 原因码分层排查 |
| WiFi 显示在线却无法通话 | 是否误开 demo_mode，是否真实获得 IP | 再查腾讯初始化与授权 |
| 微信一直未就绪 | SDK 是否存在、五个必需字段是否仍为占位符 | 分辨卡在网络、tc.init、online 还是 voip_init |
| UI 正常但无 SDK | 普通显示固件可能不包含 tc_iot | 换配套固件，不伪造 Lua SDK 文件 |
| 没有已授权用户 | 小程序授权关系、call_open_id | 仅在返回的前 10 位用户内匹配 |
| 呼叫登记失败 | URL 是否以 `/device-status` 结尾、token、HTTP 返回码 | 查后端真实 `/device-call` 请求 |
| 设备显示呼叫中但小程序无提示 | 登记是否成功，是否放行失败路径 | SDK 呼叫与业务弹窗分别验证 |
| 对方无应答 | SDK 成功返回后仍未收到匹配 talking | 检查小程序版本、授权、对端和事件 ID |
| 接听失败却显示通话中 | 当前存在模拟接通回退 | 以 SDK 日志和真实音视频为准 |
| 摄像头状态始终在线 | self 模式成功后未真实检测拔出，或开了 demo_mode | 按当前所有权检查 SDK 状态或冷启动探测 |
| 视频页没有画面 | 当前 UI 未绑定视频输出 | 分开核对 SDK 上行和页面渲染实现 |
| 按钮变色但媒体未变 | UI 先更新，SDK 失败无回滚 | 检查 media_controls 返回及实际声音 / 画面 |
| 远端挂断后后端仍显示响铃 | ENDED 并非所有结束分支都会发送 | 检查业务后端状态清理和事件流程 |
| 第一次失败后不再初始化 | start 失败退出后没有自动重新初始化任务 | 修正配置后重启再验收 |
| 更换分辨率后界面错位 | 页面有固定坐标 | 同步调整首页、顶栏与通话布局 |

### 11.3 建议保留的日志

记录固件版本、`SmartDoor` 版本、硬件型号、两种演示开关状态、从上电到故障的完整日志、当前摄像头所有权、授权用户查询结果、外呼登记 HTTP 状态码、UI 呼叫 ID / 业务呼叫 ID，以及 SDK 回调事件与错误码。

不要只以“界面开始计时”“系统就绪”或“摄像头在线”作为问题结论，这些显示可能来自静态文字、演示数据或回退分支。

---

## 十二、真机验收与当前限制

### 12.1 验收清单

以下是建议执行的测试，不代表本次文档生成已完成这些硬件测试。

| 编号 | 操作 | 验收点 |
| --- | --- | --- |
| T01 | 冷启动 | 项目版本正确，LCD、字体、触摸初始化正常 |
| T02 | 首页四角及按钮点击 | 触摸坐标一致，无明显布局溢出 |
| T03 | 正确 / 错误 WiFi 配置 | 真实 IP 与状态正确，失败原因可定位 |
| T04 | 主热点不可用、备用可用 | 备用路径能联网，后端继续初始化 |
| T05 | 关闭演示开关启动 SDK | 有“腾讯微信通话已就绪”，不是模拟 ready |
| T06 | 无授权用户 / 指定未授权 OpenID | 外呼被拒绝并提示，不虚假接通 |
| T07 | 设备语音外呼 | 后端登记、微信来电、接听、双向语音正常 |
| T08 | 设备视频外呼 | 微信侧实际收到摄像头视频；页面占位限制另行记录 |
| T09 | 微信呼入，手动接听 / 拒接 | SDK 返回、事件和页面一致 |
| T10 | 自动接听 | 按实际 `hw_config.wechat.auto_answer` 生效 |
| T11 | 静音 / 免提 / 摄像头切换 | SDK 返回及实际媒体效果与按钮一致 |
| T12 | 外呼无应答 | 60 秒分支取消并提示，后端状态能收尾 |
| T13 | 本地挂断、远端挂断、取消、忙线 | 两端状态和业务服务端最终一致 |
| T14 | 连续呼叫与快速取消 | 不串用旧 ID，不遗留忙线或错误计时 |
| T15 | 摄像头拔插 / 不接摄像头 | 分别记录 self / tc 路径表现，不只看静态在线 |
| T16 | 登记后端失败、严格 / 非严格模式 | 与第七节实际分支一致 |
| T17 | 本地演示后恢复真实配置 | 演示开关已关闭，网络和通话结果可真实验证 |

### 12.2 已知实现边界

- 视频页目前没有实时视频绑定；本目录未提供小程序和业务后端。
- 首页“已布防”、设备编号是固定文案，没有门锁 / 门磁业务实现。
- 入站模式由 `video_on_incoming` 指定，未按 SDK 来电媒体类型自动选择页面。
- 配置中的 `tc_iot_config.auto_answer/caller_camera/callee_camera` 当前未使用。
- `tc.online()` 等待没有超时，初始化失败后没有自动重建任务。
- 接听失败会进入本地模拟接通分支，需重点区分真实 talking 事件。
- SDK 媒体控制失败没有回滚 UI 状态。
- 本地摄像头在线后没有真正的热拔出检测。
- 外呼登记与结束通知不构成覆盖所有异常路径的可靠状态同步。
- 当前没有网页配置、HTTP 服务端、FOTA 应用流程或通用串口产测命令。

这些说明依据当前 Lua 代码整理，用于确定联调边界，不代表已修复上述行为。

---

## 十三、维护说明

更改硬件优先检查 `hw_config.lua`，更改腾讯设备和业务服务参数检查 `tc_iot_config.lua`。真实生效字段以业务代码读取为准，不能只根据配置注释判断。

发布版本时同步维护 `app/main.lua` 的 `VERSION` 与 `hw_config.version`，两者当前均为 `001.000.000`。各模块头部 `@version` 是模块自身版本，不替代工程版本。

新增真实视频显示、后端重试或通话恢复逻辑后，应同步更新第六至十二节的行为和验收项。本文不包含实际设备凭据，配置示例均使用占位符。
