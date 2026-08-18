> 作者：蒋骞

<font color="red"><b>声明：
本介绍为技术支持页面，禁止用于非法用途，请遵守国家法律法规要求。</b></font>
## 一、场景说明

本项目使用 **Air8101B 核心板 + AirAUDIO_1000 音频扩展板**，演示 Air8101B 分别在 **WiFi 单网卡、以太网单网卡、外挂 Air780EPM 的 4G 单网卡和多网融合**状态下注册 SIP 账号。注册完成后，使用 MicroSIP、Linphone 等 SIP 客户端拨打模块的 SIP 账号，模块等待 5 秒后自动接听，随后通过扩展板上的麦克风和喇叭进行双向通话。

开始测试前，请先完成下面两件事。

### 1.1 修改测试参数

| 参数 | 修改位置 | 说明 |
| --- | --- | --- |
| 测试网卡场景 | `netdrv_device.lua` | 四个 `netdrv_*` 模块只能按场景启用一个 |
| WiFi 名称和密码 | `netdrv/netdrv_wifi.lua` 中的 `ssid`、`password` | Air8101B 仅连接 2.4 GHz WiFi，不能连接 5 GHz WiFi |
| 以太网参数 | `netdrv/netdrv_eth_spi.lua` | Air8101B + AirETH_1000 使用 `ETHUSER1`、GPIO13、SPI0、GPIO15 和 GPIO8 |
| 外挂 4G 参数 | `netdrv/netdrv_4g.lua` | Air8101B 侧应启用 AirLink 4G 虚拟网卡；Air780EPM 端还需单独烧录桥接程序 |
| 多网优先级 | `netdrv/netdrv_multiple.lua` | 按数组顺序配置以太网、WiFi、AirLink 4G 的优先级 |
| SIP 服务器和模块账号 | `sip_app/sip_app_main.lua` 中的 `SIP_CONFIG` | 修改服务器地址、端口、域名、用户名、密码和传输方式 |
| 自动接听配置 | `sip_app/sip_app_main.lua` 中的 `auto_answer`、`delay_auto_answer` | 本例为自动接听，默认等待 5 秒 |
| 主动呼出号码（可选） | `sip_app/sip_app_key.lua` 中 `SIP_APP_MAIN_DIAL_REQ` 的最后一个参数 | 仅在使用按键主动呼出时需要修改 |
| 麦克风增益和喇叭音量 | `audio_drv.lua` 中的 `MIC_ADC_DIG_GAIN`、`MIC_ADC_ANA_GAIN`、`DAC_PLAY_VOL` | 根据现场音量、失真和底噪情况微调 |

SIP 客户端必须配置为同一台 SIP 服务器上的**另一个账号**，不能与模块使用相同账号。

### 1.2 连接核心板与音频扩展板

断电后连接硬件。Air8101B 核心板与 AirAUDIO_1000 音频扩展板应按板上丝印同名信号连接，并确保方向正确：

| Air8101B 核心板信号 | AirAUDIO_1000 音频扩展板 |
| --- | --- |
| MIC+ | MIC1+ |
| MIC- | MIC1- |
| SPK+ | SPK+ |
| SPK- | SPK- |
| GPIO13 | PA_EN |
| 电源 | VCC |
| GND | GND |

按照上表飞线连接。将 AirAUDIO_1000 上的 **PA 开关拨到 OFF**，由脚本控制 PA，可减小开关机爆音。喇叭接扩展板的扬声器接口，麦克风使用扩展板板载麦克风或其麦克风接口。

 **硬件连接图片**
![](https://docs.openluat.com/air8101/luatos/app/multimedia/sip/images/Air8101B+AirAUDIO_1000_1.jpg)

### 1.3 连接以太网扩展板

以太网场景还需要一块 AirETH_1000 扩展板和一根网线。断电后按配套排针方向将 Air8101B 核心板与 AirETH_1000 对插，核对 VCC、GND 和 1 脚方向，不要错位或反插；将网线连接到 AirETH_1000 的 RJ45 接口和路由器 LAN 口。

本项目使用的 Air8101B 侧参数应为：

| Air8101B 核心板信号 | AirETH_1000 扩展板 |
| --- | --- |
| 59/3V3 | 3.3V |
| GND | GND |
| 28/DCLK | SCK |
| 54/DISP | CSS |
| 55/HSYN | SDO |
| 57/DE | SDI |
| 14/GPIO8 | INT |


详细接线和实物图参考：[Air8101 + AirETH_1000 使用说明](https://docs.openluat.com/air8101/luatos/app/accessory/AirETH_1000/1/)。

> **以太网硬件连接图片**
![](https://docs.openluat.com/air8101/luatos/app/multimedia/sip/images/AirETH_1000_SPI1+Air8101B+AirAUDIO_1000.jpg)

### 1.4 连接 Air780EPM 作为 4G 网卡

4G 场景由 Air8101B 通过 **AirLink** 外挂 Air780EPM 实现，Air8101B 自身没有原生 `socket.LWIP_GP` 蜂窝网卡。需要准备：

1. Air780EPM V1.2 开发板、SIM 卡和 4G 天线；
2. Air8101B 与 Air780EPM 的 SPI0 AirLink 连线；
3. 分别给 Air8101B 和 Air780EPM 烧录匹配的固件及脚本；
4. Air780EPM 端创建桥接网卡、启用 4G NAPT 和 DNS 代理；
5. Air8101B 端通过 `airlink_4G` 使用 4G 虚拟网卡。

Air780EPM 端至少需要完成 `airlink.init()`、`netdrv.setup(socket.LWIP_GP_GW, netdrv.WHALE)`、`airlink.start(airlink.MODE_SPI_SLAVE)`、`netdrv.napt(socket.LWIP_GP)` 和 DNS 代理配置。具体接线、两端代码及烧录步骤参考：[Air8101 外挂 Air780EPM 使用 4G 上网](https://docs.openluat.com/air8101/luatos/app/network_routing/4G/)。

断电后连接硬件。Air8101B 核心板与 Air780EPM开发板应按板上丝印同名信号连接，并确保方向正确：

| 功能 | Air8101B 核心板信号 | Air780EPM开发板 |
| --- | --- | --- |
| GND | GND | GND |
| SPI_CLK | 28/DCLK | SPI0_CLK/GPIO11 |
| SPI_CS | 54/DISP | SPI_CS/GPIO8 |
| SPI_MOSI | 57/DE | SPI_MOSI/GPIO9 |
| SPI_MISO | 55/HSYN | SPI_MISO/GPIO10 |
| RDY | 43/R2 | GPIO22/WAKEUP5 |
| IRQ | 75/GPIO28 | GPIO1 |

> **外挂 4G 硬件连接图片**
![](https://docs.openluat.com/air8101/luatos/app/multimedia/sip/images/Air780EPM+Air8101B+AirAUDIO_1000.jpg)

> **注意**
>
> 当前 `netdrv_eth_spi.lua`、`netdrv_4g.lua` 和 `netdrv_multiple.lua` 中仍有从 Air8000 场景沿用的参数。测试 Air8101B 前，必须按照本节和官方参考资料改为 Air8101B 的 `ETHUSER1` 及 `airlink_4G` 配置。

## 二、项目结构
- Air780EPM
  - 固件：LuatOS-SoC_V2046_Air780EPM_8.soc 可在luatools中下载添加
  - 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8101/demo/airlink/Air8101_master_Air780EPM_slave/Air780EPM_slave)
- Air8101
  - 固件：[LuatOS-SoC_V2019_Air8101_106_20260729_1414.soc](https://docs.openluat.com/firmware/LuatOS-SoC_V2019_Air8101_106_20260729_1414.soc)
  - 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8101/demo/sip)
```text
8101/demo/sip/
├── main.lua                    # 项目入口，加载网络、SIP、按键和 TTS 模块
├── netdrv_device.lua           # 选择网卡；当前启用 WiFi STA 单网卡
├── netdrv/
│   ├── netdrv_wifi.lua         # WiFi STA 单网卡
│   ├── netdrv_eth_spi.lua      # AirETH_1000 以太网单网卡
│   ├── netdrv_4g.lua           # AirLink 外挂 Air780EPM 的 4G 单网卡
│   └── netdrv_multiple.lua     # WiFi、以太网和外挂 4G 多网融合
├── sip_app/
│   ├── sip_app_main.lua        # SIP 参数、注册、状态机及通话控制
│   └── sip_app_key.lua         # 按键呼出、接听和挂断逻辑
├── audio_drv.lua               # Air8101B 内置音频、麦克风增益及 PA 控制
└── tts_speaker.lua             # 状态语音播报
```

在 `netdrv_device.lua` 中按测试场景仅启用一个模块：

```lua
-- 场景一：WiFi 单网卡
require "netdrv_wifi"

-- 场景二：AirETH_1000 以太网单网卡
-- require "netdrv_eth_spi"

-- 场景三：外挂 Air780EPM 的 4G 单网卡
-- require "netdrv_4g"

-- 场景四：WiFi + 以太网 + 外挂 4G 多网融合
-- require "netdrv_multiple"
```

不要同时取消多个 `require` 的注释。当前默认启用 WiFi 单网卡。

## 三、准备环境

### 3.1 硬件

1. Air8101B 核心板一块；
2. AirAUDIO_1000 音频扩展板一块；
3. 喇叭一个；
4. 2.4 GHz WiFi 路由器或热点；
5. TYPE-C USB 数据线一根；
6. 安装了 SIP 客户端的电脑或手机。

根据测试场景增加以下硬件：

- 以太网单网卡：AirETH_1000 扩展板、网线及可联网路由器；
- 4G 单网卡：Air780EPM V1.2 开发板、可用 SIM 卡、4G 天线及两板连接线；
- 多网融合：同时准备 2.4 GHz WiFi、AirETH_1000 和 Air780EPM。

核心板通过 TYPE-C USB 接口供电和下载：数据线一端连接核心板 TYPE-C 接口，另一端连接电脑 USB 接口。

### 3.2 软件

1. [Luatools 下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/)；
2. 支持 Air8101B、`exsip`、`exaudio` 和 VoIP 功能的固件；
3. 本目录下全部脚本；
4. MicroSIP、Linphone 或其他兼容的 SIP 客户端；
5. 一台可访问的 SIP 服务器及两个可用 SIP 账号。

使用 Luatools 烧录时勾选“添加默认 lib”，并将本目录内的脚本完整加入项目。

## 四、配置方法

### 4.1 配置 WiFi

打开 `netdrv/netdrv_wifi.lua`，将下面的参数改为现场 2.4 GHz WiFi：

```lua
ssid = "你的WiFi名称",
password = "你的WiFi密码"
```

### 4.2 配置以太网

启用 `netdrv_eth_spi`，并将 `netdrv/netdrv_eth_spi.lua` 中从 Air8000 沿用的 `ETHERNET`、GPIO140、SPI1、GPIO12 和 GPIO21 改为 1.3 节所列的 Air8101B 参数。路由器应开启 DHCP，使 AirETH_1000 自动获取 IP。

### 4.3 配置外挂 4G

4G 场景不能只启用当前 `netdrv_4g.lua` 中监听原生 `socket.LWIP_GP` 的代码。应先按照 1.4 节的官方教程完成 Air780EPM 端桥接程序，然后在 Air8101B 端通过 `airlink_4G` 加入 `exnetif.set_priority_order`。

确认 Air780EPM 已驻网、AirLink 已就绪，并且 Air8101B 收到 4G 虚拟网卡的 `IP_READY` 后，再启动 SIP 注册。

### 4.4 配置多网融合

多网融合场景在 `netdrv/netdrv_multiple.lua` 中依优先级排列网卡。例如以太网优先、WiFi 次之、4G 兜底。数组顺序即优先级顺序。SIP/VoIP 使用 UDP 信令和 RTP 媒体流，通话中直接切换出口可能使现有会话失效，因此本 Demo 应重点验证：

- 空闲状态下高优先级网卡上线后，SIP 能否重新注册到新网卡；
- 当前网卡断开后，能否切换到下一可用网卡并重新注册；
- 已建立通话时保持原网卡，通话结束后再进行网卡切换。

### 4.5 配置模块 SIP 账号

打开 `sip_app/sip_app_main.lua`，修改 `SIP_CONFIG`：

```lua
local SIP_CONFIG = {
    sip_server_addr = "SIP服务器地址",
    sip_server_port = 8910,
    sip_domain = "SIP域名或服务器地址",
    sip_username = "模块使用的SIP账号",
    sip_password = "模块SIP账号密码",
    sip_transport = exsip.TRANSPORT_UDP,
    auto_answer = true,
    delay_auto_answer = 5,
}
```

- `sip_server_addr`、`sip_server_port`：SIP 服务器地址和端口；
- `sip_domain`：SIP 域，应与服务器配置一致；
- `sip_username`、`sip_password`：Air8101B 模块注册使用的账号和密码；
- `sip_transport`：按服务器要求选择 UDP 或 TCP；
- `auto_answer = true`：启用自动接听；
- `delay_auto_answer = 5`：来电 5 秒后自动接听。

不要将真实生产账号和密码提交到公开仓库。

### 4.6 配置 SIP 客户端

在 MicroSIP 或 Linphone 中填写：

- SIP 服务器、端口、域名：与模块配置相同；
- 用户名和密码：填写另一个 SIP 账号；
- 传输协议：与服务器要求及测试环境一致。

客户端和模块两个账号均显示注册成功后，使用客户端拨打模块的 `sip_username`。

#### PC 端软件：MicroSIP

下载链接：[点击下载MicroSIP](https://www.microsip.org/downloads)

##### 添加账号信息

![](https://docs.openluat.com/air8000/luatos/app/multimedia/sip/image/sip_img2.png)

##### 来电\拨号\通话

![](https://docs.openluat.com/air8000/luatos/app/multimedia/sip/image/sip_img3.png)
![](https://docs.openluat.com/air8000/luatos/app/multimedia/sip/image/sip_img4.png)
![](https://docs.openluat.com/air8000/luatos/app/multimedia/sip/image/sip_img5.png)

#### 4.4 安卓版软件：Linphone

下载链接：[点击下载Linphone](https://www.pgyer.com/53b4d12991b2582c45497671bfcb7201)

##### 添加账号信息

![](https://docs.openluat.com/air8000/luatos/app/multimedia/sip/image/sip_img6.jpg)
![](https://docs.openluat.com/air8000/luatos/app/multimedia/sip/image/sip_img7.jpg)
![](https://docs.openluat.com/air8000/luatos/app/multimedia/sip/image/sip_img8.jpg)

##### 来电\拨号\通话

![](https://docs.openluat.com/air8000/luatos/app/multimedia/sip/image/sip_img9.jpg)
![](https://docs.openluat.com/air8000/luatos/app/multimedia/sip/image/sip_img10.jpg)
![](https://docs.openluat.com/air8000/luatos/app/multimedia/sip/image/sip_img11.jpg)
![](https://docs.openluat.com/air8000/luatos/app/multimedia/sip/image/sip_img12.jpg)

## 五、演示步骤

四种场景都按以下基础流程测试：

1. 断电完成 Air8101B 与 AirAUDIO_1000 的连接，将 PA 开关拨到 OFF，并接好喇叭。
2. 按场景连接 WiFi、AirETH_1000 或 Air780EPM 硬件。
3. 在 `netdrv_device.lua` 中仅启用当前场景对应的网络模块，并完成网络参数配置。
4. 修改模块 SIP 账号及 SIP 客户端账号参数。
5. 使用 Luatools 烧录匹配的固件和全部脚本；4G 场景还要烧录 Air780EPM 端程序。
6. 设备启动后等待当前网卡获得 IP，并等待模块 SIP 账号注册成功。
7. 打开 SIP 客户端，确认另一个账号注册成功，然后拨打模块 SIP 账号。
8. 模块收到来电后等待约 5 秒自动接听；通过扩展板麦克风和喇叭验证双向语音。
9. 在 SIP 客户端挂断，确认模块恢复到可再次呼入的就绪状态。

### 5.1 场景一：WiFi 单网卡

启用 `require "netdrv_wifi"`。确认 WiFi 获得 IP 后完成呼入、自动接听、双向通话和挂断测试。

### 5.2 场景二：以太网单网卡

启用 `require "netdrv_eth_spi"`。确认 CH390 初始化成功、网线 Link Up 且 DHCP 获得 IP 后完成 SIP 通话测试。

### 5.3 场景三：4G 单网卡

启用适配 Air8101B AirLink 4G 的 `netdrv_4g`。先确认 Air780EPM 驻网和 AirLink 桥接正常，再确认 Air8101B 的 4G 虚拟网卡获得 IP，并完成 SIP 通话测试。

### 5.4 场景四：多网融合

启用 `require "netdrv_multiple"`，确认三个网卡的硬件参数和优先级均已改为 Air8101B 配置。建议依次验证：

1. 仅保留 4G，等待 SIP 通过 4G 注册；
2. 在 SIP 空闲状态接通 WiFi，确认切换并重新注册；
3. 在 SIP 空闲状态接通以太网，确认切换到最高优先级网卡并重新注册；
4. 每次切换后由 SIP 客户端呼入，验证自动接听和双向语音；
5. 通话中不要主动拔除当前承载 RTP 的网卡，通话结束后再验证下一次切换。

> **多网卡场景图片**
![](https://docs.openluat.com/air8101/luatos/app/multimedia/sip/images/8101_sip_netdrv_multiple.jpg)

## 六、相关日志

### 6.1 WiFi 联网成功

应看到 WiFi 已连接、获取 IP 以及 `IP_READY` 等信息。

[2026-07-28 13:50:58.758][CPU0][CAPP/N][000000002.668]:[KW:]conn vif0-0,auth_type:0,bssid:7692-139f-bd21,ssid:admin-降功耗，找合宙！,is encryp:8.</span><br />
[2026-07-28 13:50:58.766][CPU0][CAPP/N][000000002.669]:chan_ctxt_add: CTXT0,freq2467MHz,bw20MHz,pwr127dBm</span><br />
[2026-07-28 13:50:58.774][CPU0][CAPP/N][000000002.669]:chan_reg_fix:VIF0,CTXT0,type3,ctxt_s0,nb_vif0</span><br />
[2026-07-28 13:50:58.783][CPU0][CAPP/N][000000002.670]:mm_sta_add:vif 0,sta 0,status 0</span><br />
[2026-07-28 13:50:58.798][CPU0][CAPP/N][000000002.713]:[KW:]auth_send:seq1, txtype0, auth_type0, seq46</span><br />
[2026-07-28 13:50:58.800][CPU0][CAPP/N][000000002.716]:[KW:]sm_auth_handler: status code 0, tx status 0x80800000</span><br />
[2026-07-28 13:50:58.807][CPU0][CAPP/N][000000002.716]:[KW:]assoc_req_send:is ht, seq_num:47</span><br />
[2026-07-28 13:50:58.816][CPU0][CAPP/N][000000002.741]:[KW:]assoc_rsp:status0,tx_s0x80800000</span><br />
[2026-07-28 13:50:58.824][CPU0][CAPP/N][000000002.741]:[KW:]mm_set_vif_state,vif=0,vif_type=0,is_active=1, aid=0x7,rssi=-44</span><br />
[2026-07-28 13:50:58.834][CPU0][CAPP/N][000000002.743]:State: ASSOCIATING -> ASSOCIATED</span><br />
[2026-07-28 13:50:58.898][CPU0][CAPP/N][000000002.841]:State: ASSOCIATED -> 4WAY_HANDSHAKE</span><br />
[2026-07-28 13:50:58.903][CPU0][CAPP/N][000000002.842]:WPA: TK 28084f68b</span><br />
[2026-07-28 13:50:58.911][CPU0][CAPP/N][000000002.849]:State: 4WAY_HANDSHAKE -> 4WAY_HANDSHAKE</span><br />
[2026-07-28 13:50:58.919][CPU0][CAPP/N][000000002.851]:add CCMP</span><br />
[2026-07-28 13:50:58.929][CPU0][CAPP/N][000000002.851]:State: 4WAY_HANDSHAKE -> GROUP_HANDSHAKE</span><br />
[2026-07-28 13:50:58.936][CPU0][CAPP/N][000000002.852]:add CCMP</span><br />
[2026-07-28 13:50:58.945][CPU0][CAPP/N][000000002.852]:State: GROUP_HANDSHAKE -> COMPLETED</span><br />
[2026-07-28 13:50:58.953][CPU0][CAPP/N][000000002.853]:sta ip start</span><br />
[2026-07-28 13:50:58.965][CPU0][CAPP/N][000000002.854]:[KW:]sta:DHCP_DISCOVER()</span><br />
[2026-07-28 13:50:58.972][CPU0][CAPP/N][000000002.863]:[KW:]sta:DHCP_OFFER received in DHCP_STATE_SELECTING state</span><br />
[2026-07-28 13:50:58.982][CPU0][CAPP/N][000000002.863]:[KW:]sta:DHCP_REQUEST(netif=280655bc) en   1</span><br />
[2026-07-28 13:50:58.989][CPU0][CAPP/N][000000002.871]:[KW:]sta:DHCP_ACK received</span><br />
[2026-07-28 13:50:58.998][CPU0][CAPP/N][000000002.873]:[KW:]me dhcp done vif:0</span><br />
[2026-07-28 13:50:59.005][CPU0][CAPP/N][000000002.875]:event <2 0> has no cb</span><br />
[2026-07-28 13:50:59.014][CPU2][CAPP/N][000000002.876]:sta ip start</span><br />
[2026-07-28 13:50:59.022][CPU2][LTOS/N][000000002.877]:event_module 1 event_id 2</span><br />
<mark>[2026-07-28 13:50:59.032][CPU2][LTOS/N][000000002.877]:STA connected admin-降功耗，找合宙！ </span><br />
[2026-07-28 13:50:59.040][CPU2][LTOS/N][000000002.878]:event_module 2 event_id 0</span><br />
[2026-07-28 13:50:59.050][CPU2][LTOS/N][000000002.878]:ipv4 got!! 192.168.1.167</span><br />
[2026-07-28 13:50:59.057][CPU2][LTOS/N][000000002.879]:network ready 2, setup dns server</span><br />
[2026-07-28 13:50:59.067][CPU1][LTOS/N][000000002.880]:I/user.收到STA事件 CONNECTED admin-降功耗，找合宙！</span><br />
[2026-07-28 13:50:59.082][CPU2][LTOS/N][000000002.888]:set dns server to 192.168.1.1</span><br />
[2026-07-28 13:50:59.084][CPU2][LTOS/N][000000002.888]:设置DNS服务器 id 2 index 3 ip 192.168.1.1</span><br />
[2026-07-28 13:50:59.092][CPU1][LTOS/N][000000002.889]:sta ip 192.168.1.167</mark></span><br />
[2026-07-28 13:50:59.102][CPU1][LTOS/N][000000002.889]:I/user.dnsproxy 开始监听</span><br />
[2026-07-28 13:50:59.115][CPU1][LTOS/N][000000002.889]:设置DNS服务器 id 2 index 0 ip 223.5.5.5</span><br />
[2026-07-28 13:50:59.118][CPU1][LTOS/N][000000002.890]:设置DNS服务器 id 2 index 1 ip 114.114.114.114</span><br />
[2026-07-28 13:50:59.125][CPU1][LTOS/N][000000002.890]:I/user.netdrv_wifi.ip_ready_func IP_READY 192.168.1.167 255.255.255.0 192.168.1.1 nil</span><br />


### 6.2 SIP 注册成功

应看到 SIP 初始化、认证挑战、注册成功和服务就绪等信息。

[2026-07-28 13:50:59.138][CPU1][LTOS/N][000000002.891]:I/user.sip_app_main_task_func recv IP_READY 2 2</span><br />
[2026-07-28 13:50:59.146][CPU1][LTOS/N][000000002.891]:I/user.start 开始初始化 SIP，当前状态: STATE_INITING</span><br />
[2026-07-28 13:50:59.154][CPU1][LTOS/N][000000002.892]:I/user.exaudio.setup 当前使用新音频框架</span><br />
[2026-07-28 13:50:59.163][CPU1][LTOS/N][000000002.892]:I/user.exaudio.setup DAC模式 - 通道:0, 声道:1</span><br />
[2026-07-28 13:50:59.170][CPU1][LTOS/N][000000002.892]:I/user.exaudio.setup audio_v2 DAC模式初始化</span><br />
[2026-07-28 13:50:59.179][CPU1][LTOS/N][000000002.893]:I/user.exaudio.setup audio_v2初始化完成</span><br />
[2026-07-28 13:50:59.187][CPU1][LTOS/N][000000002.893]:I/user.audio_drv exaudio.setup初始化成功</span><br />
[2026-07-28 13:50:59.198][CPU1][LTOS/N][000000002.893]:I/user.audio_drv 已设置普通播放(TTS)软件音量为: 20</span><br />
[2026-07-28 13:50:59.205][CPU1][LTOS/N][000000002.894]:I/user.audio_drv 设置mic增益, 数字增益: 0x3f true 模拟增益: 0x03 true</span><br />
[2026-07-28 13:50:59.214][CPU1][LTOS/N][000000002.894]:I/user.exsip exsip.init called, config type: table config: table: 6098E6C8</span><br />
[2026-07-28 13:50:59.222][CPU1][LTOS/N][000000002.895]:I/user.exsip init completed: 1903CFC0@180.152.6.34</span><br />
[2026-07-28 13:50:59.231][CPU1][LTOS/N][000000002.945]:I/user.exsip subscribed to IP_READY and IP_LOSE</span><br />
[2026-07-28 13:50:59.239][CPU1][LTOS/N][000000002.946]:I/user.exsip current adapter set: 2</span><br />
[2026-07-28 13:50:59.248][CPU1][LTOS/N][000000002.949]:I/user.sip SIP task uses locked adapter: nil transport: udp</span><br />
[2026-07-28 13:50:59.257][CPU1][LTOS/N][000000002.949]:I/user.sip locked_adapter initialized to default: 2</span><br />
[2026-07-28 13:50:59.265][CPU1][LTOS/N][000000002.950]:I/user.sip creating socket with adapter: 2 locked_adapter: 2</span><br />
[2026-07-28 13:50:59.275][CPU1][LTOS/N][000000002.951]:connect to 180.152.6.34,8910</span><br />
[2026-07-28 13:50:59.284][CPU2][LTOS/N][000000002.952]:adapter 2 connect 180.152.6.34:8910 UDP</span><br />
[2026-07-28 13:50:59.299][CPU1][LTOS/N][000000002.953]:I/user.exsip started adapter nil</span><br />
[2026-07-28 13:50:59.301][CPU1][LTOS/N][000000002.957]:I/user.sip send REGISTER 180.152.6.34 8910</span><br />
[2026-07-28 13:50:59.309][CPU1][LTOS/N][000000002.958]:I/user.exsip event: lifecycle action: online</span><br />
[2026-07-28 13:50:59.318][CPU1][LTOS/N][000000002.959]:I/user.exsip lifecycle: online</span><br />
[2026-07-28 13:50:59.326][CPU1][LTOS/N][000000002.959]:I/user.sip_callback STATE_INITING lifecycle online table: 60970048 nil</span><br />
[2026-07-28 13:50:59.338][CPU1][LTOS/N][000000002.960]:I/user.sip_callback lifecycle event: online</span><br />
[2026-07-28 13:50:59.347][CPU1][LTOS/N][000000002.960]:I/user.sip_callback SIP 服务已在线，本地IP地址为： 192.168.1.167</span><br />
[2026-07-28 13:51:00.753][CPU1][LTOS/N][000000004.709]:I/user.sip resp 401 Unauthorized from 180.152.6.34 8910</span><br />
[2026-07-28 13:51:00.756][CPU1][LTOS/N][000000004.715]:I/user.sip send REGISTER (auth) cseq 2</span><br />
[2026-07-28 13:51:00.764][CPU1][LTOS/N][000000004.717]:I/user.exsip event: register action: challenge</span><br />
[2026-07-28 13:51:00.784][CPU1][LTOS/N][000000004.718]:I/user.sip_callback STATE_INITING register challenge table: 6096C9C8 nil</span><br />
[2026-07-28 13:51:00.787][CPU1][LTOS/N][000000004.718]:I/user.sip_callback 收到认证挑战，继续注册流程</span><br />
[2026-07-28 13:51:02.614][CPU1][LTOS/N][000000006.549]:I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-07-28 13:51:02.618][CPU1][LTOS/N][000000006.552]:I/user.sip next register in 570 sec</span><br />
[2026-07-28 13:51:02.625][CPU1][LTOS/N][000000006.553]:I/user.sip UDP OPTIONS keepalive started, interval 25000 ms</span><br />
[2026-07-28 13:51:02.634][CPU1][LTOS/N][000000006.553]:I/user.exsip event: register action: ok</span><br />
[2026-07-28 13:51:02.642][CPU1][LTOS/N][000000006.553]:I/user.sip_callback STATE_INITING register ok table: 6096A4D8 nil</span><br />
[2026-07-28 13:51:02.651][CPU1][LTOS/N][000000006.554]:I/user.sip_callback 注册成功，有效期: 600 SIP响应头: table: 6096BFB0</span><br />
[2026-07-28 13:51:02.658][CPU1][LTOS/N][000000006.554]:I/user.sip_callback STATE_INITING ready nil nil nil</span><br />
<mark>[2026-07-28 13:51:02.667][CPU1][LTOS/N][000000006.554]:I/user.sip_callback SIP 服务已就绪 当前SIP状态: STATE_INITING</span><br />
[2026-07-28 13:51:02.674][CPU1][LTOS/N][000000006.555]:I/user.sip_app_main_task_func waitMsg STATE_INITING sip_callback MSG_READY nil</span><br />
[2026-07-28 13:51:02.683][CPU1][LTOS/N][000000006.555]:I/user.sip_app_main_task_func after process STATE_READY</span><br />
[2026-07-28 13:51:02.691][CPU1][LTOS/N][000000006.556]:I/user.sip_app_key SIP应用已初始化</mark></span><br />
[2026-07-28 13:51:02.700][CPU1][LTOS/N][000000006.556]:I/user.sip_app_tts_speaker SIP应用就绪，开始第一个TTS播报</span><br />
[2026-07-28 13:51:02.710][CPU2][LTOS/N][000000006.560]:I/user.tts_speaker 初始化播报: 通话服务已就绪，当前已连接WiFi，信号强度-40dBm，信号良好</span><br />
[2026-07-28 13:51:02.719][CPU2][LTOS/N][000000006.561]:I/user.tts_speaker 开始播报: 通话服务已就绪，当前已连接WiFi，信号强度-40dBm，信号良好</span><br />
[2026-07-28 13:51:02.726][CPU1][LTOS/N][000000006.569]:I/user.exaudio 播放开始 0</span><br />
[2026-07-28 13:51:12.145][CPU2][LTOS/N][000000016.090]:I/user.exaudio 播放完毕 0</span><br />
[2026-07-28 13:51:12.148][CPU2][LTOS/N][000000016.090]:I/user.tts_speaker 播报事件回调，事件类型: 1</span><br />
[2026-07-28 13:51:12.157][CPU2][LTOS/N][000000016.091]:I/user.tts_speaker 播放完成</span><br />


### 6.3 客户端呼入并自动接听

应看到 `incoming`、`ringing`，约 5 秒后出现媒体通道就绪、通话建立和 VoIP 启动信息。

[2026-07-28 14:16:46.912][CPU1][LTOS/N][000001550.848]:I/user.sip req INVITE from 180.152.6.34 8910</span><br />
[2026-07-28 14:16:46.915][CPU1][LTOS/N][000001550.850]:I/user.sip parsing remote SDP v=0</span><br />
o=FreeSWITCH 1785204156 1785204157 IN IP4 180.152.6.34</span><br />
s=FreeSWITCH</span><br />
c=IN IP4 180.152.6.34</span><br />
t=0 0</span><br />
m=audio 15252 RTP/AVP 8 0 101</span><br />
a=rtpmap:8 PCMA/8000</span><br />
a=rtpmap:0 PCMU/8000</span><br />
a=rtpmap:101 telephone-event/8000</span><br />
a=fmtp:101 0-15</span><br />
a=ptime:20</span><br />
</span><br />
<mark>[2026-07-28 14:16:46.924][CPU1][LTOS/N][000001550.855]:I/user.exsip event: call action: incoming</span><br />
[2026-07-28 14:16:46.930][CPU1][LTOS/N][000001550.856]:I/user.sip_callback STATE_READY call incoming table: 6092FED0 nil</span><br />
[2026-07-28 14:16:46.940][CPU1][LTOS/N][000001550.856]:I/user.sip_callback call event sub_event= incoming</span><br />
[2026-07-28 14:16:46.948][CPU1][LTOS/N][000001550.856]:I/user.sip_callback 来电: "Extension 11234560" <sip:11234560@180.152.6.34>;tag=QvQ4KjZ6rF2jr sip:1903CFC0@192.168.1.167:5062;received=180.165.40.195:1030 <sip:1903CFC0@192.168.1.167:5062;received=180.165.40.195:1030>;tag=2a6b9933ced5b148</span><br />
[2026-07-28 14:16:46.958][CPU1][LTOS/N][000001550.858]:I/user.exsip event: call action: ringing</span><br />
[2026-07-28 14:16:46.965][CPU1][LTOS/N][000001550.858]:I/user.sip_callback STATE_READY call ringing table: 6092A670 nil</span><br />
[2026-07-28 14:16:46.975][CPU1][LTOS/N][000001550.859]:I/user.sip_callback call event sub_event= ringing</span><br />
[2026-07-28 14:16:46.984][CPU1][LTOS/N][000001550.859]:I/user.sip_callback 对方响铃中</span><br />
[2026-07-28 14:16:46.993][CPU1][LTOS/N][000001550.859]:I/user.exsip event: media action: offer</mark></span><br />
[2026-07-28 14:16:47.008][CPU1][LTOS/N][000001550.860]:I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_INCOMING "Extension 11234560" <sip:11234560@180.152.6.34>;tag=QvQ4KjZ6rF2jr</span><br />
[2026-07-28 14:16:47.010][CPU1][LTOS/N][000001550.861]:I/user.sip_app_main_task_func after process STATE_INCOMING</span><br />
[2026-07-28 14:16:47.018][CPU1][LTOS/N][000001550.861]:I/user.sip_app_key 呼入中，来电号码： 11234560</span><br />
[2026-07-28 14:16:47.028][CPU1][LTOS/N][000001550.862]:I/user.sip_app_tts_speaker 呼入中，来电号码： 11234560</span><br />
[2026-07-28 14:16:47.039][CPU1][LTOS/N][000001550.863]:I/user.tts_speaker 收到来电，号码 1 1 2 3 4 5 6 0</span><br />
[2026-07-28 14:16:47.046][CPU1][LTOS/N][000001550.863]:I/user.tts_speaker 开始播报: 收到1 1 2 3 4 5 6 0来电</span><br />
[2026-07-28 14:16:47.056][CPU1][LTOS/N][000001550.870]:I/user.exaudio 播放开始 3</span><br />
[2026-07-28 14:16:48.075][CPU2][LTOS/N][000001552.007]:I/user.sip send OPTIONS ping</span><br />
[2026-07-28 14:16:48.758][CPU1][LTOS/N][000001552.689]:I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-07-28 14:16:50.468][CPU2][LTOS/N][000001554.397]:I/user.exaudio 播放完毕 3</span><br />
[2026-07-28 14:16:50.472][CPU2][LTOS/N][000001554.398]:I/user.tts_speaker 播报事件回调，事件类型: 1</span><br />
[2026-07-28 14:16:50.480][CPU2][LTOS/N][000001554.398]:I/user.tts_speaker 播放完成</span><br />
[2026-07-28 14:16:50.717][CPU1][LTOS/N][000001554.646]:print from irq 2 0 0</span><br />
<mark>[2026-07-28 14:16:51.919][CPU1][LTOS/N][000001555.858]:I/user.exsip answering call</span><br />
[2026-07-28 14:16:51.923][CPU1][LTOS/N][000001555.858]:I/user.sip cmd answer </span><br />
[2026-07-28 14:16:51.931][CPU1][LTOS/N][000001555.859]:I/user.test ip 192.168.1.167</span><br />
[2026-07-28 14:16:51.946][CPU1][LTOS/N][000001555.863]:I/user.sip answer 200 OK</mark></span><br />
[2026-07-28 14:16:52.339][CPU1][LTOS/N][000001556.274]:I/user.sip req ACK from 180.152.6.34 8910</span><br />
[2026-07-28 14:16:52.343][CPU1][LTOS/N][000001556.275]:I/user.exsip event: media action: ready</span><br />
[2026-07-28 14:16:52.351][CPU1][LTOS/N][000001556.275]:I/user.exsip media ready 180.152.6.34 15252 PCMU</span><br />
[2026-07-28 14:16:52.361][CPU1][LTOS/N][000001556.276]:I/user.exsip start voip engine with adapter: 2 remote: 180.152.6.34:15252</span><br />
[2026-07-28 14:16:52.368][CPU1][LTOS/N][000001556.276]:voip start event</span><br />
[2026-07-28 14:16:52.378][CPU1][LTOS/N][000001556.276]:voip config: remote=180.152.6.34:15252 codec=0 ptime=20</span><br />
[2026-07-28 14:16:52.385][CPU1][LTOS/N][000001556.276]:voio origin: samples=8000</span><br />
[2026-07-28 14:16:52.394][CPU1][LTOS/N][000001556.276]:voio frame: samples=160 bytes=320</span><br />
[2026-07-28 14:16:52.404][CPU1][LTOS/N][000001556.277]:codec encoder bind success type=7</span><br />
[2026-07-28 14:16:52.411][CPU2][LTOS/N][000001556.277]:I/user.exsip voip engine started 180.152.6.34:15252 codec=PCMU adapter nil</span><br />
<mark>[2026-07-28 14:16:52.421][CPU2][LTOS/N][000001556.278]:I/user.sip_callback STATE_INCOMING media ready table: 60948F90 nil</span><br />
[2026-07-28 14:16:52.430][CPU2][LTOS/N][000001556.278]:I/user.sip_callback 媒体通道就绪 180.152.6.34:15252</span><br />
[2026-07-28 14:16:52.438][CPU2][LTOS/N][000001556.279]:I/user.sip call established (incoming)</span><br />
[2026-07-28 14:16:52.447][CPU2][LTOS/N][000001556.279]:I/user.exsip event: call action: established</span><br />
[2026-07-28 14:16:52.455][CPU2][LTOS/N][000001556.280]:I/user.sip_callback STATE_INCOMING call connected table: 60956F80 nil</span><br />
[2026-07-28 14:16:52.464][CPU2][LTOS/N][000001556.280]:I/user.sip_callback call event sub_event= connected</span><br />
[2026-07-28 14:16:52.472][CPU2][LTOS/N][000001556.280]:I/user.sip_callback 通话已建立</mark></span><br />
[2026-07-28 14:16:52.481][CPU2][LTOS/N][000001556.282]:I/user.sip_app_main_task_func waitMsg STATE_INCOMING sip_callback MSG_CONNECTED nil</span><br />
[2026-07-28 14:16:52.488][CPU2][LTOS/N][000001556.282]:I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />


### 6.4 通话与挂断

通话中应周期性看到 VoIP 收发统计；客户端挂断后应看到媒体停止、通话结束及状态恢复。

[2026-07-28 14:16:52.498][CPU2][LTOS/N][000001556.283]:I/user.sip_app_key 通话建立成功</span><br />
[2026-07-28 14:16:52.505][CPU1][LTOS/N][000001556.284]:aec ready frame=160 tail_ms=200 denoise=1</span><br />
[2026-07-28 14:16:52.517][CPU2][LTOS/N][000001556.285]:adapter 2 connect 180.152.6.34:15252 UDP</span><br />
[2026-07-28 14:16:52.525][CPU2][LTOS/N][000001556.287]:I/user.exsip voip state: started</span><br />
<mark>[2026-07-28 14:16:52.532][CPU2][LTOS/N][000001556.288]:I/user.sip_callback STATE_CONNECTED voip state started nil</span><br />
[2026-07-28 14:16:52.540][CPU2][LTOS/N][000001556.288]:I/user.sip_callback VoIP状态: started</span><br />
[2026-07-28 14:16:52.549][CPU2][LTOS/N][000001556.289]:I/user.audio_drv 设置喇叭音量(DAC硬件增益): 40 实际生效: 40</span><br />
[2026-07-28 14:16:54.804][CPU1][LTOS/N][000001558.745]:jb resync: expected_seq 37513 -> 37511 (pending 1)</span><br />
[2026-07-28 14:16:57.351][CPU2][LTOS/N][000001561.288]:I/user.sip_callback STATE_CONNECTED voip stats table: 60956980 nil</span><br />
[2026-07-28 14:16:57.354][CPU2][LTOS/N][000001561.289]:I/user.sip_callback VoIP统计 - 发送: 249 接收: 158 丢失: 0</span><br />
[2026-07-28 14:17:02.346][CPU2][LTOS/N][000001566.287]:I/user.sip_callback STATE_CONNECTED voip stats table: 60956710 nil</span><br />
[2026-07-28 14:17:02.351][CPU2][LTOS/N][000001566.288]:I/user.sip_callback VoIP统计 - 发送: 499 接收: 406 丢失: 0</mark></span><br />
[2026-07-28 14:17:05.056][CPU1][LTOS/N][000001568.985]:jb resync: expected_seq 38023 -> 37957 (pending 4)</span><br />
[2026-07-28 14:17:05.118][CPU1][LTOS/N][000001569.045]:jb resync: expected_seq 37960 -> 37971 (pending 3)</span><br />
[2026-07-28 14:17:05.164][CPU1][LTOS/N][000001569.105]:jb resync: expected_seq 37974 -> 37976 (pending 2)</span><br />
[2026-07-28 14:17:05.227][CPU1][LTOS/N][000001569.165]:jb resync: expected_seq 37979 -> 38010 (pending 1)</span><br />
<mark>[2026-07-28 14:17:06.759][CPU1][LTOS/N][000001570.707]:I/user.sip req BYE from 180.152.6.34 8910</span><br />
[2026-07-28 14:17:06.762][CPU2][LTOS/N][000001570.714]:I/user.exsip event: media action: stop</span><br />
[2026-07-28 14:17:06.770][CPU2][LTOS/N][000001570.714]:I/user.exsip voip engine stopping</span><br />
[2026-07-28 14:17:06.779][CPU2][LTOS/N][000001570.717]:I/user.sip_callback STATE_CONNECTED media stop table: 60922450 nil</span><br />
[2026-07-28 14:17:06.790][CPU2][LTOS/N][000001570.717]:I/user.sip_callback 媒体通道已关闭，关闭原因： peer_hangup</span><br />
[2026-07-28 14:17:06.797][CPU2][LTOS/N][000001570.717]:I/user.sip peer hung up</span><br />
[2026-07-28 14:17:06.804][CPU2][LTOS/N][000001570.718]:I/user.exsip event: call action: ended</span><br />
[2026-07-28 14:17:06.814][CPU2][LTOS/N][000001570.718]:I/user.sip_callback STATE_CONNECTED call ended table: 609222C8 nil</span><br />
[2026-07-28 14:17:06.822][CPU2][LTOS/N][000001570.718]:I/user.sip_callback call event sub_event= ended</span><br />
[2026-07-28 14:17:06.832][CPU2][LTOS/N][000001570.718]:I/user.sip_callback 通话已结束，结束原因为： peer_hangup 通话对象： table: 609383E0</span><br />
[2026-07-28 14:17:06.839][CPU2][LTOS/N][000001570.721]:network_default_socket_callback 1147:cb ctrl invaild 28022a08 F2000004</span><br />
[2026-07-28 14:17:06.849][CPU2][LTOS/N][000001570.721]:03 00 00 00 00 00 00 00 </span><br />
[2026-07-28 14:17:06.858][CPU1][LTOS/N][000001570.723]:I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_callback MSG_DISCONNECTED peer_hangup</mark></span><br />
[2026-07-28 14:17:06.866][CPU1][LTOS/N][000001570.724]:I/user.sip_app_main_task_func after process STATE_READY</span><br />
[2026-07-28 14:17:06.875][CPU1][LTOS/N][000001570.724]:I/user.sip_app_key 通话已断开</span><br />
[2026-07-28 14:17:06.883][CPU1][LTOS/N][000001570.725]:I/user.tts_speaker 播报挂断，原因 peer_hangup -> 对方挂断</span><br />
[2026-07-28 14:17:06.891][CPU1][LTOS/N][000001570.726]:I/user.tts_speaker 开始播报: 对方挂断</span><br />
[2026-07-28 14:17:06.900][CPU1][LTOS/N][000001570.733]:I/user.exsip voip state: stopped</span><br />
[2026-07-28 14:17:06.908][CPU1][LTOS/N][000001570.734]:I/user.sip_callback STATE_READY voip state stopped nil</span><br />
[2026-07-28 14:17:06.916][CPU1][LTOS/N][000001570.734]:I/user.sip_callback VoIP状态: stopped</span><br />
[2026-07-28 14:17:06.924][CPU1][LTOS/N][000001570.735]:I/user.exaudio 播放开始 4</span><br />
[2026-07-28 14:17:08.553][CPU2][LTOS/N][000001572.507]:I/user.exaudio 播放完毕 4</span><br />
[2026-07-28 14:17:08.557][CPU2][LTOS/N][000001572.507]:I/user.tts_speaker 播报事件回调，事件类型: 1</span><br />
[2026-07-28 14:17:08.565][CPU2][LTOS/N][000001572.508]:I/user.tts_speaker 播放完成</span><br />
[2026-07-28 14:17:08.824][CPU1][LTOS/N][000001572.755]:print from irq 2 0 0</span><br />


### 6.5 主动呼出

[2026-07-28 14:11:47.980][CPU2][LTOS/N][000001251.917]:I/user.sip send OPTIONS ping</span><br />
[2026-07-28 14:11:48.421][CPU1][LTOS/N][000001252.353]:I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-07-28 14:11:52.449][CPU2][LTOS/N][000001256.386]:I/user.sip_app_key 按下BOOT键</span><br />
[2026-07-28 14:11:52.451][CPU2][LTOS/N][000001256.388]:I/user.sip_app_tts_speaker 收到拨号请求，准备播报拨号信息</span><br />
[2026-07-28 14:11:52.452][CPU2][LTOS/N][000001256.390]:I/user.sip_app_main_task_func waitMsg STATE_READY sip_app_key MSG_DIAL 11234560</span><br />
[2026-07-28 14:11:52.453][CPU2][LTOS/N][000001256.390]:I/user.exsip calling: 11234560 nil</span><br />
[2026-07-28 14:11:52.454][CPU2][LTOS/N][000001256.391]:I/user.sip_app_main_task_func after process STATE_DIALING</span><br />
[2026-07-28 14:11:52.455][CPU2][LTOS/N][000001256.395]:I/user.tts_speaker 播报拨号 1 1 2 3 4 5 6 0</span><br />
[2026-07-28 14:11:52.456][CPU2][LTOS/N][000001256.396]:I/user.tts_speaker 开始播报: 正在拨号，号码1 1 2 3 4 5 6 0</span><br />
[2026-07-28 14:11:52.457][CPU2][LTOS/N][000001256.404]:I/user.sip cmd call table: 609676A0</span><br />
[2026-07-28 14:11:52.480][CPU2][LTOS/N][000001256.412]:I/user.test ip 192.168.1.167</span><br />
[2026-07-28 14:11:52.483][CPU2][LTOS/N][000001256.418]:I/user.sip setting call timeout 30 seconds</span><br />
[2026-07-28 14:11:52.484][CPU2][LTOS/N][000001256.432]:I/user.sip send INVITE sip:11234560@180.152.6.34</span><br />
[2026-07-28 14:11:52.485][CPU2][LTOS/N][000001256.436]:I/user.exaudio 播放开始 1</span><br />
[2026-07-28 14:11:53.738][CPU1][LTOS/N][000001257.677]:I/user.sip resp 407 Proxy Authentication Required from 180.152.6.34 8910</span><br />
[2026-07-28 14:11:53.769][CPU1][LTOS/N][000001257.709]:I/user.exsip event: call action: auth_retry</span><br />
[2026-07-28 14:11:55.577][CPU1][LTOS/N][000001259.519]:I/user.sip resp 100 Trying from 180.152.6.34 8910</span><br />
[2026-07-28 14:11:57.262][CPU2][LTOS/N][000001261.193]:I/user.exaudio 播放完毕 1</span><br />
[2026-07-28 14:11:57.267][CPU2][LTOS/N][000001261.194]:I/user.tts_speaker 播报事件回调，事件类型: 1</span><br />
[2026-07-28 14:11:57.270][CPU2][LTOS/N][000001261.194]:I/user.tts_speaker 播放完成</span><br />
<mark>[2026-07-28 14:11:57.434][CPU1][LTOS/N][000001261.362]:I/user.sip resp 180 Ringing from 180.152.6.34 8910</span><br />
[2026-07-28 14:11:57.437][CPU1][LTOS/N][000001261.367]:I/user.sip invite provisional response 180 Ringing</span><br />
[2026-07-28 14:11:57.438][CPU1][LTOS/N][000001261.367]:I/user.exsip event: call action: ringing</span><br />
[2026-07-28 14:11:57.439][CPU1][LTOS/N][000001261.368]:I/user.sip_callback STATE_DIALING call ringing table: 609292E0 nil</span><br />
[2026-07-28 14:11:57.440][CPU1][LTOS/N][000001261.368]:I/user.sip_callback call event sub_event= ringing</span><br />
[2026-07-28 14:11:57.441][CPU1][LTOS/N][000001261.368]:I/user.sip_callback 对方响铃中</mark></span><br />
[2026-07-28 14:11:57.512][CPU1][LTOS/N][000001261.442]:print from irq 2 0 0</span><br />


### 6.6 以太网单网卡

<mark>[2026-07-29 16:26:47.156][CPU1][LTOS/N][000000000.998]:I/user.初始化以太网</mark></span><br />
[2026-07-29 16:26:47.165][CPU1][LTOS/N][000000000.999]:I/user.config.opts.spi 1 ,config.type 1</span><br />
[2026-07-29 16:26:47.175][CPU1][LTOS/N][000000001.000]:SPI(1) gpio init : wire 3 clk 2 cs 3 mosi 4 miso 5</span><br />
[2026-07-29 16:26:47.185][CPU1][LTOS/N][000000001.000]:I/user.main open spi 0</span><br />
[2026-07-29 16:26:47.193][CPU1][LTOS/N][000000001.001]:注册CH390H设备(4) SPI id 1 cs 3 irq 8</span><br />
[2026-07-29 16:26:47.204][CPU1][LTOS/N][000000001.001]:malloc queue in psram item count 1024 size 12</span><br />
[2026-07-29 16:26:47.212][CPU2][LTOS/N][000000001.001]:adapter 4 netif init ok</span><br />
[2026-07-29 16:26:47.222][CPU1][LTOS/N][000000001.001]:task started</span><br />
[2026-07-29 16:26:47.232][CPU1][LTOS/N][000000001.002]:注册完成 adapter 4 spi 1 cs 3 irq 8</span><br />
[2026-07-29 16:26:47.242][CPU1][LTOS/N][000000001.002]:I/user.以太网初始化完成</span><br />
[2026-07-29 16:26:47.252][CPU1][LTOS/N][000000001.003]:I/user.netdrv 订阅socket连接状态变化事件 Ethernet</span><br />
[2026-07-29 16:26:47.260][CPU1][LTOS/N][000000001.037]:enable irq mode in pin 8</span><br />
[2026-07-29 16:26:47.270][CPU1][LTOS/N][000000001.047]:初始化MAC 701988D30068</span><br />
[2026-07-29 16:26:47.282][CPU2][LTOS/N][000000001.053]:D/user.exaudio version -> 202607171800</span><br />
[2026-07-29 16:26:47.290][CPU2][LTOS/N][000000001.059]:D/user.exsip version -> 202607021200</span><br />
[2026-07-29 16:26:47.302][CPU2][LTOS/N][000000001.124]:I/user.exsip unified callback registered for all events</span><br />
<mark>[2026-07-29 16:26:47.317][CPU2][LTOS/N][000000001.125]:W/user.sip_app_main_task_func wait IP_READY 4 4</mark></span><br />
[2026-07-29 16:26:47.321][CPU2][LTOS/N][000000001.126]:I/user.start_req SIP 主任务已启动</span><br />
[2026-07-29 16:26:48.256][CPU2][LTOS/N][000000002.126]:W/user.sip_app_main_task_func wait IP_READY 4 4</span><br />
......</span><br />
[2026-07-29 16:26:49.442][CPU2][LTOS/N][000000003.158]:DHCP ready adapter=4 IP=192.168.1.100 gw=192.168.1.1</span><br />
[2026-07-29 16:26:49.451][CPU1][LTOS/N][000000003.159]:I/user.dnsproxy 开始监听</span><br />
[2026-07-29 16:26:49.459][CPU1][LTOS/N][000000003.160]:I/user.sip_app_main_task_func recv IP_READY 4 4</span><br />
[2026-07-29 16:26:49.472][CPU1][LTOS/N][000000003.161]:I/user.start 开始初始化 SIP，当前状态: STATE_INITING</span><br />
[2026-07-29 16:26:49.482][CPU1][LTOS/N][000000003.161]:I/user.exaudio.setup 当前使用新音频框架</span><br />
[2026-07-29 16:26:49.491][CPU1][LTOS/N][000000003.161]:I/user.exaudio.setup DAC模式 - 通道:0, 声道:1</span><br />
[2026-07-29 16:26:49.504][CPU1][LTOS/N][000000003.162]:I/user.exaudio.setup audio_v2 DAC模式初始化</span><br />
[2026-07-29 16:26:49.512][CPU1][LTOS/N][000000003.163]:I/user.exaudio.setup audio_v2初始化完成</span><br />
[2026-07-29 16:26:49.522][CPU1][LTOS/N][000000003.163]:I/user.audio_drv exaudio.setup初始化成功</span><br />
[2026-07-29 16:26:49.531][CPU1][LTOS/N][000000003.163]:I/user.audio_drv 已设置普通播放(TTS)软件音量为: 20</span><br />
[2026-07-29 16:26:49.541][CPU1][LTOS/N][000000003.164]:I/user.audio_drv 设置mic增益, 数字增益: 0x3f true 模拟增益: 0x03 true</span><br />
[2026-07-29 16:26:49.553][CPU1][LTOS/N][000000003.164]:I/user.exsip exsip.init called, config type: table config: table: 6098E5F8</span><br />
[2026-07-29 16:26:49.561][CPU1][LTOS/N][000000003.165]:I/user.exsip init completed: 1903CFC0@180.152.6.34</span><br />
[2026-07-29 16:26:49.572][CPU1][LTOS/N][000000003.228]:I/user.exsip subscribed to IP_READY and IP_LOSE</span><br />
[2026-07-29 16:26:49.584][CPU1][LTOS/N][000000003.228]:I/user.exsip current adapter set: 4</span><br />
[2026-07-29 16:26:49.592][CPU1][LTOS/N][000000003.231]:I/user.sip SIP task uses locked adapter: nil transport: udp</span><br />
[2026-07-29 16:26:49.602][CPU1][LTOS/N][000000003.232]:I/user.sip locked_adapter initialized to default: 4</span><br />
[2026-07-29 16:26:49.620][CPU1][LTOS/N][000000003.233]:I/user.sip creating socket with adapter: 4 locked_adapter: 4</span><br />
[2026-07-29 16:26:49.623][CPU1][LTOS/N][000000003.234]:connect to 180.152.6.34,8910</span><br />
[2026-07-29 16:26:49.632][CPU2][LTOS/N][000000003.234]:adapter 4 connect 180.152.6.34:8910 UDP</span><br />
[2026-07-29 16:26:49.643][CPU1][LTOS/N][000000003.235]:I/user.exsip started adapter nil</span><br />
[2026-07-29 16:26:49.651][CPU1][LTOS/N][000000003.240]:I/user.sip send REGISTER 180.152.6.34 8910</span><br />
[2026-07-29 16:26:49.660][CPU2][LTOS/N][000000003.242]:I/user.exsip event: lifecycle action: online</span><br />
[2026-07-29 16:26:49.671][CPU2][LTOS/N][000000003.242]:I/user.exsip lifecycle: online</span><br />
[2026-07-29 16:26:49.686][CPU2][LTOS/N][000000003.242]:I/user.sip_callback STATE_INITING lifecycle online table: 6096ED08 nil</span><br />
[2026-07-29 16:26:49.692][CPU2][LTOS/N][000000003.243]:I/user.sip_callback lifecycle event: online</span><br />
[2026-07-29 16:26:49.702][CPU2][LTOS/N][000000003.243]:I/user.sip_callback SIP 服务已在线，本地IP地址为： 192.168.1.100</span><br />
[2026-07-29 16:26:49.710][CPU2][LTOS/N][000000003.322]:I/user.sip resp 401 Unauthorized from 180.152.6.34 8910</span><br />
[2026-07-29 16:26:49.721][CPU2][LTOS/N][000000003.330]:I/user.sip send REGISTER (auth) cseq 2</span><br />
[2026-07-29 16:26:49.729][CPU2][LTOS/N][000000003.332]:I/user.exsip event: register action: challenge</span><br />
[2026-07-29 16:26:49.740][CPU2][LTOS/N][000000003.332]:I/user.sip_callback STATE_INITING register challenge table: 6096B688 nil</span><br />
[2026-07-29 16:26:49.749][CPU2][LTOS/N][000000003.333]:I/user.sip_callback 收到认证挑战，继续注册流程</span><br />
[2026-07-29 16:26:51.340][CPU1][LTOS/N][000000005.207]:I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-07-29 16:26:51.345][CPU1][LTOS/N][000000005.209]:I/user.sip next register in 570 sec</span><br />
[2026-07-29 16:26:51.354][CPU1][LTOS/N][000000005.210]:I/user.sip UDP OPTIONS keepalive started, interval 25000 ms</span><br />
[2026-07-29 16:26:51.362][CPU1][LTOS/N][000000005.211]:I/user.exsip event: register action: ok</span><br />
[2026-07-29 16:26:51.375][CPU1][LTOS/N][000000005.211]:I/user.sip_callback STATE_INITING register ok table: 60969190 nil</span><br />
[2026-07-29 16:26:51.384][CPU1][LTOS/N][000000005.211]:I/user.sip_callback 注册成功，有效期: 600 SIP响应头: table: 6096AC50</span><br />
[2026-07-29 16:26:51.393][CPU1][LTOS/N][000000005.212]:I/user.sip_callback STATE_INITING ready nil nil nil</span><br />
<mark>[2026-07-29 16:26:51.403][CPU1][LTOS/N][000000005.212]:I/user.sip_callback SIP 服务已就绪 当前SIP状态: STATE_INITING</mark></span><br />
[2026-07-29 16:26:51.411][CPU1][LTOS/N][000000005.215]:I/user.sip req NOTIFY from 180.152.6.34 8910</span><br />
[2026-07-29 16:26:51.424][CPU2][LTOS/N][000000005.219]:I/user.sip_app_main_task_func waitMsg STATE_INITING sip_callback MSG_READY nil</span><br />
[2026-07-29 16:26:51.433][CPU2][LTOS/N][000000005.220]:I/user.sip_app_main_task_func after process STATE_READY</span><br />
[2026-07-29 16:26:51.442][CPU2][LTOS/N][000000005.220]:I/user.sip_app_key SIP应用已初始化</span><br />

### 6.7 4G 单网卡

<mark>[2026-07-29 15:02:39.614][CPU1][LTOS/N][000000000.993]:初始化AirLink</span><br />
[2026-07-29 15:02:39.672][CPU1][LTOS/N][000000000.994]:I/user.创建桥接网络设备</span><br />
[2026-07-29 15:02:39.725][CPU1][LTOS/N][000000000.995]:启动AirLink主机模式</mark></span><br />
[2026-07-29 15:02:39.779][CPU1][LTOS/N][000000000.995]:malloc queue in psram item count 1024 size 16</span><br />
[2026-07-29 15:02:39.813][CPU2][LTOS/N][000000000.995]:malloc queue in psram item count 4096 size 8</span><br />
[2026-07-29 15:02:39.851][CPU2][LTOS/N][000000000.996]:malloc queue in psram item count 4096 size 8</span><br />
[2026-07-29 15:02:39.890][CPU2][LTOS/N][000000000.996]:malloc queue in psram item count 4096 size 16</span><br />
[2026-07-29 15:02:39.925][CPU2][LTOS/N][000000000.997]:设置IP[15] 192.168.111.1 255.255.255.0 192.168.111.2 ret 0</span><br />
[2026-07-29 15:02:39.981][CPU2][LTOS/N][000000000.998]:I/user.netdrv 订阅socket连接状态变化事件 airlink_4G</span><br />
[2026-07-29 15:02:40.044][CPU2][LTOS/N][000000000.999]:I/user.airlink_4G网卡已开启 15</span><br />
[2026-07-29 15:02:40.097][CPU2][LTOS/N][000000001.000]:I/user.设置网卡 airlink_4G</span><br />
[2026-07-29 15:02:40.162][CPU2][LTOS/N][000000001.000]:I/user.exnetif publish network status airlink_4G 15</span><br />
[2026-07-29 15:02:40.204][CPU1][LTOS/N][000000001.001]:spi master id 0 cs 15 rdy 48 irq 255</span><br />
[2026-07-29 15:02:40.239][CPU1][LTOS/N][000000001.001]:SPI(0) gpio init : wire 3 clk 14 cs 15 mosi 16 miso 17</span><br />
[2026-07-29 15:02:40.276][CPU1][LTOS/N][000000001.011]:peer flags: rpc=1 frag=1 raw=0x00000302</span><br />
<mark>[2026-07-29 15:02:40.312][CPU2][LTOS/N][000000001.012]:AIRLINK_READY 1012 t 1012</span><br />
[2026-07-29 15:02:40.354][CPU1][LTOS/N][000000001.017]:4G代理网卡上线了</span><br />
[2026-07-29 15:02:40.416][CPU2][LTOS/N][000000001.017]:网卡(15)设置为UP</span><br />
[2026-07-29 15:02:40.476][CPU2][LTOS/N][000000001.018]:network ready 15, setup dns server</mark></span><br />
[2026-07-29 15:02:40.513][CPU2][LTOS/N][000000001.060]:D/user.exaudio version -> 202607171800</span><br />
[2026-07-29 15:02:40.554][CPU1][LTOS/N][000000001.066]:D/user.exsip version -> 202607021200</span><br />
[2026-07-29 15:02:40.591][CPU1][LTOS/N][000000001.140]:I/user.exsip unified callback registered for all events</span><br />
<mark>[2026-07-29 15:02:40.632][CPU2][LTOS/N][000000001.142]:I/user.sip_app_main_task_func recv IP_READY 15 15</mark></span><br />
[2026-07-29 15:02:40.671][CPU2][LTOS/N][000000001.142]:I/user.start 开始初始化 SIP，当前状态: STATE_INITING</span><br />
[2026-07-29 15:02:40.731][CPU2][LTOS/N][000000001.143]:I/user.exaudio.setup 当前使用新音频框架</span><br />
[2026-07-29 15:02:40.792][CPU1][LTOS/N][000000001.143]:I/user.exaudio.setup DAC模式 - 通道:0, 声道:1</span><br />
[2026-07-29 15:02:40.855][CPU1][LTOS/N][000000001.144]:I/user.exaudio.setup audio_v2 DAC模式初始化</span><br />
[2026-07-29 15:02:40.911][CPU1][LTOS/N][000000001.145]:I/user.exaudio.setup audio_v2初始化完成</span><br />
[2026-07-29 15:02:40.972][CPU1][LTOS/N][000000001.145]:I/user.audio_drv exaudio.setup初始化成功</span><br />
[2026-07-29 15:02:41.030][CPU1][LTOS/N][000000001.145]:I/user.audio_drv 已设置普通播放(TTS)软件音量为: 20</span><br />
[2026-07-29 15:02:41.093][CPU1][LTOS/N][000000001.146]:I/user.audio_drv 设置mic增益, 数字增益: 0x3f true 模拟增益: 0x03 true</span><br />
[2026-07-29 15:02:41.158][CPU1][LTOS/N][000000001.146]:I/user.exsip exsip.init called, config type: table config: table: 6098E6E0</span><br />
[2026-07-29 15:02:41.194][CPU1][LTOS/N][000000001.147]:I/user.exsip init completed: 1903CFC0@180.152.6.34</span><br />
[2026-07-29 15:02:41.235][CPU2][LTOS/N][000000001.216]:I/user.exsip subscribed to IP_READY and IP_LOSE</span><br />
[2026-07-29 15:02:41.280][CPU2][LTOS/N][000000001.217]:I/user.exsip current adapter set: 15</span><br />
[2026-07-29 15:02:41.317][CPU2][LTOS/N][000000001.220]:I/user.sip SIP task uses locked adapter: nil transport: udp</span><br />
[2026-07-29 15:02:41.354][CPU2][LTOS/N][000000001.220]:I/user.sip locked_adapter initialized to default: 15</span><br />
[2026-07-29 15:02:41.394][CPU2][LTOS/N][000000001.221]:I/user.sip creating socket with adapter: 15 locked_adapter: 15</span><br />
[2026-07-29 15:02:41.439][CPU2][LTOS/N][000000001.222]:connect to 180.152.6.34,8910</span><br />
[2026-07-29 15:02:41.480][CPU2][LTOS/N][000000001.223]:adapter 15 connect 180.152.6.34:8910 UDP</span><br />
[2026-07-29 15:02:41.522][CPU2][LTOS/N][000000001.224]:I/user.exsip started adapter nil</span><br />
<mark>[2026-07-29 15:02:41.564][CPU2][LTOS/N][000000001.224]:I/user.start_req SIP 主任务已启动</mark></span><br />
[2026-07-29 15:02:41.625][CPU2][LTOS/N][000000001.225]:DHCP ready adapter=15 IP=192.168.111.1 gw=192.168.111.2</span><br />
[2026-07-29 15:02:41.664][CPU2][LTOS/N][000000001.226]:设置DNS服务器 id 15 index 0 ip 223.5.5.5</span><br />
[2026-07-29 15:02:41.722][CPU2][LTOS/N][000000001.226]:设置DNS服务器 id 15 index 1 ip 114.114.114.114</span><br />
[2026-07-29 15:02:41.789][CPU2][LTOS/N][000000001.226]:I/user.netdrv_4g.ip_ready_func IP_READY 192.168.111.1 255.255.255.0 192.168.111.2 nil</span><br />
[2026-07-29 15:02:41.828][CPU2][LTOS/N][000000001.227]:I/user.exsip IP_READY 192.168.111.1 15</span><br />
[2026-07-29 15:02:41.873][CPU2][LTOS/N][000000001.227]:I/user.sip IP_READY 15</span><br />
[2026-07-29 15:02:41.909][CPU2][LTOS/N][000000001.227]:I/user.dnsproxy 开始监听</span><br />
[2026-07-29 15:02:41.963][CPU2][LTOS/N][000000001.232]:I/user.sip send REGISTER 180.152.6.34 8910</span><br />
[2026-07-29 15:02:42.001][CPU2][LTOS/N][000000001.234]:I/user.exsip event: lifecycle action: online</span><br />
[2026-07-29 15:02:42.043][CPU2][LTOS/N][000000001.234]:I/user.exsip lifecycle: online</span><br />
[2026-07-29 15:02:42.080][CPU2][LTOS/N][000000001.234]:I/user.sip_callback STATE_INITING lifecycle online table: 6096EC00 nil</span><br />
[2026-07-29 15:02:42.117][CPU2][LTOS/N][000000001.234]:I/user.sip_callback lifecycle event: online</span><br />
[2026-07-29 15:02:42.157][CPU2][LTOS/N][000000001.235]:I/user.sip_callback SIP 服务已在线，本地IP地址为： 192.168.111.1</span><br />
[2026-07-29 15:02:42.217][CPU1][LTOS/N][000000002.281]:I/user.sip resp 401 Unauthorized from 180.152.6.34 8910</span><br />
[2026-07-29 15:02:42.262][CPU2][LTOS/N][000000002.290]:I/user.sip send REGISTER (auth) cseq 2</span><br />
[2026-07-29 15:02:42.308][CPU2][LTOS/N][000000002.292]:I/user.exsip event: register action: challenge</span><br />
[2026-07-29 15:02:42.349][CPU2][LTOS/N][000000002.293]:I/user.sip_callback STATE_INITING register challenge table: 6096B4E8 nil</span><br />
[2026-07-29 15:02:42.387][CPU2][LTOS/N][000000002.293]:I/user.sip_callback 收到认证挑战，继续注册流程</span><br />
[2026-07-29 15:02:42.445][CPU1][LTOS/N][000000004.358]:I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-07-29 15:02:42.490][CPU2][LTOS/N][000000004.361]:I/user.sip next register in 570 sec</span><br />
[2026-07-29 15:02:42.537][CPU2][LTOS/N][000000004.362]:I/user.sip UDP OPTIONS keepalive started, interval 25000 ms</span><br />
<mark>[2026-07-29 15:02:42.586][CPU2][LTOS/N][000000004.363]:I/user.exsip event: register action: ok</span><br />
[2026-07-29 15:02:42.631][CPU2][LTOS/N][000000004.363]:I/user.sip_callback STATE_INITING register ok table: 60968EC0 nil</span><br />
[2026-07-29 15:02:42.674][CPU2][LTOS/N][000000004.363]:I/user.sip_callback 注册成功，有效期: 600 SIP响应头: table: 6096FA48</span><br />
[2026-07-29 15:02:42.741][CPU2][LTOS/N][000000004.363]:I/user.sip_callback STATE_INITING ready nil nil nil</span><br />
[2026-07-29 15:02:42.779][CPU2][LTOS/N][000000004.364]:I/user.sip_callback SIP 服务已就绪 当前SIP状态: STATE_INITING</span><br />
[2026-07-29 15:02:42.841][CPU2][LTOS/N][000000004.365]:I/user.sip_app_main_task_func waitMsg STATE_INITING sip_callback MSG_READY nil</span><br />
[2026-07-29 15:02:42.882][CPU2][LTOS/N][000000004.365]:I/user.sip_app_main_task_func after process STATE_READY</span><br />
[2026-07-29 15:02:42.923][CPU2][LTOS/N][000000004.366]:I/user.sip_app_key SIP应用已初始化</mark></span><br />

### 6.8 多网融合
**以太网切WIFI**</span><br />
[2026-07-29 17:37:43.301][CPU1][LTOS/N][000000072.191]:IP_LOSE 8</span><br />
[2026-07-29 17:37:43.310][CPU1][LTOS/N][000000072.192]:I/user.exsip IP_LOSE 8</span><br />
[2026-07-29 17:37:43.322][CPU1][LTOS/N][000000072.193]:I/user.ip_lose_handle 8101SPIETH</span><br />
<mark>[2026-07-29 17:37:43.330][CPU2][LTOS/N][000000072.194]:I/user.8101SPIETH 失效，切换到其他网络</mark></span><br />
[2026-07-29 17:37:43.341][CPU2][LTOS/N][000000072.195]:I/user.设置网卡 WiFi</span><br />
[2026-07-29 17:37:43.349][CPU2][LTOS/N][000000072.195]:设置DNS服务器 id 2 index 0 ip 223.5.5.5</span><br />
[2026-07-29 17:37:43.360][CPU2][LTOS/N][000000072.195]:设置DNS服务器 id 2 index 1 ip 114.114.114.114</span><br />
[2026-07-29 17:37:43.371][CPU2][LTOS/N][000000072.196]:I/user.netdrv_multiple_notify_cbfunc use new adapter WiFi 2</span><br />
[2026-07-29 17:37:43.379][CPU2][LTOS/N][000000072.196]:I/user.exnetif publish network status WiFi 2</span><br />
[2026-07-29 17:37:43.390][CPU2][LTOS/N][000000072.196]:dft adapter change from 8 to 2</span><br />
[2026-07-29 17:37:43.400][CPU2][LTOS/N][000000072.197]:I/user.sip IP_LOSE 8</span><br />
[2026-07-29 17:37:43.410][CPU2][LTOS/N][000000072.197]:I/user.sip default network changed from 8 to 2 , trigger reconnect</span><br />
<mark>[2026-07-29 17:37:46.299][CPU1][LTOS/N][000000075.201]:I/user.sip creating socket with adapter: 2 locked_adapter: 2</mark></span><br />
[2026-07-29 17:37:46.305][CPU1][LTOS/N][000000075.202]:connect to 180.152.6.34,8910</span><br />
[2026-07-29 17:37:46.314][CPU2][LTOS/N][000000075.202]:adapter 2 connect 180.152.6.34:8910 UDP</span><br />
[2026-07-29 17:37:46.325][CPU2][LTOS/N][000000075.208]:I/user.sip send REGISTER 180.152.6.34 8910</span><br />
[2026-07-29 17:37:46.334][CPU1][LTOS/N][000000075.210]:I/user.exsip event: lifecycle action: online</span><br />
[2026-07-29 17:37:46.345][CPU1][LTOS/N][000000075.211]:I/user.exsip lifecycle: online</span><br />
[2026-07-29 17:37:46.354][CPU2][LTOS/N][000000075.212]:I/user.sip_callback STATE_READY lifecycle online table: 6094B808 nil</span><br />
[2026-07-29 17:37:46.365][CPU2][LTOS/N][000000075.213]:I/user.sip_callback lifecycle event: online</span><br />
[2026-07-29 17:37:46.374][CPU2][LTOS/N][000000075.213]:I/user.sip_callback SIP 服务已在线，本地IP地址为： 192.168.137.115</span><br />
[2026-07-29 17:37:47.923][CPU1][LTOS/N][000000076.817]:I/user.sip resp 401 Unauthorized from 180.152.6.34 8910</span><br />
[2026-07-29 17:37:47.930][CPU1][LTOS/N][000000076.826]:I/user.sip send REGISTER (auth) cseq 7</span><br />
[2026-07-29 17:37:47.942][CPU1][LTOS/N][000000076.829]:I/user.exsip event: register action: challenge</span><br />
[2026-07-29 17:37:47.951][CPU1][LTOS/N][000000076.830]:I/user.sip_callback STATE_READY register challenge table: 60948278 nil</span><br />
[2026-07-29 17:37:47.962][CPU1][LTOS/N][000000076.830]:I/user.sip_callback 收到认证挑战，继续注册流程</span><br />
[2026-07-29 17:37:49.762][CPU1][LTOS/N][000000078.660]:I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-07-29 17:37:49.768][CPU1][LTOS/N][000000078.664]:I/user.sip next register in 570 sec</span><br />
[2026-07-29 17:37:49.777][CPU1][LTOS/N][000000078.665]:I/user.sip UDP OPTIONS keepalive started, interval 25000 ms</span><br />
[2026-07-29 17:37:49.786][CPU1][LTOS/N][000000078.666]:I/user.exsip event: register action: ok</span><br />
[2026-07-29 17:37:49.798][CPU1][LTOS/N][000000078.666]:I/user.sip_callback STATE_READY register ok table: 60946C90 nil</span><br />
[2026-07-29 17:37:49.806][CPU1][LTOS/N][000000078.667]:I/user.sip_callback 注册成功，有效期: 600 SIP响应头: table: 60947210</span><br />
[2026-07-29 17:37:49.816][CPU1][LTOS/N][000000078.667]:I/user.sip_callback STATE_READY ready nil nil nil</span><br />
<mark>[2026-07-29 17:37:49.827][CPU1][LTOS/N][000000078.667]:I/user.sip_callback SIP 服务已就绪 当前SIP状态: STATE_READY</mark></span><br />
[2026-07-29 17:37:49.834][CPU2][LTOS/N][000000078.672]:I/user.sip req NOTIFY from 180.152.6.34 8910</span><br />
[2026-07-29 17:37:49.846][CPU2][LTOS/N][000000078.677]:I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_READY nil</span><br />
[2026-07-29 17:37:49.855][CPU2][LTOS/N][000000078.677]:I/user.sip_app_main_task_func after process STATE_READY</span><br />
</span><br />
**以太网切4G**</span><br />
[2026-07-29 17:54:24.088][CPU2][LTOS/N][000000067.704]:I/user.8101SPIETH网卡httpdns域名解析成功</span><br />
[2026-07-29 17:54:24.096][CPU2][LTOS/N][000000067.705]:I/user.httpdns baidu.com 110.242.74.102</span><br />
[2026-07-29 17:54:27.080][CPU2][LTOS/N][000000070.706]:I/user.WiFi网卡开始PING</span><br />
[2026-07-29 17:54:27.090][CPU2][LTOS/N][000000070.706]:I/user.dns_request WiFi true</span><br />
[2026-07-29 17:54:27.110][CPU2][LTOS/N][000000070.708]:adapter 2 connect 223.5.5.5:80 TCP</span><br />
[2026-07-29 17:54:28.062][CPU1][LTOS/N][000000071.708]:link is down 1 3 609c8648</span><br />
[2026-07-29 17:54:28.070][CPU2][LTOS/N][000000071.709]:网卡(8)设置为DOWN</span><br />
<mark>[2026-07-29 17:54:28.082][CPU1][LTOS/N][000000071.710]:IP_LOSE 8</span><br />
[2026-07-29 17:54:28.111][CPU1][LTOS/N][000000071.711]:I/user.ip_lose_handle 8101SPIETH</span><br />
[2026-07-29 17:54:28.131][CPU1][LTOS/N][000000071.711]:I/user.8101SPIETH 失效，切换到其他网络</mark></span><br />
[2026-07-29 17:54:28.149][CPU1][LTOS/N][000000071.712]:W/user.netdrv_multiple_notify_cbfunc no available adapter nil -1</span><br />
[2026-07-29 17:54:28.170][CPU1][LTOS/N][000000071.712]:W/user.exnetif publish network status no available adapter -1</span><br />
[2026-07-29 17:54:28.181][CPU1][LTOS/N][000000071.713]:I/user.sip IP_LOSE 8</span><br />
[2026-07-29 17:54:28.194][CPU1][LTOS/N][000000071.713]:I/user.exsip event: error action: network_changed</span><br />
[2026-07-29 17:54:28.203][CPU1][LTOS/N][000000071.713]:E/user.exsip error: network_changed nil nil</span><br />
[2026-07-29 17:54:28.217][CPU1][LTOS/N][000000071.714]:I/user.sip_callback STATE_READY error network_changed table: 60940F80 nil</span><br />
[2026-07-29 17:54:28.230][CPU1][LTOS/N][000000071.714]:E/user.sip_callback 错误: network_changed nil nil</span><br />
[2026-07-29 17:54:28.244][CPU2][LTOS/N][000000071.715]:I/user.exsip IP_LOSE 8</span><br />
[2026-07-29 17:54:28.255][CPU2][LTOS/N][000000071.716]:I/user.sip default network changed from 8 to -1 , trigger reconnect</span><br />
[2026-07-29 17:54:28.275][CPU2][LTOS/N][000000071.717]:I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_ERROR nil</span><br />
[2026-07-29 17:54:28.284][CPU2][LTOS/N][000000071.717]:I/user.stop 开始停止 SIP，当前状态: STATE_READY</span><br />
[2026-07-29 17:54:28.300][CPU2][LTOS/N][000000071.759]:I/user.exsip unsubscribed from IP_READY and IP_LOSE</span><br />
[2026-07-29 17:54:28.360][CPU1][LTOS/N][000000071.762]:I/user.exsip event: lifecycle action: stopped</span><br />
[2026-07-29 17:54:28.368][CPU1][LTOS/N][000000071.762]:I/user.exsip lifecycle: stopped</span><br />
[2026-07-29 17:54:28.388][CPU1][LTOS/N][000000071.764]:I/user.sip_callback STATE_READY lifecycle stopped table: 60951EB8 nil</span><br />
[2026-07-29 17:54:28.398][CPU1][LTOS/N][000000071.764]:I/user.sip_callback lifecycle event: stopped</span><br />
[2026-07-29 17:54:29.159][CPU2][LTOS/N][000000072.776]:I/user.exsip stopped</span><br />
[2026-07-29 17:54:29.165][CPU2][LTOS/N][000000072.777]:I/user.sip_app_key SIP应用已断开</span><br />
[2026-07-29 17:54:30.078][CPU2][LTOS/N][000000073.708]:http close 60a3a7d8</span><br />
<mark>[2026-07-29 17:54:30.086][CPU2][LTOS/N][000000073.710]:I/user.WiFi网卡httpdns域名解析失败，重置为OPENED</span><br />
[2026-07-29 17:54:30.099][CPU2][LTOS/N][000000073.711]:I/user.httpdns baidu.com nil</span><br />
[2026-07-29 17:54:33.082][CPU1][LTOS/N][000000076.712]:I/user.airlink_4G网卡开始PING</span><br />
[2026-07-29 17:54:33.094][CPU1][LTOS/N][000000076.713]:I/user.dns_request airlink_4G true</mark></span><br />
[2026-07-29 17:54:33.104][CPU2][LTOS/N][000000076.715]:adapter 15 connect 223.5.5.5:80 TCP</span><br />
[2026-07-29 17:54:33.236][CPU2][LTOS/N][000000076.857]:http close 60a3a7d8</span><br />
[2026-07-29 17:54:33.242][CPU2][LTOS/N][000000076.860]:I/user.airlink_4G网卡httpdns域名解析成功</span><br />
[2026-07-29 17:54:33.254][CPU2][LTOS/N][000000076.860]:I/user.httpdns baidu.com 110.242.74.102</span><br />
[2026-07-29 17:54:33.263][CPU2][LTOS/N][000000076.860]:I/user.设置网卡 airlink_4G</span><br />
[2026-07-29 17:54:33.273][CPU2][LTOS/N][000000076.861]:设置DNS服务器 id 15 index 0 ip 223.5.5.5</span><br />
[2026-07-29 17:54:33.286][CPU2][LTOS/N][000000076.861]:设置DNS服务器 id 15 index 1 ip 114.114.114.114</span><br />
[2026-07-29 17:54:33.304][CPU2][LTOS/N][000000076.861]:I/user.netdrv_multiple_notify_cbfunc use new adapter airlink_4G 15</span><br />
[2026-07-29 17:54:33.319][CPU2][LTOS/N][000000076.862]:I/user.exnetif publish network status airlink_4G 15</span><br />
[2026-07-29 17:54:33.333][CPU2][LTOS/N][000000076.862]:dft adapter change from 8 to 15</span><br />
[2026-07-29 17:54:34.158][CPU2][LTOS/N][000000077.777]:I/user.sip_app_main_task_func recv IP_READY 15 15</span><br />
[2026-07-29 17:54:34.196][CPU2][LTOS/N][000000077.777]:I/user.start 开始初始化 SIP，当前状态: STATE_INITING</span><br />
[2026-07-29 17:54:34.202][CPU2][LTOS/N][000000077.777]:I/user.exsip exsip.init called, config type: table config: table: 6098DC00</span><br />
[2026-07-29 17:54:34.212][CPU2][LTOS/N][000000077.778]:I/user.exsip init completed: 1903CFC0@180.152.6.34</span><br />
[2026-07-29 17:54:34.223][CPU2][LTOS/N][000000077.779]:I/user.exsip subscribed to IP_READY and IP_LOSE</span><br />
[2026-07-29 17:54:34.272][CPU2][LTOS/N][000000077.779]:I/user.exsip current adapter set: 15</span><br />
[2026-07-29 17:54:34.280][CPU2][LTOS/N][000000077.782]:I/user.sip SIP task uses locked adapter: nil transport: udp</span><br />
[2026-07-29 17:54:34.289][CPU2][LTOS/N][000000077.783]:I/user.sip locked_adapter initialized to default: 15</span><br />
[2026-07-29 17:54:34.302][CPU2][LTOS/N][000000077.784]:I/user.sip creating socket with adapter: 15 locked_adapter: 15</span><br />
[2026-07-29 17:54:34.312][CPU2][LTOS/N][000000077.784]:connect to 180.152.6.34,8910</span><br />
[2026-07-29 17:54:34.321][CPU2][LTOS/N][000000077.785]:adapter 15 connect 180.152.6.34:8910 UDP</span><br />
[2026-07-29 17:54:34.333][CPU1][LTOS/N][000000077.786]:I/user.exsip started adapter nil</span><br />
[2026-07-29 17:54:34.343][CPU2][LTOS/N][000000077.792]:I/user.sip send REGISTER 180.152.6.34 8910</span><br />
[2026-07-29 17:54:34.353][CPU2][LTOS/N][000000077.794]:I/user.exsip event: lifecycle action: online</span><br />
[2026-07-29 17:54:34.367][CPU2][LTOS/N][000000077.794]:I/user.exsip lifecycle: online</span><br />
[2026-07-29 17:54:34.379][CPU2][LTOS/N][000000077.795]:I/user.sip_callback STATE_INITING lifecycle online table: 6096A1A0 nil</span><br />
[2026-07-29 17:54:34.387][CPU2][LTOS/N][000000077.795]:I/user.sip_callback lifecycle event: online</span><br />
[2026-07-29 17:54:34.401][CPU2][LTOS/N][000000077.795]:I/user.sip_callback SIP 服务已在线，本地IP地址为： 192.168.111.1</span><br />
[2026-07-29 17:54:34.735][CPU1][LTOS/N][000000078.361]:I/user.sip resp 401 Unauthorized from 180.152.6.34 8910</span><br />
[2026-07-29 17:54:34.742][CPU2][LTOS/N][000000078.370]:I/user.sip send REGISTER (auth) cseq 3</span><br />
[2026-07-29 17:54:34.754][CPU2][LTOS/N][000000078.373]:I/user.exsip event: register action: challenge</span><br />
[2026-07-29 17:54:34.767][CPU2][LTOS/N][000000078.373]:I/user.sip_callback STATE_INITING register challenge table: 6095C178 nil</span><br />
[2026-07-29 17:54:34.775][CPU2][LTOS/N][000000078.373]:I/user.sip_callback 收到认证挑战，继续注册流程</span><br />
[2026-07-29 17:54:36.486][CPU1][LTOS/N][000000080.122]:I/user.sip req NOTIFY from 180.152.6.34 8910</span><br />
[2026-07-29 17:54:36.500][CPU2][LTOS/N][000000080.128]:I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-07-29 17:54:36.507][CPU2][LTOS/N][000000080.131]:I/user.sip next register in 570 sec</span><br />
[2026-07-29 17:54:36.521][CPU2][LTOS/N][000000080.132]:I/user.sip UDP OPTIONS keepalive started, interval 25000 ms</span><br />
[2026-07-29 17:54:36.530][CPU2][LTOS/N][000000080.132]:I/user.exsip event: register action: ok</span><br />
[2026-07-29 17:54:36.539][CPU2][LTOS/N][000000080.133]:I/user.sip_callback STATE_INITING register ok table: 6094CBC8 nil</span><br />
[2026-07-29 17:54:36.552][CPU2][LTOS/N][000000080.133]:I/user.sip_callback 注册成功，有效期: 600 SIP响应头: table: 6094E0D8</span><br />
[2026-07-29 17:54:36.562][CPU2][LTOS/N][000000080.133]:I/user.sip_callback STATE_INITING ready nil nil nil</span><br />
<mark>[2026-07-29 17:54:36.573][CPU2][LTOS/N][000000080.133]:I/user.sip_callback SIP 服务已就绪 当前SIP状态: STATE_INITING</mark></span><br />


## 七、常见问题

### 7.1 WiFi 无法联网

- 确认热点为 2.4 GHz；
- 检查 `ssid` 和 `password`，注意大小写及特殊字符；
- 确认路由器允许设备访问 SIP 服务器及 RTP 端口；
- 若处于专网或海外网络，请按网络环境调整 `netdrv_wifi.lua` 中的 DNS 设置。

### 7.2 SIP 无法注册

- 检查服务器地址、端口、域名、账号、密码和传输协议；
- 确认模块与客户端没有使用同一个账号；
- `401 Unauthorized` 可能是正常的认证挑战；其后收到 `200 OK` 才表示注册成功；
- 检查服务器、路由器防火墙及 NAT 配置。

### 7.3 能接通但没有声音

- 检查 MIC、SPK、PA_EN、VCC、GND 连接和板卡方向；
- 确认使用 Air8101B，而不是不支持完整录音能力的 Air8101；
- 确认 AirAUDIO_1000 的 PA 开关位置与软件控制方式一致；
- 检查 RTP 端口是否被防火墙或 NAT 阻断。

### 7.4 声音太小、破音或底噪明显

在 `audio_drv.lua` 中逐级微调增益。模拟增益优先小步调整，数字增益和喇叭音量过高都可能导致削波、破音或底噪放大。

### 7.5 以太网无法获得 IP

- 确认代码已改为 `ETHUSER1`、GPIO13、SPI0、GPIO15 和 GPIO8；
- 检查 AirETH_1000 供电、SPI 线序、排针方向和网线；
- 确认路由器 LAN 口及 DHCP 服务正常。

### 7.6 外挂 4G 无法联网

- 确认 Air780EPM 已插入可用 SIM 卡、连接天线并成功驻网；
- 确认 Air8101B 与 Air780EPM 两端均已烧录对应程序；
- 检查 SPI0 AirLink 接线和两端主从模式；
- 确认 Air780EPM 端已创建桥接网卡并开启 NAPT、DNS 代理；
- Air8101B 端应使用 `airlink_4G`，不能将本机不存在的原生 `LWIP_GP` 当作 4G 网卡。

## 八、总结

本 Demo 覆盖 Air8101B 的 WiFi 单网卡、AirETH_1000 以太网单网卡、外挂 Air780EPM 的 4G 单网卡和多网融合场景，并演示 SIP 注册、客户端呼入、延时自动接听、双向语音和挂断恢复流程。补充各场景的实测图片和关键日志后，即可形成完整的复现实验记录。
