# **SIP DEMO 项目说明**

## **一、项目概述**

SIP DEMO 项目是一个基于 Air8000 开发板的 SIP 通话演示项目，通过 Air8000 开发板实现 SIP 通话功能，支持 4G、WIFI、以太网三种网络方式以及多网融合情况下的 SIP 通话。

### **文件结构**

```lua
sip/
├── main.lua：主程序入口，加载网络驱动模块、SIP通话模块和按键处理
├── sip_app/
│   ├── sip_app_main.lua：sip主入口;
│   ├── sip_app_key.lua：按键相关处理;
├── netdrv/
│   ├── netdrv_4g.lua：4g网络模块
│   ├── netdrv_eth_spi.lua：“通过SPI外挂CH390H芯片的以太网卡”驱动模块
│   ├── netdrv_multiple.lua：多网卡（4G网卡、WIFI STA网卡、通过SPI外挂CH390H芯片的以太网卡）驱动模块
│   └── netdrv_wifi.lua：wifi网络模块
├── netdrv_device.lua：网络设备驱动模块，根据选择的网络类型加载对应的网络驱动
├── audio_drv.lua: 管理音频设备初始化与控制
├── tts_speaker.lua：语音播报
```

## **二、演示功能概述**

1. 单网卡测试 sip 功能：4g 联网测试 sip 功能、wifi 联网测试 sip 功能、以太网联网测试 sip 功能；
2. 多网卡测试 sip 功能：4g 联网 + wifi 联网 + 以太网联网测试 sip 功能

本文使用 Air8000 开发板，分别演示 4g 联网测试、wifi 联网测试、以太网联网测试和多网卡组合测试 sip 功能。

### **场景一：4g 单网卡联网测试**

1. **网络设备驱动模块**：根据选择的网络类型在 **netdrv_device.lua** 文件中加载对应的网络驱动，这里选择 4g 驱动（require "netdrv_4g"）。
2. **音频设备初始化与控制**：使用 exaudio.setup 统一配置 ES8311 音频编解码芯片和扬声器功放，包括 I2C、I2S 接口设置及音量控制。
3. **拨号/接听**：在无来电的情况下，单击 boot 键进行拨号；收到来电，单击 boot 键进行接听
4. **挂断**：来电/拨号/通话过程中，单击 PWRKEY 键进行挂断

### **场景二：WIFI 单网卡联网测试**

1. **网络设备驱动模块**：根据选择的网络类型在 **netdrv_device.lua** 文件中加载对应的网络驱动，这里选择以太网驱动（require "netdrv_wifi"）。
2. **音频设备初始化与控制**：使用 exaudio.setup 统一配置 ES8311 音频编解码芯片和扬声器功放，包括 I2C、I2S 接口设置及音量控制。
3. **拨号/接听**：在无来电的情况下，单击 boot 键进行拨号；收到来电，单击 boot 键进行接听
4. **挂断**：来电/拨号/通话过程中，单击 PWRKEY 键进行挂断

### **场景三：以太网单网卡联网测试**

1. **网络设备驱动模块**：根据选择的网络类型在 **netdrv_device.lua** 文件中加载对应的网络驱动，这里选择以太网驱动（require "netdrv_eth_spi"）。
2. **音频设备初始化与控制**：使用 exaudio.setup 统一配置 ES8311 音频编解码芯片和扬声器功放，包括 I2C、I2S 接口设置及音量控制。
3. **拨号/接听**：在无来电的情况下，单击 boot 键进行拨号；收到来电，单击 boot 键进行接听
4. **挂断**：来电/拨号/通话过程中，单击 PWRKEY 键进行挂断

### **场景四：多网卡联网组合通话测试**

1. **网络设备驱动模块**：根据选择的网络类型加载对应的网络驱动，这里选择多网融合驱动（require "netdrv_multiple"）。
2. **音频设备初始化与控制**：使用 exaudio.setup 统一配置 ES8311 音频编解码芯片和扬声器功放，包括 I2C、I2S 接口设置及音量控制。
3. **拨号/接听**：在无来电的情况下，单击 boot 键进行拨号；收到来电，单击 boot 键进行接听
4. **通话保持**：当前配置的网络优先级是：以太网 >wifi>4g；先断开 wifi 和以太网，用 4g 联网注册 SIP，在通话过程中开启 wifi 或者连接以太网，通话能够继续保持，通话结束后，下次重新发起 SIP 通话时，会使用当时优先级最高并且网络状态就绪的网卡重新注册。
5. **挂断**：来电/拨号/通话过程中，单击 PWRKEY 键进行挂断

## **三、准备硬件环境**

参考：[硬件环境清单第二章节内容](https://docs.openluat.com/air8000/luatos/common/hwenv/)，准备以及组装好硬件环境。

1. Air8000 开发板一块 +SIM 卡一张 +4g 天线一根 +WIFI 天线一根 + 网线一根，所有硬件环境组装好，实际测试根据需要进行，具体可以参考”演示核心步骤“中的对应操作。
2. TYPE-C USB 数据线一根，Air8000 开发板和数据线的硬件接线方式为：

- Air8000 开发板通过 TYPE-C USB 口供电；
- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

![](https://docs.openluat.com/air8000/luatos/app/multimedia/sip/image/sip_img1.jpg)

## **四、准备软件环境**

### **4.1 工具 + 内核固件 + 脚本**

1. 烧录工具 [Luatools](https://luatos.com/luatools/download/last)；
2. Air8000A V2034 及以上 版本固件，除 11/12/14 和 111/112/114 固件以外，其他均可，如果需要 TTS 播放，则只能选 1/3/5/7/13/16[Air8000A 固件](https://docs.openluat.com/air8000/luatos/firmware/)本 demo 开发测试时使用的固件为 [Air8000A V2034 版本固件](https://cdn18.air32.cn:19443/files/Air8000/LuatOS_Air8000/LuatOS-SoC_V2034_Air8000/) ，如果发现最新版本的内核固件测试有问题，可以使用我们开发本 demo 时使用的内核固件版本来对比测试；
3. luatos 需要的脚本和资源文件

- 脚本和资源文件[点我浏览所有文件](https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/sip)
- 准备好软件环境之后，接下来查看[如何使用 LuaTools 烧录软件](https://docs.openluat.com/air780epm/luatos/common/download/)，将本篇文章中演示使用的项目文件烧录到 Air8000A 开发板中，或者查看 [Air8000A 整机开发板使用说明_V1.0.3](https://docs.openluat.com/air8000/product/file/Air8000_V2.0%E5%BC%80%E5%8F%91%E6%9D%BF%E4%BD%BF%E7%94%A8%E8%AF%B4%E6%98%8E_V1.0.3.pdf) ，将本篇文章中演示使用的项目文件烧录到 Air8000A 开发板中。
- lib 脚本文件：使用 Luatools 烧录时，勾选 添加默认 lib 选项，使用默认 lib 脚本文件，如果测试有问题，尝试手动添加 libs（..\LuatOS\script\libs）;

### **4.2 API 介绍**

这里仅介绍本篇文档所使用的 API，详情请查看：[API - exsip](https://docs.openluat.com/osapi/ext/exsip/)

### **4.3MicroSIP/LinPhone 测试 sip 通话功能**

```lua
服务器地址：180.152.6.34
端口号：8910
域名：180.152.6.34
用户名：100001
密码：Mm123..
SIP传输方式：TCP/UDP
```

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

## **五、代码演示**

程序架构

```lua
sip/
├── main.lua：主程序入口，加载网络驱动模块、SIP通话模块和按键处理
├── sip_app/
│   ├── sip_app_main.lua：sip主入口;
│   ├── sip_app_key.lua：按键相关处理;
├── netdrv/
│   ├── netdrv_4g.lua：4g网络模块
│   ├── netdrv_eth_spi.lua：“通过SPI外挂CH390H芯片的以太网卡”驱动模块
│   ├── netdrv_multiple.lua：多网卡（4G网卡、WIFI STA网卡、通过SPI外挂CH390H芯片的以太网卡）驱动模块
│   └── netdrv_wifi.lua：wifi网络模块
├── netdrv_device.lua：网络设备驱动模块，根据选择的网络类型加载对应的网络驱动
├── audio_drv.lua: 管理音频设备初始化与控制
├── tts_speaker.lua：语音播报
```

当前我们有测试账号 100000 和 100001，如果您有自己的 SIP 服务器，那么只需要更改 sip_app_main.lua 文件中 SIP_CONFIG 相关参数和 sip_app_key.lua 的目标号码

```sql
local SIP_CONFIG = 
{
    sip_server_addr = "180.152.6.34",
    sip_server_port = 8910,
    sip_domain = "180.152.6.34",
    sip_username = "100000",
    sip_password = "Mm123.",
    _-- sip_username = "100001",_
    _-- sip_password = "Mm123..",_
    sip_transport = exsip.TRANSPORT_UDP,
    auto_answer = false,
}
```

```sql
local function **boot_key_handler**()
    log.**info**(g_tag, "按下BOOT键")
    ...
    
    sys.**publish**("SIP_APP_MAIN_DIAL_REQ", g_tag, "100001")
end
```

## **六、功能演示**

1、搭建好硬件环境

2、在 **netdrv_device.lua** 中选择要测试的网卡场景:

- 场景一：4g 联网测试：require "netdrv_4g"
- 场景二：WIFI 联网测试：require "netdrv_wifi"
- 场景三：以太网联网测试：require "netdrv_eth_spi"
- 场景四：多网卡联网测试：require "netdrv_multiple"

3、在 sip_app_main.lua 中的 SIP_CONFIG 配置 SIP 服务器地址，端口，域名，用户名，密码，注意：服务器地址、端口、用户名和密码按实际填，在 sip_app_key.lua 中的 boo 按键函数发布的消息中填写要拨打的号码：sys.publish("SIP_APP_MAIN_DIAL_REQ", g_tag, targetnumber)，本例中 targetnumber = "100001"；

4、打开 MicroSIP/Linphone，输入 sip_app_main.lua 中 SIP_CONFIG 配置的 sip 服务器地址，端口，域名，注意：用户名和密码按实际填，不要与脚本中的用户名重复，本例中 MicroSIP/Linphone 填写的用户名为 100001；

5、烧录内核固件和 sip 相关 demo 成功后，自动开机运行；

6、运行程序，观察日志输出了解系统状态

### **场景一：4g 单网卡联网测试**

#### SIP 和音频初始化：

参数含义：触发回调的事件</span><br />
[2026-05-18 17:53:19.686][000000014.842] D/mobile NETIF_LINK_ON -> IP_READY</span><br />
[2026-05-18 17:53:19.692][000000014.843] I/user.netdrv_4g.ip_ready_func IP_READY 10.16.253.118 255.255.255.255 0.0.0.0 nil</span><br />
[2026-05-18 17:53:19.698][000000014.844] I/user.sip_app_main_task_func recv IP_READY 1 3</span><br />
<mark>[2026-05-18 17:53:19.704][000000014.845] I/user.start 开始初始化 SIP，当前状态: STATE_INITING</span><br />
[2026-05-18 17:53:19.710][000000014.846] I/user.exaudio.setup 使用ES8311 I2S模式初始化</mark></span><br />
[2026-05-18 17:53:19.717][000000014.846] I2C_MasterSetup 426:I2C0, Total 65 HCNT 22 LCNT 40</span><br />
[2026-05-18 17:53:19.727][000000014.923] D/audio codec init es8311 </span><br />
[2026-05-18 17:53:20.272][000000015.480] I/user.exaudio.setup 声道数已设置为:1(1=单声道,2=双声道)</span><br />
[2026-05-18 17:53:20.275][000000015.480] I/user.audio_drv exaudio.setup初始化成功</span><br />
[2026-05-18 17:53:20.458][000000015.663] I/user.audio_drv 已设置通话音量为: 40</span><br />
[2026-05-18 17:53:20.647][000000015.849] I/user.audio_drv 已设置麦克风音量为: 98</span><br />

#### 4g 联网注册 SIP，日志如下：

[2026-05-18 17:53:20.655][000000015.851] I/user.exsip init completed: 100000@180.152.6.34</span><br />
[2026-05-18 17:53:20.708][000000015.910] I/user.exsip subscribed to IP_READY and IP_LOSE</span><br />
[2026-05-18 17:53:20.710][000000015.911] I/user.exsip current adapter set: 1</span><br />
[2026-05-18 17:53:20.751][000000015.917] I/user.sip SIP task uses locked adapter: nil transport: udp</span><br />
[2026-05-18 17:53:20.756][000000015.918] I/user.sip locked_adapter initialized to default: 1</span><br />
[2026-05-18 17:53:20.762][000000015.919] I/user.sip creating socket with adapter: 1 locked_adapter: 1</span><br />
[2026-05-18 17:53:20.766][000000015.920] D/socket connect to 180.152.6.34,8910</span><br />
[2026-05-18 17:53:20.771][000000015.921] I/user.exsip started adapter nil</span><br />
[2026-05-18 17:53:20.779][000000015.922] I/user.dnsproxy 开始监听</span><br />
[2026-05-18 17:53:20.781][000000015.922] D/mobile TIME_SYNC 0 tm 1779098000</span><br />
[2026-05-18 17:53:20.787][000000015.926] I/user.sip send REGISTER 180.152.6.34 8910</span><br />
[2026-05-18 17:53:20.797][000000015.928] I/user.exsip event: lifecycle action: online</span><br />
[2026-05-18 17:53:20.802][000000015.929] I/user.exsip lifecycle: online</span><br />
[2026-05-18 17:53:20.806][000000015.929] I/user.sip_callback STATE_INITING lifecycle online table: 0C7CD028 nil</span><br />
[2026-05-18 17:53:20.812][000000015.930] I/user.sip_callback lifecycle event: online</span><br />
[2026-05-18 17:53:20.818][000000015.930] I/user.sip_callback SIP 服务已在线，本地IP地址为： 10.16.253.118</span><br />
[2026-05-18 17:53:20.832][000000016.028] I/user.sip resp 401 Unauthorized from 180.152.6.34 8910</span><br />
[2026-05-18 17:53:20.834][000000016.037] I/user.sip send REGISTER (auth) cseq 2</span><br />
[2026-05-18 17:53:20.843][000000016.039] I/user.exsip event: register action: challenge</span><br />
[2026-05-18 17:53:20.849][000000016.040] I/user.sip_callback STATE_INITING register challenge table: 0C7C8CF0 nil</span><br />
[2026-05-18 17:53:20.854][000000016.040] I/user.sip_callback 收到认证挑战，继续注册流程</span><br />
[2026-05-18 17:53:20.910][000000016.113] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-18 17:53:20.912][000000016.116] I/user.sip next register in 570 sec</span><br />
[2026-05-18 17:53:20.916][000000016.117] I/user.sip UDP OPTIONS keepalive started, interval 25000 ms</span><br />
[2026-05-18 17:53:20.928][000000016.118] I/user.exsip event: register action: ok</span><br />
[2026-05-18 17:53:20.933][000000016.119] I/user.sip_callback STATE_INITING register ok table: 0C7C72B8 nil</span><br />
[2026-05-18 17:53:20.937][000000016.119] I/user.sip_callback 注册成功，有效期: 600 SIP响应头: table: 0C7C7C98</span><br />
<mark>[2026-05-18 17:53:20.947][000000016.120] I/user.sip_callback STATE_INITING ready nil nil nil</span><br />
[2026-05-18 17:53:20.952][000000016.120] I/user.sip_callback SIP 服务已就绪 当前SIP状态: STATE_INITING</mark></span><br />
[2026-05-18 17:53:20.958][000000016.121] I/user.sip_app_main_task_func waitMsg STATE_INITING sip_callback MSG_READY nil</span><br />


#### 拨号测试

##### 单击 boot 键拨号

日志如下：


[2026-05-18 17:59:09.708][000000364.908] I/user.sip_app_key 按下BOOT键</span><br />
[2026-05-18 17:59:09.709][000000364.909] I/user.sip_app_main_task_func waitMsg STATE_READY sip_app_key MSG_DIAL 100001</span><br />
[2026-05-18 17:59:09.710][000000364.909] I/user.exsip calling: 100001</span><br />
[2026-05-18 17:59:09.818][000000365.014] I/user.sip_app_main_task_func after process STATE_DIALING</span><br />
[2026-05-18 17:59:09.819][000000365.015] I/user.sip cmd call 100001</span><br />
[2026-05-18 17:59:09.819][000000365.017] I/user.test ip 10.16.253.118</span><br />
[2026-05-18 17:59:09.819][000000365.018] I/user.sip setting call timeout 30 seconds</span><br />
[2026-05-18 17:59:09.820][000000365.021] I/user.sip send INVITE sip:100001@180.152.6.34</span><br />
[2026-05-18 17:59:09.990][000000365.187] I/user.sip resp 407 Proxy Authentication Required from 180.152.6.34 8910</span><br />
[2026-05-18 17:59:10.006][000000365.199] I/user.exsip event: call action: auth_retry</span><br />
[2026-05-18 17:59:10.084][000000365.289] I/user.sip resp 100 Trying from 180.152.6.34 8910</span><br />
[2026-05-18 17:59:10.114][000000365.316] I/user.sip resp 180 Ringing from 180.152.6.34 8910</span><br />
[2026-05-18 17:59:10.114][000000365.319] I/user.sip invite provisional response 180 Ringing</span><br />
[2026-05-18 17:59:10.115][000000365.320] I/user.exsip event: call action: ringing</span><br />
[2026-05-18 17:59:10.130][000000365.321] I/user.sip_callback STATE_DIALING call ringing table: 0C79F470 nil</span><br />
<mark>[2026-05-18 17:59:10.131][000000365.321] I/user.sip_callback call event sub_event= ringing</span><br />
[2026-05-18 17:59:10.131][000000365.321] I/user.sip_callback 对方响铃中</mark></span><br />
[2026-05-18 17:59:11.004][000000366.209] I/user.sip send OPTIONS ping</span><br />
[2026-05-18 17:59:11.127][000000366.321] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />


##### 对方接听，通话建立

[2026-05-18 17:59:18.394][000000373.600] I/user.sip resp 200 OK from 180.152.6.34 8910
[2026-05-18 17:59:18.410][000000373.603] I/user.sip parsing remote SDP v=0
o=FreeSWITCH 1779082298 1779082299 IN IP4 180.152.6.34
s=FreeSWITCH
c=IN IP4 180.152.6.34
t=0 0
m=audio 16060 RTP/AVP 0 101
a=rtpmap:0 PCMU/8000
a=rtpmap:101 telephone-event/8000
a=fmtp:101 0-15
a=ptime:20

[2026-05-18 17:59:18.413][000000373.606] I/user.sip stopping all call timers, clearing timeout_timer</span><br />
[2026-05-18 17:59:18.427][000000373.611] I/user.exsip event: media action: ready</span><br />
[2026-05-18 17:59:18.432][000000373.612] I/user.exsip media ready 180.152.6.34 16060 PCMU</span><br />
[2026-05-18 17:59:18.437][000000373.613] I/user.exsip start voip engine with adapter: 1 remote: 180.152.6.34:16060</span><br />
[2026-05-18 17:59:18.444][000000373.614] I/user.exsip voip engine started 180.152.6.34:16060 codec=PCMU adapter nil</span><br />
[2026-05-18 17:59:18.448][000000373.614] I/user.sip_callback STATE_DIALING media ready table: 0C79A6C0 nil</span><br />
[2026-05-18 17:59:18.459][000000373.615] I/user.sip_callback 媒体通道就绪 180.152.6.34:16060</span><br />
[2026-05-18 17:59:18.468][000000373.615] I/user.sip call established (outgoing)</span><br />
[2026-05-18 17:59:18.480][000000373.616] I/user.exsip event: call action: established</span><br />
[2026-05-18 17:59:18.485][000000373.616] I/user.sip_callback STATE_DIALING call connected table: 0C799FB0 nil</span><br />
<mark>[2026-05-18 17:59:18.496][000000373.617] I/user.sip_callback call event sub_event= connected</span><br />
[2026-05-18 17:59:18.501][000000373.617] I/user.sip_callback 通话已建立</mark></span><br />
[2026-05-18 17:59:18.513][000000373.619] I/user.sip_app_main_task_func waitMsg STATE_DIALING sip_callback MSG_CONNECTED nil</span><br />
[2026-05-18 17:59:18.523][000000373.619] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-18 17:59:18.528][000000373.620] I/user.sip_app_key 通话建立成功</span><br />
[2026-05-18 17:59:18.533][000000373.621] D/voip voip task started</span><br />
[2026-05-18 17:59:18.541][000000373.621] D/voip voip start event</span><br />
[2026-05-18 17:59:18.546][000000373.622] E/voip voip config: remote=180.152.6.34:16060 codec=0 ptime=20</span><br />
[2026-05-18 17:59:18.553][000000373.622] E/voip voio origin: samples=8000</span><br />
[2026-05-18 17:59:18.558][000000373.622] E/voip voio frame: samples=160 bytes=320</span><br />
[2026-05-18 17:59:18.562][000000373.629] I/voip aec ready frame=160 tail_ms=200 denoise=1</span><br />
[2026-05-18 17:59:18.571][000000373.641] E/voip udp socket created and connected to 180.152.6.34:16060</span><br />
[2026-05-18 17:59:18.575][000000373.641] luat_i2s_save_old_config 279:i2s1 save old param</span><br />
[2026-05-18 17:59:18.579][000000373.658] E/voip audio started: multimedia_id=0 sample_rate=8000 backend=1</span><br />
[2026-05-18 17:59:18.585][000000373.659] I/user.exsip voip state: started</span><br />
<mark>[2026-05-18 17:59:18.589][000000373.660] I/user.sip_callback STATE_CONNECTED voip state started nil</span><br />
[2026-05-18 17:59:18.600][000000373.660] I/user.sip_callback VoIP状态: started</span><br /></mark>
[2026-05-18 17:59:18.611][000000373.661] I/voip voip running: 180.152.6.34:16060 codec=0 ptime=20</span><br />
<mark>[2026-05-18 17:59:23.465][000000378.659] I/user.sip_callback STATE_CONNECTED voip stats table: 0C799D38 nil</span><br />
[2026-05-18 17:59:23.472][000000378.660] I/user.sip_callback VoIP统计 - 发送: 250 接收: 237 丢失: 0</mark></span><br />

##### 单击 PWRKEY 键，挂断通话

通话结束，结束原因为： local_hangup(我方主动挂断)，日志如下：

[2026-05-18 17:59:25.198][000000380.401] I/user.sip_app_key 按下POWERKEY键</span><br />
[2026-05-18 17:59:25.200][000000380.403] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_app_key MSG_HANGUP nil</span><br />
[2026-05-18 17:59:25.205][000000380.404] I/user.exsip hanging up</span><br />
[2026-05-18 17:59:25.210][000000380.404] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-18 17:59:25.215][000000380.405] I/user.sip cmd hangup </span><br />
[2026-05-18 17:59:25.220][000000380.406] I/user.sip BYE uri sip:100001@180.152.6.34:8910;transport=udp from <sip:100000@180.152.6.34>;tag=4c76f661cb70b652 to <sip:100001@180.152.6.34>;tag=y9KBKpFZKr56K routes 0</span><br />
[2026-05-18 17:59:25.225][000000380.409] I/user.sip send BYE</span><br />
[2026-05-18 17:59:25.293][000000380.486] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-18 17:59:25.309][000000380.489] I/user.exsip event: media action: stop</span><br />
[2026-05-18 17:59:25.316][000000380.489] I/user.exsip voip engine stopping</span><br />
<mark>[2026-05-18 17:59:25.321][000000380.490] I/user.sip_callback STATE_CONNECTED media stop table: 0C798400 nil</span><br />
[2026-05-18 17:59:25.336][000000380.490] I/user.sip_callback 媒体通道已关闭，关闭原因： local_hangup</span><br /></mark>
[2026-05-18 17:59:25.344][000000380.491] I/user.sip call cleared</span><br />
[2026-05-18 17:59:25.353][000000380.492] I/user.exsip event: call action: ended</span><br />
[2026-05-18 17:59:25.358][000000380.492] I/user.exsip voip engine stopping</span><br />
[2026-05-18 17:59:25.363][000000380.493] I/user.sip_callback STATE_CONNECTED call ended table: 0C798358 nil</span><br />
<mark>[2026-05-18 17:59:25.373][000000380.493] I/user.sip_callback call event sub_event= ended</span><br />
[2026-05-18 17:59:25.386][000000380.494] I/user.sip_callback 通话已结束，结束原因为： local_hangup 通话对象： table: 0C7A64F0</span><br /></mark>
[2026-05-18 17:59:25.395][000000380.495] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_callback MSG_DISCONNECTED local_hangup</span><br />
[2026-05-18 17:59:25.409][000000380.495] I/user.sip_app_main_task_func after process STATE_READY</span><br />
[2026-05-18 17:59:25.416][000000380.496] I/user.sip_app_key 通话已断开</span><br />
[2026-05-18 17:59:25.422][000000380.503] D/voip voip stop event</span><br />
[2026-05-18 17:59:25.424][000000380.504] luat_i2s_load_old_config 297:i2s0 load old param</span><br />
<mark>[2026-05-18 17:59:25.428][000000380.506] I/user.exsip voip state: stopped</span><br />
[2026-05-18 17:59:25.433][000000380.508] I/user.sip_callback STATE_READY voip state stopped nil</span><br />
[2026-05-18 17:59:25.442][000000380.508] I/user.sip_callback VoIP状态: stopped</span><br /></mark>
[2026-05-18 17:59:25.456][000000380.509] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_PLAY_HUNGUP local_hangup</span><br />
[2026-05-18 17:59:25.470][000000380.510] I/user.sip_app_main_task_func after process STATE_READY</span><br />

#### 来电接听测试

##### 收到来电

[2026-05-19 11:39:42.120][000000051.648] I/user.sip req INVITE from 180.152.6.34 8910</span><br />
[2026-05-19 11:39:42.122][000000051.650] I/user.sip parsing remote SDP v=0</span><br />
o=FreeSWITCH 1779145202 1779145203 IN IP4 180.152.6.34</span><br />
s=FreeSWITCH</span><br />
c=IN IP4 180.152.6.34</span><br />
t=0 0</span><br />
m=audio 16780 RTP/AVP 8 0 101</span><br />
a=rtpmap:8 PCMA/8000</span><br />
a=rtpmap:0 PCMU/8000</span><br />
a=rtpmap:101 telephone-event/8000</span><br />
a=fmtp:101 0-15</span><br />
a=ptime:20</span><br />

[2026-05-19 11:39:42.134][000000051.659] I/user.exsip event: call action: incoming</span><br />
[2026-05-19 11:39:42.140][000000051.660] I/user.sip_callback STATE_READY call incoming table: 0C7BE0F0 nil</span><br />
<mark>[2026-05-19 11:39:42.145][000000051.660] I/user.sip_callback call event sub_event= incoming</span><br />
[2026-05-19 11:39:42.153][000000051.660] I/user.sip_callback 来电: "Extension 100001" <sip:100001@180.152.6.34>;tag=BQZ8cmgc36Q7r sip:100000@10.18.113.64:5062;received=36.7.99.190:5062 <sip:100000@10.18.113.64:5062;received=36.7.99.190:5062>;tag=1a4d4e84c8751186</span><br /></mark>
[2026-05-19 11:39:42.169][000000051.662] I/user.exsip event: call action: ringing</span><br />
[2026-05-19 11:39:42.174][000000051.662] I/user.sip_callback STATE_READY call ringing table: 0C7BDDA8 nil</span><br />
<mark>[2026-05-19 11:39:42.179][000000051.663] I/user.sip_callback call event sub_event= ringing</span><br />
[2026-05-19 11:39:42.187][000000051.663] I/user.sip_callback 对方响铃中</span><br /></mark>
[2026-05-19 11:39:42.205][000000051.664] I/user.exsip event: media action: offer</span><br />
[2026-05-19 11:39:42.212][000000051.665] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_INCOMING "Extension 100001" <sip:100001@180.152.6.34>;tag=BQZ8cmgc36Q7r</span><br />
[2026-05-19 11:39:42.243][000000051.771] I/user.sip_app_main_task_func after process STATE_INCOMING</span><br />
[2026-05-19 11:39:42.243][000000051.877] I/user.sip_app_key 呼入中，来电号码： 100001</span><br />

##### 单击 boot 键接听来电

<mark>[2026-05-19 11:39:51.669][000000061.206] I/user.sip_app_key 按下BOOT键</span><br />
[2026-05-19 11:39:51.671][000000061.206] I/user.sip_app_key 呼入中，接听</span><br /></mark>
[2026-05-19 11:39:51.677][000000061.207] I/user.sip_app_main_task_func waitMsg STATE_INCOMING sip_app_key MSG_ACCEPT nil</span><br />
[2026-05-19 11:39:51.682][000000061.208] I/user.exsip answering call</span><br />
[2026-05-19 11:39:51.689][000000061.208] I/user.sip_app_main_task_func after process STATE_INCOMING</span><br />
[2026-05-19 11:39:51.695][000000061.209] I/user.sip cmd answer </span><br />
[2026-05-19 11:39:51.701][000000061.210] I/user.test ip 10.18.113.64</span><br />
[2026-05-19 11:39:51.706][000000061.213] I/user.sip answer 200 OK</span><br />
[2026-05-19 11:39:51.840][000000061.366] I/user.sip req ACK from 180.152.6.34 8910</span><br />
[2026-05-19 11:39:51.854][000000061.369] I/user.exsip event: media action: ready</span><br />
[2026-05-19 11:39:51.861][000000061.369] I/user.exsip media ready 180.152.6.34 16780 PCMU</span><br />
[2026-05-19 11:39:51.867][000000061.370] I/user.exsip start voip engine with adapter: 1 remote: 180.152.6.34:16780</span><br />
[2026-05-19 11:39:51.873][000000061.371] I/user.exsip voip engine started 180.152.6.34:16780 codec=PCMU adapter nil</span><br />
<mark>[2026-05-19 11:39:51.881][000000061.371] I/user.sip_callback STATE_INCOMING media ready table: 0C7BB4C0 nil</span><br />
[2026-05-19 11:39:51.891][000000061.372] I/user.sip_callback 媒体通道就绪 180.152.6.34:16780</span><br /></mark>
[2026-05-19 11:39:51.904][000000061.372] I/user.sip call established (incoming)</span><br />
[2026-05-19 11:39:51.916][000000061.373] I/user.exsip event: call action: established</span><br />
[2026-05-19 11:39:51.922][000000061.374] I/user.sip_callback STATE_INCOMING call connected table: 0C7BAC50 nil</span><br />
<mark>[2026-05-19 11:39:51.930][000000061.374] I/user.sip_callback call event sub_event= connected</span><br />
[2026-05-19 11:39:51.943][000000061.375] I/user.sip_callback 通话已建立</span><br /></mark>
[2026-05-19 11:39:51.957][000000061.376] I/user.sip_app_main_task_func waitMsg STATE_INCOMING sip_callback MSG_CONNECTED nil</span><br />
[2026-05-19 11:39:51.968][000000061.376] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-19 11:39:51.972][000000061.377] I/user.sip_app_key 通话建立成功</span><br />
[2026-05-19 11:39:51.979][000000061.378] D/voip voip task started</span><br />
[2026-05-19 11:39:51.984][000000061.379] D/voip voip start event</span><br />
[2026-05-19 11:39:51.990][000000061.379] E/voip voip config: remote=180.152.6.34:16780 codec=0 ptime=20</span><br />
[2026-05-19 11:39:51.998][000000061.379] E/voip voio origin: samples=8000</span><br />
[2026-05-19 11:39:52.003][000000061.380] E/voip voio frame: samples=160 bytes=320</span><br />
[2026-05-19 11:39:52.010][000000061.386] I/voip aec ready frame=160 tail_ms=200 denoise=1</span><br />
[2026-05-19 11:39:52.018][000000061.403] E/voip udp socket created and connected to 180.152.6.34:16780</span><br />
[2026-05-19 11:39:52.021][000000061.404] luat_i2s_save_old_config 279:i2s1 save old param</span><br />
[2026-05-19 11:39:52.029][000000061.420] E/voip audio started: multimedia_id=0 sample_rate=8000 backend=1</span><br />
[2026-05-19 11:39:52.034][000000061.421] I/user.exsip voip state: started</span><br />
<mark>[2026-05-19 11:39:52.039][000000061.422] I/user.sip_callback STATE_CONNECTED voip state started nil</span><br />
[2026-05-19 11:39:52.054][000000061.422] I/user.sip_callback VoIP状态: started</span><br /></mark>
[2026-05-19 11:39:52.063][000000061.423] I/voip voip running: 180.152.6.34:16780 codec=0 ptime=20</span><br />
[2026-05-19 11:39:54.375][000000063.912] W/voip_jb jb resync: expected_seq 36286 -> 36232 (pending 4)</span><br />
[2026-05-19 11:39:54.438][000000063.971] W/voip_jb jb resync: expected_seq 36235 -> 36260 (pending 7)</span><br />
[2026-05-19 11:39:54.501][000000064.031] W/voip_jb jb resync: expected_seq 36263 -> 36276 (pending 9)</span><br />
[2026-05-19 11:39:54.624][000000064.152] W/voip_jb jb resync: expected_seq 36282 -> 36284 (pending 14)</span><br />
[2026-05-19 11:39:56.563][000000066.094] I/user.sip send OPTIONS ping</span><br />
[2026-05-19 11:39:56.640][000000066.167] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
<mark>[2026-05-19 11:39:56.889][000000066.421] I/user.sip_callback STATE_CONNECTED voip stats table: 0C7B8E30 nil</span><br />
[2026-05-19 11:39:56.898][000000066.422] I/user.sip_callback VoIP统计 - 发送: 250 接收: 230 丢失: 0</span><br /></mark>
[2026-05-19 11:40:01.887][000000071.421] I/user.sip_callback STATE_CONNECTED voip stats table: 0C7B8738 nil</span><br />
[2026-05-19 11:40:01.895][000000071.422] I/user.sip_callback VoIP统计 - 发送: 500 接收: 473 丢失: 0</span><br />

##### 单击 PWRKEY 键，挂断通话

通话结束，结束原因为： local_hangup(我方主动挂断)，日志如下：

[2026-05-19 11:40:02.334][000000071.870] I/user.sip_app_key 按下POWERKEY键</span><br />
[2026-05-19 11:40:02.336][000000071.872] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_app_key MSG_HANGUP nil</span><br />
[2026-05-19 11:40:02.342][000000071.872] I/user.exsip hanging up</span><br />
[2026-05-19 11:40:02.348][000000071.873] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-19 11:40:02.355][000000071.874] I/user.sip cmd hangup </span><br />
[2026-05-19 11:40:02.361][000000071.875] I/user.sip BYE uri sip:mod_sofia@180.152.6.34:8910 from <sip:100000@10.18.113.64:5062;received=36.7.99.190:5062>;tag=1a4d4e84c8751186 to "Extension 100001" <sip:100001@180.152.6.34>;tag=BQZ8cmgc36Q7r routes 0</span><br />
[2026-05-19 11:40:02.368][000000071.878] I/user.sip send BYE</span><br />
[2026-05-19 11:40:02.442][000000071.966] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-19 11:40:02.450][000000071.969] I/user.exsip event: media action: stop</span><br />
[2026-05-19 11:40:02.457][000000071.969] I/user.exsip voip engine stopping</span><br />
<mark>[2026-05-19 11:40:02.462][000000071.970] I/user.sip_callback STATE_CONNECTED media stop table: 0C7B6D48 nil</span><br />
[2026-05-19 11:40:02.483][000000071.970] I/user.sip_callback 媒体通道已关闭，关闭原因： local_hangup</span><br /></mark>
[2026-05-19 11:40:02.510][000000071.971] I/user.sip call cleared</span><br />
[2026-05-19 11:40:02.525][000000071.971] I/user.exsip event: call action: ended</span><br />
[2026-05-19 11:40:02.531][000000071.972] I/user.exsip voip engine stopping</span><br />
[2026-05-19 11:40:02.542][000000071.972] I/user.sip_callback STATE_CONNECTED call ended table: 0C7B6C58 nil</span><br />
<mark>[2026-05-19 11:40:02.556][000000071.973] I/user.sip_callback call event sub_event= ended</span><br />
[2026-05-19 11:40:02.570][000000071.973] I/user.sip_callback 通话已结束，结束原因为： local_hangup 通话对象： table: 0C7BD440</span><br /></mark>
[2026-05-19 11:40:02.585][000000071.974] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_callback MSG_DISCONNECTED local_hangup</span><br />
[2026-05-19 11:40:02.601][000000071.975] I/user.sip_app_main_task_func after process STATE_READY</span><br />
[2026-05-19 11:40:02.603][000000071.976] I/user.sip_app_key 通话已断开</span><br />
[2026-05-19 11:40:02.608][000000071.985] D/voip voip stop event</span><br />
[2026-05-19 11:40:02.615][000000071.986] luat_i2s_load_old_config 297:i2s0 load old param</span><br />
[2026-05-19 11:40:02.623][000000071.988] I/user.exsip voip state: stopped</span><br />
<mark>[2026-05-19 11:40:02.628][000000071.988] I/user.sip_callback STATE_READY voip state stopped nil</span><br />
[2026-05-19 11:40:02.644][000000071.989] I/user.sip_callback VoIP状态: stopped</span><br /></mark>
[2026-05-19 11:40:02.655][000000071.990] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_PLAY_HUNGUP local_hangup</span><br />

### **场景二：WIFI 单网卡联网拨号测试**

#### SIP 和音频初始化：

[2026-05-18 18:03:11.106][000000002.335] D/net network ready 2, setup dns server</span><br />
[2026-05-18 18:03:11.111][000000002.336] D/netdrv IP_READY 2 192.168.137.232</span><br />
[2026-05-18 18:03:11.117][000000002.337] D/net 设置DNS服务器 id 2 index 0 ip 223.5.5.5</span><br />
[2026-05-18 18:03:11.125][000000002.337] D/net 设置DNS服务器 id 2 index 1 ip 114.114.114.114</span><br />
[2026-05-18 18:03:11.129][000000002.338] I/user.netdrv_wifi.ip_ready_func IP_READY 192.168.137.232 255.255.255.0 192.168.137.1 nil</span><br />
[2026-05-18 18:03:11.136][000000002.338] I/user.dnsproxy 开始监听</span><br />
[2026-05-18 18:03:11.140][000000002.339] I/user.sip_app_main_task_func recv IP_READY 2 3</span><br />
<mark>[2026-05-18 18:03:11.145][000000002.339] I/user.start 开始初始化 SIP，当前状态: STATE_INITING</span><br />
[2026-05-18 18:03:11.151][000000002.340] I/user.exaudio.setup 使用ES8311 I2S模式初始化</span><br /></mark>
[2026-05-18 18:03:11.155][000000002.341] I2C_MasterSetup 426:I2C0, Total 65 HCNT 22 LCNT 40</span><br />
[2026-05-18 18:03:11.160][000000002.416] D/audio codec init es8311 </span><br />
[2026-05-18 18:03:11.682][000000002.973] I/user.exaudio.setup 声道数已设置为:1(1=单声道,2=双声道)</span><br />
[2026-05-18 18:03:11.685][000000002.973] I/user.audio_drv exaudio.setup初始化成功</span><br />
[2026-05-18 18:03:11.872][000000003.157] I/user.audio_drv 已设置通话音量为: 40</span><br />
[2026-05-18 18:03:12.063][000000003.341] I/user.audio_drv 已设置麦克风音量为: 98</span><br />

#### WIFI 联网注册 SIP，日志如下：

[2026-05-18 18:03:12.069][000000003.342] I/user.exsip init completed: 100000@180.152.6.34</span><br />
[2026-05-18 18:03:12.111][000000003.398] I/user.exsip subscribed to IP_READY and IP_LOSE</span><br />
[2026-05-18 18:03:12.113][000000003.399] I/user.exsip current adapter set: 2</span><br />
[2026-05-18 18:03:12.151][000000003.404] I/user.sip SIP task uses locked adapter: nil transport: udp</span><br />
[2026-05-18 18:03:12.155][000000003.404] I/user.sip locked_adapter initialized to default: 2</span><br />
[2026-05-18 18:03:12.161][000000003.406] I/user.sip creating socket with adapter: 2 locked_adapter: 2</span><br />
[2026-05-18 18:03:12.165][000000003.406] D/socket connect to 180.152.6.34,8910</span><br />
<mark>[2026-05-18 18:03:12.171][000000003.407] D/net adapter 2 connect 180.152.6.34:8910 UDP</span><br /></mark>
[2026-05-18 18:03:12.178][000000003.408] I/user.exsip started adapter nil</span><br />
[2026-05-18 18:03:12.182][000000003.412] I/user.sip send REGISTER 180.152.6.34 8910</span><br />
[2026-05-18 18:03:12.194][000000003.414] I/user.exsip event: lifecycle action: online</span><br />
[2026-05-18 18:03:12.202][000000003.415] I/user.exsip lifecycle: online</span><br />
[2026-05-18 18:03:12.207][000000003.415] I/user.sip_callback STATE_INITING lifecycle online table: 0C7ECFF0 nil</span><br />
[2026-05-18 18:03:12.215][000000003.415] I/user.sip_callback lifecycle event: online</span><br />
[2026-05-18 18:03:12.224][000000003.416] I/user.sip_callback SIP 服务已在线，本地IP地址为： 192.168.137.232</span><br />
[2026-05-18 18:03:12.231][000000003.447] I/user.sip resp 401 Unauthorized from 180.152.6.34 8910</span><br />
[2026-05-18 18:03:12.236][000000003.454] I/user.sip send REGISTER (auth) cseq 2</span><br />
[2026-05-18 18:03:12.245][000000003.456] I/user.exsip event: register action: challenge</span><br />
[2026-05-18 18:03:12.249][000000003.457] I/user.sip_callback STATE_INITING register challenge table: 0C7C8A78 nil</span><br />
[2026-05-18 18:03:12.257][000000003.457] I/user.sip_callback 收到认证挑战，继续注册流程</span><br />
[2026-05-18 18:03:12.266][000000003.497] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-18 18:03:12.272][000000003.499] I/user.sip next register in 570 sec</span><br />
[2026-05-18 18:03:12.278][000000003.500] I/user.sip UDP OPTIONS keepalive started, interval 25000 ms</span><br />
[2026-05-18 18:03:12.288][000000003.501] I/user.exsip event: register action: ok</span><br />
[2026-05-18 18:03:12.292][000000003.501] I/user.sip_callback STATE_INITING register ok table: 0C7C7000 nil</span><br />
[2026-05-18 18:03:12.302][000000003.502] I/user.sip_callback 注册成功，有效期: 600 SIP响应头: table: 0C7C7A00</span><br />
<mark>[2026-05-18 18:03:12.311][000000003.502] I/user.sip_callback STATE_INITING ready nil nil nil</span><br />
[2026-05-18 18:03:12.319][000000003.503] I/user.sip_callback SIP 服务已就绪 当前SIP状态: STATE_INITING</span><br /></mark>
[2026-05-18 18:03:12.328][000000003.504] I/user.sip_app_main_task_func waitMsg STATE_INITING sip_callback MSG_READY nil</span><br />

#### 拨号测试

##### 单击 boot 键拨号

[2026-05-18 18:10:56.773][000000468.059] I/user.sip_app_key 按下BOOT键</span><br />
[2026-05-18 18:10:56.776][000000468.060] I/user.sip_app_main_task_func waitMsg STATE_READY sip_app_key MSG_DIAL 100001</span><br />
[2026-05-18 18:10:56.780][000000468.061] I/user.exsip calling: 100001</span><br />
[2026-05-18 18:10:56.883][000000468.168] I/user.sip_app_main_task_func after process STATE_DIALING</span><br />
[2026-05-18 18:10:56.886][000000468.169] I/user.sip cmd call 100001</span><br />
[2026-05-18 18:10:56.899][000000468.171] I/user.test ip 192.168.137.232</span><br />
[2026-05-18 18:10:56.904][000000468.172] I/user.sip setting call timeout 30 seconds</span><br />
[2026-05-18 18:10:56.908][000000468.175] I/user.sip send INVITE sip:100001@180.152.6.34</span><br />
[2026-05-18 18:10:56.916][000000468.197] I/user.sip resp 407 Proxy Authentication Required from 180.152.6.34 8910</span><br />
[2026-05-18 18:10:56.931][000000468.209] I/user.exsip event: call action: auth_retry</span><br />
[2026-05-18 18:10:56.959][000000468.235] I/user.sip resp 100 Trying from 180.152.6.34 8910</span><br />
[2026-05-18 18:10:56.991][000000468.265] I/user.sip resp 180 Ringing from 180.152.6.34 8910</span><br />
[2026-05-18 18:10:56.994][000000468.268] I/user.sip invite provisional response 180 Ringing</span><br />
[2026-05-18 18:10:57.005][000000468.269] I/user.exsip event: call action: ringing</span><br />
[2026-05-18 18:10:57.009][000000468.269] I/user.sip_callback STATE_DIALING call ringing table: 0C7978C0 nil</span><br />
<mark>[2026-05-18 18:10:57.016][000000468.270] I/user.sip_callback call event sub_event= ringing</span><br />
[2026-05-18 18:10:57.030][000000468.270] I/user.sip_callback 对方响铃中</span><br /></mark>


##### 对方接听，通话建立

[2026-05-18 18:11:00.755][000000472.043] I/user.sip resp 200 OK from 180.152.6.34 8910
[2026-05-18 18:11:00.770][000000472.045] I/user.sip parsing remote SDP v=0
o=FreeSWITCH 1779082685 1779082686 IN IP4 180.152.6.34
s=FreeSWITCH
c=IN IP4 180.152.6.34
t=0 0
m=audio 16376 RTP/AVP 0 101
a=rtpmap:0 PCMU/8000
a=rtpmap:101 telephone-event/8000
a=fmtp:101 0-15
a=ptime:20

[2026-05-18 18:11:00.774][000000472.047] I/user.sip stopping all call timers, clearing timeout_timer</span><br />
[2026-05-18 18:11:00.799][000000472.052] I/user.exsip event: media action: ready</span><br />
[2026-05-18 18:11:00.808][000000472.053] I/user.exsip media ready 180.152.6.34 16376 PCMU</span><br />
[2026-05-18 18:11:00.813][000000472.053] I/user.exsip start voip engine with adapter: 2 remote: 180.152.6.34:16376</span><br />
[2026-05-18 18:11:00.820][000000472.054] I/user.exsip voip engine started 180.152.6.34:16376 codec=PCMU adapter nil</span><br />
[2026-05-18 18:11:00.828][000000472.055] I/user.sip_callback STATE_DIALING media ready table: 0C794C30 nil</span><br />
[2026-05-18 18:11:00.838][000000472.055] I/user.sip_callback 媒体通道就绪 180.152.6.34:16376</span><br />
[2026-05-18 18:11:00.852][000000472.055] I/user.sip call established (outgoing)</span><br />
[2026-05-18 18:11:00.866][000000472.056] I/user.exsip event: call action: established</span><br />
[2026-05-18 18:11:00.876][000000472.057] I/user.sip_callback STATE_DIALING call connected table: 0C794518 nil</span><br />
<mark>[2026-05-18 18:11:00.889][000000472.057] I/user.sip_callback call event sub_event= connected</span><br />
[2026-05-18 18:11:00.900][000000472.057] I/user.sip_callback 通话已建立</span><br /></mark>
[2026-05-18 18:11:00.914][000000472.058] I/user.sip_app_main_task_func waitMsg STATE_DIALING sip_callback MSG_CONNECTED nil</span><br />
[2026-05-18 18:11:00.923][000000472.059] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-18 18:11:00.928][000000472.059] I/user.sip_app_key 通话建立成功</span><br />
[2026-05-18 18:11:00.933][000000472.060] D/voip voip task started</span><br />
[2026-05-18 18:11:00.944][000000472.061] D/voip voip start event</span><br />
[2026-05-18 18:11:00.949][000000472.061] E/voip voip config: remote=180.152.6.34:16376 codec=0 ptime=20</span><br />
[2026-05-18 18:11:00.956][000000472.062] E/voip voio origin: samples=8000</span><br />
[2026-05-18 18:11:00.961][000000472.062] E/voip voio frame: samples=160 bytes=320</span><br />
[2026-05-18 18:11:00.966][000000472.069] I/voip aec ready frame=160 tail_ms=200 denoise=1</span><br />
[2026-05-18 18:11:00.974][000000472.070] D/net adapter 2 connect 180.152.6.34:16376 UDP</span><br />
[2026-05-18 18:11:00.979][000000472.071] E/voip udp socket created and connected to 180.152.6.34:16376</span><br />
[2026-05-18 18:11:00.986][000000472.071] luat_i2s_save_old_config 279:i2s1 save old param</span><br />
[2026-05-18 18:11:00.991][000000472.088] E/voip audio started: multimedia_id=0 sample_rate=8000 backend=1</span><br />
[2026-05-18 18:11:00.995][000000472.089] I/user.exsip voip state: started</span><br />
<mark>[2026-05-18 18:11:01.000][000000472.089] I/user.sip_callback STATE_CONNECTED voip state started nil</span><br />
[2026-05-18 18:11:01.015][000000472.090] I/user.sip_callback VoIP状态: started</span><br /></mark>
[2026-05-18 18:11:01.027][000000472.090] I/voip voip running: 180.152.6.34:16376 codec=0 ptime=20</span><br />
<mark>[2026-05-18 18:11:05.809][000000477.088] I/user.sip_callback STATE_CONNECTED voip stats table: 0C794170 nil</span><br />
[2026-05-18 18:11:05.821][000000477.089] I/user.sip_callback VoIP统计 - 发送: 250 接收: 239 丢失: 0</span><br /></mark>

##### 单击 PWRKEY 键，挂断通话

结束原因为： local_hangup(我方主动挂断)，日志如下：

[2026-05-18 18:11:09.175][000000480.458] I/user.sip_app_key 按下POWERKEY键</span><br />
[2026-05-18 18:11:09.179][000000480.459] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_app_key MSG_HANGUP nil</span><br />
[2026-05-18 18:11:09.184][000000480.459] I/user.exsip hanging up</span><br />
[2026-05-18 18:11:09.189][000000480.460] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-18 18:11:09.196][000000480.461] I/user.sip cmd hangup </span><br />
[2026-05-18 18:11:09.200][000000480.461] I/user.sip BYE uri sip:100001@180.152.6.34:8910;transport=udp from <sip:100000@180.152.6.34>;tag=078dd5b6096f92c0 to <sip:100001@180.152.6.34>;tag=0evQa64mSpycD routes 0</span><br />
[2026-05-18 18:11:09.206][000000480.464] I/user.sip send BYE</span><br />
[2026-05-18 18:11:09.211][000000480.492] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-18 18:11:09.224][000000480.494] I/user.exsip event: media action: stop</span><br />
[2026-05-18 18:11:09.233][000000480.495] I/user.exsip voip engine stopping</span><br />
<mark>[2026-05-18 18:11:09.246][000000480.495] I/user.sip_callback STATE_CONNECTED media stop table: 0C790770 nil</span><br />
[2026-05-18 18:11:09.269][000000480.496] I/user.sip_callback 媒体通道已关闭，关闭原因： local_hangup</span><br /></mark>
[2026-05-18 18:11:09.287][000000480.496] I/user.sip call cleared</span><br />
[2026-05-18 18:11:09.300][000000480.497] I/user.exsip event: call action: ended</span><br />
[2026-05-18 18:11:09.306][000000480.497] I/user.exsip voip engine stopping</span><br />
[2026-05-18 18:11:09.308][000000480.498] I/user.sip_callback STATE_CONNECTED call ended table: 0C7906C8 nil</span><br />
<mark>[2026-05-18 18:11:09.322][000000480.498] I/user.sip_callback call event sub_event= ended</span><br />
[2026-05-18 18:11:09.334][000000480.499] I/user.sip_callback 通话已结束，结束原因为： local_hangup 通话对象： table: 0C79E918</span><br /></mark>
[2026-05-18 18:11:09.343][000000480.500] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_callback MSG_DISCONNECTED local_hangup</span><br />
[2026-05-18 18:11:09.359][000000480.500] I/user.sip_app_main_task_func after process STATE_READY</span><br />
[2026-05-18 18:11:09.368][000000480.501] I/user.sip_app_key 通话已断开</span><br />
[2026-05-18 18:11:09.373][000000480.508] D/voip voip stop event</span><br />
[2026-05-18 18:11:09.379][000000480.509] luat_i2s_load_old_config 297:i2s0 load old param</span><br />
[2026-05-18 18:11:09.385][000000480.512] I/user.exsip voip state: stopped</span><br />
<mark>[2026-05-18 18:11:09.391][000000480.512] I/user.sip_callback STATE_READY voip state stopped nil</span><br />
[2026-05-18 18:11:09.407][000000480.513] I/user.sip_callback VoIP状态: stopped</span><br /></mark>
[2026-05-18 18:11:09.423][000000480.514] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_PLAY_HUNGUP local_hangup</span><br />

#### 来电接听测试

##### 收到来电

[2026-05-19 11:48:00.491][000000068.667] I/user.sip req INVITE from 180.152.6.34 8910</span><br />
[2026-05-19 11:48:00.495][000000068.669] I/user.sip parsing remote SDP v=0</span><br />
o=FreeSWITCH 1779146915 1779146916 IN IP4 180.152.6.34</span><br />
s=FreeSWITCH</span><br />
c=IN IP4 180.152.6.34</span><br />
t=0 0</span><br />
m=audio 15566 RTP/AVP 102 0 8 103 101</span><br />
a=rtpmap:102 opus/48000/2</span><br />
a=fmtp:102 useinbandfec=1; maxaveragebitrate=30000; maxplaybackrate=48000; ptime=20; minptime=10; maxptime=40; stereo=1</span><br />
a=rtpmap:0 PCMU/8000</span><br />
a=rtpmap:8 PCMA/8000</span><br />
a=rtpmap:103 telephone-event/48000</span><br />
a=fmtp:103 0-15</span><br />
a=rtpmap:101 telephone-event/8000</span><br />
a=fmtp:101 0-15</span><br />
a=ptime:20</span><br />

[2026-05-19 11:48:00.515][000000068.677] I/user.exsip event: call action: incoming</span><br />
[2026-05-19 11:48:00.522][000000068.678] I/user.sip_callback STATE_READY call incoming table: 0C7BB590 nil</span><br />
<mark>[2026-05-19 11:48:00.537][000000068.678] I/user.sip_callback call event sub_event= incoming</span><br />
[2026-05-19 11:48:00.552][000000068.679] I/user.sip_callback 来电: "Extension 100001" <sip:100001@180.152.6.34>;tag=9SKUN2ptarc6j sip:100000@192.168.137.233:5062;received=180.171.81.183:62053 <sip:100000@192.168.137.233:5062;received=180.171.81.183:62053>;tag=9a41199408abdd6c</span><br /></mark>
[2026-05-19 11:48:00.574][000000068.680] I/user.exsip event: call action: ringing</span><br />
[2026-05-19 11:48:00.580][000000068.680] I/user.sip_callback STATE_READY call ringing table: 0C7BB240 nil</span><br />
<mark>[2026-05-19 11:48:00.596][000000068.681] I/user.sip_callback call event sub_event= ringing</span><br />
[2026-05-19 11:48:00.615][000000068.681] I/user.sip_callback 对方响铃中</span><br /></mark>
[2026-05-19 11:48:00.636][000000068.682] I/user.exsip event: media action: offer</span><br />
[2026-05-19 11:48:00.641][000000068.683] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_INCOMING "Extension 100001" <sip:100001@180.152.6.34>;tag=9SKUN2ptarc6j</span><br />
[2026-05-19 11:48:00.669][000000068.784] I/user.sip_app_main_task_func after process STATE_INCOMING</span><br />
[2026-05-19 11:48:00.674][000000068.785] I/user.sip_app_key 呼入中，来电号码： 100001</span><br />

##### 单击 boot 键接听来电

[2026-05-19 11:48:08.683][000000076.852] I/user.sip_app_key 按下BOOT键</span><br />
[2026-05-19 11:48:08.686][000000076.853] I/user.sip_app_key 呼入中，接听</span><br />
[2026-05-19 11:48:08.691][000000076.854] I/user.sip_app_main_task_func waitMsg STATE_INCOMING sip_app_key MSG_ACCEPT nil</span><br />
[2026-05-19 11:48:08.697][000000076.854] I/user.exsip answering call</span><br />
[2026-05-19 11:48:08.702][000000076.855] I/user.sip_app_main_task_func after process STATE_INCOMING</span><br />
[2026-05-19 11:48:08.708][000000076.855] I/user.sip cmd answer </span><br />
[2026-05-19 11:48:08.719][000000076.857] I/user.test ip 192.168.137.233</span><br />
[2026-05-19 11:48:08.724][000000076.860] I/user.sip answer 200 OK</span><br />
[2026-05-19 11:48:08.730][000000076.911] I/user.sip req ACK from 180.152.6.34 8910</span><br />
[2026-05-19 11:48:08.759][000000076.913] I/user.exsip event: media action: ready</span><br />
[2026-05-19 11:48:08.763][000000076.913] I/user.exsip media ready 180.152.6.34 15566 PCMU</span><br />
[2026-05-19 11:48:08.769][000000076.914] I/user.exsip start voip engine with adapter: 2 remote: 180.152.6.34:15566</span><br />
[2026-05-19 11:48:08.775][000000076.915] I/user.exsip voip engine started 180.152.6.34:15566 codec=PCMU adapter nil</span><br />
[2026-05-19 11:48:08.781][000000076.915] I/user.sip_callback STATE_INCOMING media ready table: 0C7B89F8 nil</span><br />
[2026-05-19 11:48:08.796][000000076.916] I/user.sip_callback 媒体通道就绪 180.152.6.34:15566</span><br />
[2026-05-19 11:48:08.813][000000076.917] I/user.sip call established (incoming)</span><br />
[2026-05-19 11:48:08.831][000000076.918] I/user.exsip event: call action: established</span><br />
[2026-05-19 11:48:08.838][000000076.918] I/user.sip_callback STATE_INCOMING call connected table: 0C7B8188 nil</span><br />
<mark>[2026-05-19 11:48:08.855][000000076.918] I/user.sip_callback call event sub_event= connected</span><br />
[2026-05-19 11:48:08.875][000000076.919] I/user.sip_callback 通话已建立</span><br /></mark>
[2026-05-19 11:48:08.891][000000076.920] I/user.sip_app_main_task_func waitMsg STATE_INCOMING sip_callback MSG_CONNECTED nil</span><br />
[2026-05-19 11:48:08.907][000000076.920] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-19 11:48:08.913][000000076.921] I/user.sip_app_key 通话建立成功</span><br />
[2026-05-19 11:48:08.924][000000076.921] D/voip voip task started</span><br />
[2026-05-19 11:48:08.931][000000076.922] D/voip voip start event</span><br />
[2026-05-19 11:48:08.937][000000076.922] E/voip voip config: remote=180.152.6.34:15566 codec=0 ptime=20</span><br />
[2026-05-19 11:48:08.944][000000076.922] E/voip voio origin: samples=8000</span><br />
[2026-05-19 11:48:08.952][000000076.923] E/voip voio frame: samples=160 bytes=320</span><br />
[2026-05-19 11:48:08.959][000000076.929] I/voip aec ready frame=160 tail_ms=200 denoise=1</span><br />
[2026-05-19 11:48:08.966][000000076.930] D/net adapter 2 connect 180.152.6.34:15566 UDP</span><br />
[2026-05-19 11:48:08.973][000000076.931] E/voip udp socket created and connected to 180.152.6.34:15566</span><br />
[2026-05-19 11:48:08.981][000000076.931] luat_i2s_save_old_config 279:i2s1 save old param</span><br />
[2026-05-19 11:48:08.988][000000076.948] E/voip audio started: multimedia_id=0 sample_rate=8000 backend=1</span><br />
[2026-05-19 11:48:08.995][000000076.949] I/user.exsip voip state: started</span><br />
<mark>[2026-05-19 11:48:09.003][000000076.950] I/user.sip_callback STATE_CONNECTED voip state started nil</span><br />
[2026-05-19 11:48:09.021][000000076.950] I/user.sip_callback VoIP状态: started</span><br /></mark>
[2026-05-19 11:48:09.041][000000076.951] I/voip voip running: 180.152.6.34:15566 codec=0 ptime=20</span><br />
[2026-05-19 11:48:10.410][000000078.589] I/user.sip send OPTIONS ping</span><br />
[2026-05-19 11:48:10.471][000000078.644] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-19 11:48:13.014][000000081.180] W/voip_jb jb resync: expected_seq 61008 -> 60957 (pending 3)</span><br />
[2026-05-19 11:48:13.090][000000081.259] W/voip_jb jb resync: expected_seq 60961 -> 61006 (pending 11)</span><br />
<mark>[2026-05-19 11:48:13.777][000000081.949] I/user.sip_callback STATE_CONNECTED voip stats table: 0C7B61C8 nil</span><br />
[2026-05-19 11:48:13.794][000000081.949] I/user.sip_callback VoIP统计 - 发送: 250 接收: 223 丢失: 0</span><br /></mark>

##### 单击 PWRKEY 键，挂断通话

结束原因为： local_hangup(我方主动挂断)，日志如下：


[2026-05-19 11:48:23.191][000000091.372] I/user.sip_app_key 按下POWERKEY键</span><br />
[2026-05-19 11:48:23.207][000000091.373] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_app_key MSG_HANGUP nil</span><br />
[2026-05-19 11:48:23.210][000000091.374] I/user.exsip hanging up</span><br />
[2026-05-19 11:48:23.216][000000091.374] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-19 11:48:23.225][000000091.375] I/user.sip cmd hangup </span><br />
[2026-05-19 11:48:23.230][000000091.376] I/user.sip BYE uri sip:mod_sofia@180.152.6.34:8910 from <sip:100000@192.168.137.233:5062;received=180.171.81.183:62053>;tag=9a41199408abdd6c to "Extension 100001" <sip:100001@180.152.6.34>;tag=9SKUN2ptarc6j routes 0</span><br />
[2026-05-19 11:48:23.238][000000091.378] I/user.sip send BYE</span><br />
[2026-05-19 11:48:23.285][000000091.451] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-19 11:48:23.293][000000091.454] I/user.exsip event: media action: stop</span><br />
[2026-05-19 11:48:23.299][000000091.454] I/user.exsip voip engine stopping</span><br />
<mark>[2026-05-19 11:48:23.306][000000091.455] I/user.sip_callback STATE_CONNECTED media stop table: 0C7B40A0 nil</span><br />
[2026-05-19 11:48:23.324][000000091.455] I/user.sip_callback 媒体通道已关闭，关闭原因： local_hangup</span><br /></mark>
[2026-05-19 11:48:23.342][000000091.455] I/user.sip call cleared</span><br />
[2026-05-19 11:48:23.354][000000091.456] I/user.exsip event: call action: ended</span><br />
[2026-05-19 11:48:23.359][000000091.457] I/user.exsip voip engine stopping</span><br />
[2026-05-19 11:48:23.371][000000091.457] I/user.sip_callback STATE_CONNECTED call ended table: 0C7B3FB0 nil</span><br />
<mark>[2026-05-19 11:48:23.389][000000091.458] I/user.sip_callback call event sub_event= ended</span><br />
[2026-05-19 11:48:23.408][000000091.458] I/user.sip_callback 通话已结束，结束原因为： local_hangup 通话对象： table: 0C7BA978</span><br /></mark>
[2026-05-19 11:48:23.428][000000091.459] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_callback MSG_DISCONNECTED local_hangup</span><br />
[2026-05-19 11:48:23.448][000000091.459] I/user.sip_app_main_task_func after process STATE_READY</span><br />
[2026-05-19 11:48:23.455][000000091.460] I/user.sip_app_key 通话已断开</span><br />
[2026-05-19 11:48:23.460][000000091.467] D/voip voip stop event</span><br />
[2026-05-19 11:48:23.466][000000091.468] luat_i2s_load_old_config 297:i2s0 load old param</span><br />
[2026-05-19 11:48:23.473][000000091.470] I/user.exsip voip state: stopped</span><br />
<mark>[2026-05-19 11:48:23.478][000000091.471] I/user.sip_callback STATE_READY voip state stopped nil</span><br />
[2026-05-19 11:48:23.497][000000091.471] I/user.sip_callback VoIP状态: stopped</span><br /></mark>
[2026-05-19 11:48:23.517][000000091.472] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_PLAY_HUNGUP local_hangup</span><br />
[2026-05-19 11:48:23.536][000000091.473] I/user.sip_app_main_task_func after process STATE_READY</span><br />

### **场景三：以太网单网卡联网拨号测试**

#### SIP 和音频初始化：

[2026-05-18 18:21:41.397][000000466.258] D/net network ready 4, setup dns server</span><br />
[2026-05-18 18:21:41.408][000000466.259] D/netdrv IP_READY 4 192.168.1.100</span><br />
[2026-05-18 18:21:41.411][000000466.260] D/net 设置DNS服务器 id 4 index 0 ip 223.5.5.5</span><br />
[2026-05-18 18:21:41.417][000000466.260] D/net 设置DNS服务器 id 4 index 1 ip 114.114.114.114</span><br />
[2026-05-18 18:21:41.420][000000466.261] I/user.netdrv_eth_spi.ip_ready_func IP_READY 192.168.1.100 255.255.255.0 192.168.1.1 nil</span><br />
[2026-05-18 18:21:41.426][000000466.262] I/user.sip_app_main_task_func recv IP_READY 4 4</span><br />
<mark>[2026-05-18 18:21:41.432][000000466.262] I/user.start 开始初始化 SIP，当前状态: STATE_INITING</span><br />
[2026-05-18 18:21:41.436][000000466.263] I/user.exaudio.setup 使用ES8311 I2S模式初始化</span><br /></mark>
[2026-05-18 18:21:41.441][000000466.264] I2C_MasterSetup 426:I2C0, Total 65 HCNT 22 LCNT 40</span><br />
[2026-05-18 18:21:41.446][000000466.340] D/audio codec init es8311 </span><br />
[2026-05-18 18:21:41.974][000000466.896] I/user.exaudio.setup 声道数已设置为:1(1=单声道,2=双声道)</span><br />
[2026-05-18 18:21:41.976][000000466.896] I/user.audio_drv exaudio.setup初始化成功</span><br />
[2026-05-18 18:21:42.158][000000467.080] I/user.audio_drv 已设置通话音量为: 40</span><br />
[2026-05-18 18:21:42.329][000000467.264] I/user.audio_drv 已设置麦克风音量为: 98</span><br />


#### 以太网联网注册 SIP，日志如下：

[2026-05-18 18:21:42.394][000000467.326] I/user.exsip current adapter set: 4</span><br />
[2026-05-18 18:21:42.435][000000467.331] I/user.sip SIP task uses locked adapter: nil transport: udp</span><br />
[2026-05-18 18:21:42.441][000000467.331] I/user.sip locked_adapter initialized to default: 4</span><br />
[2026-05-18 18:21:42.446][000000467.333] I/user.sip creating socket with adapter: 4 locked_adapter: 4</span><br />
[2026-05-18 18:21:42.450][000000467.333] D/socket connect to 180.152.6.34,8910</span><br />
<mark>[2026-05-18 18:21:42.456][000000467.334] D/net adapter 4 connect 180.152.6.34:8910 UDP</span><br /></mark>
[2026-05-18 18:21:42.459][000000467.335] I/user.exsip started adapter nil</span><br />
[2026-05-18 18:21:42.464][000000467.335] I/user.dnsproxy 开始监听</span><br />
[2026-05-18 18:21:42.468][000000467.340] I/user.sip send REGISTER 180.152.6.34 8910</span><br />
[2026-05-18 18:21:42.478][000000467.341] I/user.exsip event: lifecycle action: online</span><br />
[2026-05-18 18:21:42.483][000000467.342] I/user.exsip lifecycle: online</span><br />
[2026-05-18 18:21:42.488][000000467.342] I/user.sip_callback STATE_INITING lifecycle online table: 0C7ED110 nil</span><br />
[2026-05-18 18:21:42.493][000000467.343] I/user.sip_callback lifecycle event: online</span><br />
[2026-05-18 18:21:42.497][000000467.343] I/user.sip_callback SIP 服务已在线，本地IP地址为： 192.168.1.100</span><br />
[2026-05-18 18:21:42.508][000000467.361] I/user.sip resp 401 Unauthorized from 180.152.6.34 8910</span><br />
[2026-05-18 18:21:42.514][000000467.368] I/user.sip send REGISTER (auth) cseq 2</span><br />
[2026-05-18 18:21:42.522][000000467.369] I/user.exsip event: register action: challenge</span><br />
[2026-05-18 18:21:42.526][000000467.370] I/user.sip_callback STATE_INITING register challenge table: 0C7D3E80 nil</span><br />
[2026-05-18 18:21:42.531][000000467.370] I/user.sip_callback 收到认证挑战，继续注册流程</span><br />
[2026-05-18 18:21:42.541][000000467.384] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-18 18:21:42.548][000000467.386] I/user.sip next register in 570 sec</span><br />
[2026-05-18 18:21:42.550][000000467.387] I/user.sip UDP OPTIONS keepalive started, interval 25000 ms</span><br />
[2026-05-18 18:21:42.560][000000467.388] I/user.exsip event: register action: ok</span><br />
[2026-05-18 18:21:42.565][000000467.388] I/user.sip_callback STATE_INITING register ok table: 0C7D2418 nil</span><br />
[2026-05-18 18:21:42.570][000000467.389] I/user.sip_callback 注册成功，有效期: 600 SIP响应头: table: 0C7D3B08</span><br />
<mark>[2026-05-18 18:21:42.575][000000467.389] I/user.sip_callback STATE_INITING ready nil nil nil</span><br />
[2026-05-18 18:21:42.582][000000467.389] I/user.sip_callback SIP 服务已就绪 当前SIP状态: STATE_INITING</span><br /></mark>
[2026-05-18 18:21:42.591][000000467.390] I/user.sip_app_main_task_func waitMsg STATE_INITING sip_callback MSG_READY nil</span><br />

#### 拨号测试

##### 单击 boot 键拨号

[2026-05-18 18:26:33.781][000000758.708] I/user.sip_app_key 按下BOOT键</span><br />
[2026-05-18 18:26:33.782][000000758.710] I/user.sip_app_main_task_func waitMsg STATE_READY sip_app_key MSG_DIAL 100001</span><br />
[2026-05-18 18:26:33.782][000000758.711] I/user.exsip calling: 100001</span><br />
[2026-05-18 18:26:33.891][000000758.815] I/user.sip_app_main_task_func after process STATE_DIALING</span><br />
[2026-05-18 18:26:33.893][000000758.816] I/user.sip cmd call 100001</span><br />
[2026-05-18 18:26:33.895][000000758.818] I/user.test ip 192.168.1.100</span><br />
[2026-05-18 18:26:33.897][000000758.820] I/user.sip setting call timeout 30 seconds</span><br />
[2026-05-18 18:26:33.906][000000758.823] I/user.sip send INVITE sip:100001@180.152.6.34</span><br />
[2026-05-18 18:26:33.908][000000758.837] I/user.sip resp 407 Proxy Authentication Required from 180.152.6.34 8910</span><br />
[2026-05-18 18:26:33.923][000000758.848] I/user.exsip event: call action: auth_retry</span><br />
[2026-05-18 18:26:33.952][000000758.877] I/user.sip resp 100 Trying from 180.152.6.34 8910</span><br />
[2026-05-18 18:26:33.983][000000758.905] I/user.sip resp 180 Ringing from 180.152.6.34 8910</span><br />
[2026-05-18 18:26:33.984][000000758.907] I/user.sip invite provisional response 180 Ringing</span><br />
[2026-05-18 18:26:33.984][000000758.908] I/user.exsip event: call action: ringing</span><br />
[2026-05-18 18:26:33.985][000000758.909] I/user.sip_callback STATE_DIALING call ringing table: 0C7A3E20 nil</span><br />
<mark>[2026-05-18 18:26:33.985][000000758.909] I/user.sip_callback call event sub_event= ringing</span><br />
[2026-05-18 18:26:33.985][000000758.909] I/user.sip_callback 对方响铃中</span><br /></mark>


##### 对方接听，通话建立

[2026-05-18 18:26:38.089][000000763.012] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-18 18:26:38.093][000000763.015] I/user.sip parsing remote SDP v=0</span><br />
o=FreeSWITCH 1779084091 1779084092 IN IP4 180.152.6.34</span><br />
s=FreeSWITCH</span><br />
c=IN IP4 180.152.6.34</span><br />
t=0 0</span><br />
m=audio 15908 RTP/AVP 0 101</span><br />
a=rtpmap:0 PCMU/8000</span><br />
a=rtpmap:101 telephone-event/8000</span><br />
a=fmtp:101 0-15</span><br />
a=ptime:20</span><br />

[2026-05-18 18:26:38.103][000000763.017] I/user.sip stopping all call timers, clearing timeout_timer</span><br />
[2026-05-18 18:26:38.131][000000763.022] I/user.exsip event: media action: ready</span><br />
[2026-05-18 18:26:38.136][000000763.022] I/user.exsip media ready 180.152.6.34 15908 PCMU</span><br />
[2026-05-18 18:26:38.147][000000763.023] I/user.exsip start voip engine with adapter: 4 remote: 180.152.6.34:15908</span><br />
[2026-05-18 18:26:38.157][000000763.024] I/user.exsip voip engine started 180.152.6.34:15908 codec=PCMU adapter nil</span><br />
[2026-05-18 18:26:38.164][000000763.025] I/user.sip_callback STATE_DIALING media ready table: 0C7A11C8 nil</span><br />
[2026-05-18 18:26:38.174][000000763.025] I/user.sip_callback 媒体通道就绪 180.152.6.34:15908</span><br />
[2026-05-18 18:26:38.185][000000763.025] I/user.sip call established (outgoing)</span><br />
[2026-05-18 18:26:38.200][000000763.026] I/user.exsip event: call action: established</span><br />
[2026-05-18 18:26:38.209][000000763.027] I/user.sip_callback STATE_DIALING call connected table: 0C7A0AB8 nil</span><br />
<mark>[2026-05-18 18:26:38.217][000000763.027] I/user.sip_callback call event sub_event= connected</span><br />
[2026-05-18 18:26:38.231][000000763.027] I/user.sip_callback 通话已建立</span><br /></mark>
[2026-05-18 18:26:38.238][000000763.028] I/user.sip_app_main_task_func waitMsg STATE_DIALING sip_callback MSG_CONNECTED nil</span><br />
[2026-05-18 18:26:38.255][000000763.029] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-18 18:26:38.259][000000763.029] I/user.sip_app_key 通话建立成功</span><br />
[2026-05-18 18:26:38.270][000000763.030] D/voip voip task started</span><br />
[2026-05-18 18:26:38.276][000000763.031] D/voip voip start event</span><br />
[2026-05-18 18:26:38.281][000000763.031] E/voip voip config: remote=180.152.6.34:15908 codec=0 ptime=20</span><br />
[2026-05-18 18:26:38.290][000000763.032] E/voip voio origin: samples=8000</span><br />
[2026-05-18 18:26:38.294][000000763.032] E/voip voio frame: samples=160 bytes=320</span><br />
[2026-05-18 18:26:38.299][000000763.038] I/voip aec ready frame=160 tail_ms=200 denoise=1</span><br />
[2026-05-18 18:26:38.309][000000763.040] D/net adapter 4 connect 180.152.6.34:15908 UDP</span><br />
[2026-05-18 18:26:38.313][000000763.040] E/voip udp socket created and connected to 180.152.6.34:15908</span><br />
[2026-05-18 18:26:38.324][000000763.041] luat_i2s_save_old_config 279:i2s1 save old param</span><br />
[2026-05-18 18:26:38.328][000000763.058] E/voip audio started: multimedia_id=0 sample_rate=8000 backend=1</span><br />
[2026-05-18 18:26:38.333][000000763.059] I/user.exsip voip state: started</span><br />
<mark>[2026-05-18 18:26:38.342][000000763.059] I/user.sip_callback STATE_CONNECTED voip state started nil</span><br />
[2026-05-18 18:26:38.349][000000763.060] I/user.sip_callback VoIP状态: started</span><br /></mark>
[2026-05-18 18:26:38.359][000000763.060] I/voip voip running: 180.152.6.34:15908 codec=0 ptime=20</span><br />
[2026-05-18 18:26:42.517][000000767.443] I/user.sip send OPTIONS ping</span><br />
[2026-05-18 18:26:42.531][000000767.455] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-18 18:26:42.999][000000767.928] W/voip_jb jb resync: expected_seq 60769 -> 60765 (pending 2)</span><br />
<mark>[2026-05-18 18:26:43.138][000000768.058] I/user.sip_callback STATE_CONNECTED voip stats table: 0C79EB18 nil</span><br />
[2026-05-18 18:26:43.148][000000768.059] I/user.sip_callback VoIP统计 - 发送: 250 接收: 233 丢失: 0</span><br /></mark>

##### 单击 PWRKEY 键，挂断通话

结束原因为： local_hangup(我方主动挂断)，日志如下：

[2026-05-18 18:26:46.183][000000771.100] I/user.sip_app_key 按下POWERKEY键</span><br />
[2026-05-18 18:26:46.186][000000771.101] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_app_key MSG_HANGUP nil</span><br />
[2026-05-18 18:26:46.192][000000771.101] I/user.exsip hanging up</span><br />
[2026-05-18 18:26:46.196][000000771.102] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-18 18:26:46.201][000000771.103] I/user.sip cmd hangup </span><br />
[2026-05-18 18:26:46.205][000000771.103] I/user.sip BYE uri sip:100001@180.152.6.34:8910;transport=udp from <sip:100000@180.152.6.34>;tag=c054d234b05e06b9 to <sip:100001@180.152.6.34>;tag=Ue2BZ9amjSQpm routes 0</span><br />
[2026-05-18 18:26:46.211][000000771.106] I/user.sip send BYE</span><br />
[2026-05-18 18:26:46.215][000000771.131] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-18 18:26:46.227][000000771.133] I/user.exsip event: media action: stop</span><br />
[2026-05-18 18:26:46.231][000000771.133] I/user.exsip voip engine stopping</span><br />
<mark>[2026-05-18 18:26:46.238][000000771.134] I/user.sip_callback STATE_CONNECTED media stop table: 0C79CD38 nil</span><br />
[2026-05-18 18:26:46.262][000000771.134] I/user.sip_callback 媒体通道已关闭，关闭原因： local_hangup</span><br /></mark>
[2026-05-18 18:26:46.284][000000771.135] I/user.sip call cleared</span><br />
[2026-05-18 18:26:46.301][000000771.135] I/user.exsip event: call action: ended</span><br />
[2026-05-18 18:26:46.305][000000771.136] I/user.exsip voip engine stopping</span><br />
[2026-05-18 18:26:46.312][000000771.136] I/user.sip_callback STATE_CONNECTED call ended table: 0C79CC90 nil</span><br />
<mark>[2026-05-18 18:26:46.325][000000771.137] I/user.sip_callback call event sub_event= ended</span><br />
[2026-05-18 18:26:46.338][000000771.137] I/user.sip_callback 通话已结束，结束原因为： local_hangup 通话对象： table: 0C7AAEB0</span><br /></mark>
[2026-05-18 18:26:46.351][000000771.138] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_callback MSG_DISCONNECTED local_hangup</span><br />
[2026-05-18 18:26:46.361][000000771.139] I/user.sip_app_main_task_func after process STATE_READY</span><br />
[2026-05-18 18:26:46.365][000000771.139] I/user.sip_app_key 通话已断开</span><br />
[2026-05-18 18:26:46.370][000000771.140] D/voip voip stop event</span><br />
[2026-05-18 18:26:46.376][000000771.141] luat_i2s_load_old_config 297:i2s0 load old param</span><br />
[2026-05-18 18:26:46.380][000000771.143] I/user.exsip voip state: stopped</span><br />
<mark>[2026-05-18 18:26:46.385][000000771.144] I/user.sip_callback STATE_READY voip state stopped nil</span><br />
[2026-05-18 18:26:46.396][000000771.144] I/user.sip_callback VoIP状态: stopped</span><br /></mark>
[2026-05-18 18:26:46.409][000000771.145] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_PLAY_HUNGUP local_hangup</span><br />

#### 来电接听测试

##### 收到来电

[2026-05-19 11:56:03.011][000000016.468] I/user.sip req INVITE from 180.152.6.34 8910</span><br />
[2026-05-19 11:56:03.013][000000016.469] I/user.sip parsing remote SDP v=0</span><br />
o=FreeSWITCH 1779147004 1779147005 IN IP4 180.152.6.34</span><br />
s=FreeSWITCH</span><br />
c=IN IP4 180.152.6.34</span><br />
t=0 0</span><br />
m=audio 15960 RTP/AVP 8 0 101</span><br />
a=rtpmap:8 PCMA/8000</span><br />
a=rtpmap:0 PCMU/8000</span><br />
a=rtpmap:101 telephone-event/8000</span><br />
a=fmtp:101 0-15</span><br />
a=ptime:20</span><br />

[2026-05-19 11:56:03.016][000000016.477] I/user.exsip event: call action: incoming</span><br />
[2026-05-19 11:56:03.017][000000016.478] I/user.sip_callback STATE_READY call incoming table: 0C7BFD70 nil</span><br />
<mark>[2026-05-19 11:56:03.019][000000016.478] I/user.sip_callback call event sub_event= incoming</span><br />
[2026-05-19 11:56:03.021][000000016.478] I/user.sip_callback 来电: "Extension 100001" <sip:100001@180.152.6.34>;tag=3my5KXDQFH40K sip:100000@192.168.1.100:5062;received=180.171.81.183:46336 <sip:100000@192.168.1.100:5062;received=180.171.81.183:46336>;tag=01ab8f8afea177a0</span><br /></mark>
[2026-05-19 11:56:03.024][000000016.479] I/user.exsip event: call action: ringing</span><br />
[2026-05-19 11:56:03.025][000000016.480] I/user.sip_callback STATE_READY call ringing table: 0C7BFA28 nil</span><br />
<mark>[2026-05-19 11:56:03.027][000000016.480] I/user.sip_callback call event sub_event= ringing</span><br />
[2026-05-19 11:56:03.030][000000016.481] I/user.sip_callback 对方响铃中</span><br /></mark>
[2026-05-19 11:56:03.033][000000016.481] I/user.exsip event: media action: offer</span><br />
[2026-05-19 11:56:03.034][000000016.482] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_INCOMING "Extension 100001" <sip:100001@180.152.6.34>;tag=3my5KXDQFH40K</span><br />
[2026-05-19 11:56:03.120][000000016.584] I/user.sip_app_main_task_func after process STATE_INCOMING</span><br />
[2026-05-19 11:56:03.121][000000016.585] I/user.sip_app_key 呼入中，来电号码： 100001</span><br />

##### 单击 boot 键接听来电

[2026-05-19 11:56:10.052][000000023.515] I/user.sip_app_key 按下BOOT键</span><br />
[2026-05-19 11:56:10.054][000000023.516] I/user.sip_app_key 呼入中，接听</span><br />
[2026-05-19 11:56:10.054][000000023.517] I/user.sip_app_main_task_func waitMsg STATE_INCOMING sip_app_key MSG_ACCEPT nil</span><br />
[2026-05-19 11:56:10.055][000000023.517] I/user.exsip answering call</span><br />
[2026-05-19 11:56:10.056][000000023.518] I/user.sip_app_main_task_func after process STATE_INCOMING</span><br />
[2026-05-19 11:56:10.056][000000023.518] I/user.sip cmd answer </span><br />
[2026-05-19 11:56:10.057][000000023.520] I/user.test ip 192.168.1.100</span><br />
[2026-05-19 11:56:10.067][000000023.523] I/user.sip answer 200 OK</span><br />
[2026-05-19 11:56:10.082][000000023.537] I/user.sip req ACK from 180.152.6.34 8910</span><br />
[2026-05-19 11:56:10.085][000000023.539] I/user.exsip event: media action: ready</span><br />
[2026-05-19 11:56:10.086][000000023.540] I/user.exsip media ready 180.152.6.34 15960 PCMU</span><br />
[2026-05-19 11:56:10.086][000000023.540] I/user.exsip start voip engine with adapter: 4 remote: 180.152.6.34:15960</span><br />
[2026-05-19 11:56:10.094][000000023.541] I/user.exsip voip engine started 180.152.6.34:15960 codec=PCMU adapter nil</span><br />
<mark>[2026-05-19 11:56:10.102][000000023.542] I/user.sip_callback STATE_INCOMING media ready table: 0C7BD200 nil</span><br />
[2026-05-19 11:56:10.109][000000023.542] I/user.sip_callback 媒体通道就绪 180.152.6.34:15960</span><br /></mark>
[2026-05-19 11:56:10.121][000000023.543] I/user.sip call established (incoming)</span><br />
[2026-05-19 11:56:10.136][000000023.543] I/user.exsip event: call action: established</span><br />
[2026-05-19 11:56:10.143][000000023.544] I/user.sip_callback STATE_INCOMING call connected table: 0C7BC990 nil</span><br />
<mark>[2026-05-19 11:56:10.150][000000023.544] I/user.sip_callback call event sub_event= connected</span><br />
[2026-05-19 11:56:10.156][000000023.544] I/user.sip_callback 通话已建立</span><br /></mark>
[2026-05-19 11:56:10.163][000000023.545] I/user.sip_app_main_task_func waitMsg STATE_INCOMING sip_callback MSG_CONNECTED nil</span><br />
[2026-05-19 11:56:10.170][000000023.546] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-19 11:56:10.177][000000023.547] I/user.sip_app_key 通话建立成功</span><br />
[2026-05-19 11:56:10.185][000000023.547] D/voip voip task started</span><br />
[2026-05-19 11:56:10.192][000000023.548] D/voip voip start event</span><br />
[2026-05-19 11:56:10.203][000000023.548] E/voip voip config: remote=180.152.6.34:15960 codec=0 ptime=20</span><br />
[2026-05-19 11:56:10.210][000000023.548] E/voip voio origin: samples=8000</span><br />
[2026-05-19 11:56:10.216][000000023.549] E/voip voio frame: samples=160 bytes=320</span><br />
[2026-05-19 11:56:10.224][000000023.555] I/voip aec ready frame=160 tail_ms=200 denoise=1</span><br />
[2026-05-19 11:56:10.230][000000023.556] D/net adapter 4 connect 180.152.6.34:15960 UDP</span><br />
[2026-05-19 11:56:10.232][000000023.557] E/voip udp socket created and connected to 180.152.6.34:15960</span><br />
[2026-05-19 11:56:10.239][000000023.558] luat_i2s_save_old_config 279:i2s1 save old param</span><br />
[2026-05-19 11:56:10.244][000000023.574] E/voip audio started: multimedia_id=0 sample_rate=8000 backend=1</span><br />
[2026-05-19 11:56:10.251][000000023.575] I/user.exsip voip state: started</span><br />
<mark>[2026-05-19 11:56:10.263][000000023.575] I/user.sip_callback STATE_CONNECTED voip state started nil</span><br />
[2026-05-19 11:56:10.272][000000023.576] I/user.sip_callback VoIP状态: started</span><br /></mark>
[2026-05-19 11:56:10.278][000000023.576] I/voip voip running: 180.152.6.34:15960 codec=0 ptime=20</span><br />
[2026-05-19 11:56:12.599][000000026.065] W/voip_jb jb resync: expected_seq 58736 -> 58681 (pending 3)</span><br />
[2026-05-19 11:56:12.663][000000026.125] W/voip_jb jb resync: expected_seq 58684 -> 58700 (pending 5)</span><br />
[2026-05-19 11:56:12.725][000000026.186] W/voip_jb jb resync: expected_seq 58703 -> 58734 (pending 7)</span><br />
[2026-05-19 11:56:15.030][000000028.496] I/user.sip send OPTIONS ping</span><br />
[2026-05-19 11:56:15.046][000000028.508] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
<mark>[2026-05-19 11:56:15.107][000000028.575] I/user.sip_callback STATE_CONNECTED voip stats table: 0C7BA828 nil</span><br />
[2026-05-19 11:56:15.114][000000028.575] I/user.sip_callback VoIP统计 - 发送: 250 接收: 234 丢失: 0</span><br /></mark>

##### 单击 PWRKEY 键，挂断通话

结束原因为： local_hangup(我方主动挂断)，日志如下：

[2026-05-19 11:56:18.004][000000031.469] I/user.sip_app_key 按下POWERKEY键</span><br />
[2026-05-19 11:56:18.007][000000031.470] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_app_key MSG_HANGUP nil</span><br />
[2026-05-19 11:56:18.013][000000031.471] I/user.exsip hanging up</span><br />
[2026-05-19 11:56:18.018][000000031.471] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-19 11:56:18.024][000000031.472] I/user.sip cmd hangup </span><br />
[2026-05-19 11:56:18.033][000000031.473] I/user.sip BYE uri sip:mod_sofia@180.152.6.34:8910 from <sip:100000@192.168.1.100:5062;received=180.171.81.183:46336>;tag=01ab8f8afea177a0 to "Extension 100001" <sip:100001@180.152.6.34>;tag=3my5KXDQFH40K routes 0
[2026-05-19 11:56:18.044][000000031.475] I/user.sip send BYE</span><br />
[2026-05-19 11:56:18.047][000000031.497] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-19 11:56:18.062][000000031.500] I/user.exsip event: media action: stop</span><br />
[2026-05-19 11:56:18.072][000000031.500] I/user.exsip voip engine stopping</span><br />
<mark>[2026-05-19 11:56:18.080][000000031.501] I/user.sip_callback STATE_CONNECTED media stop table: 0C7B8860 nil</span><br />
[2026-05-19 11:56:18.097][000000031.501] I/user.sip_callback 媒体通道已关闭，关闭原因： local_hangup</span><br /></mark>
[2026-05-19 11:56:18.117][000000031.501] I/user.sip call cleared</span><br />
[2026-05-19 11:56:18.133][000000031.502] I/user.exsip event: call action: ended</span><br />
[2026-05-19 11:56:18.139][000000031.503] I/user.exsip voip engine stopping</span><br />
[2026-05-19 11:56:18.147][000000031.503] I/user.sip_callback STATE_CONNECTED call ended table: 0C7B8770 nil</span><br />
<mark>[2026-05-19 11:56:18.160][000000031.504] I/user.sip_callback call event sub_event= ended</span><br />
[2026-05-19 11:56:18.173][000000031.504] I/user.sip_callback 通话已结束，结束原因为： local_hangup 通话对象： table: 0C7BF168</span><br /></mark>
[2026-05-19 11:56:18.188][000000031.505] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_callback MSG_DISCONNECTED local_hangup</span><br />
[2026-05-19 11:56:18.198][000000031.506] I/user.sip_app_main_task_func after process STATE_READY</span><br />
[2026-05-19 11:56:18.203][000000031.506] I/user.sip_app_key 通话已断开</span><br />
[2026-05-19 11:56:18.211][000000031.514] D/voip voip stop event</span><br />
[2026-05-19 11:56:18.216][000000031.515] luat_i2s_load_old_config 297:i2s0 load old param</span><br />
[2026-05-19 11:56:18.223][000000031.517] I/user.exsip voip state: stopped</span><br />
<mark>[2026-05-19 11:56:18.229][000000031.518] I/user.sip_callback STATE_READY voip state stopped nil</span><br />
[2026-05-19 11:56:18.242][000000031.518] I/user.sip_callback VoIP状态: stopped</span><br /></mark>
[2026-05-19 11:56:18.255][000000031.519] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_PLAY_HUNGUP local_hangup</span><br />
[2026-05-19 11:56:18.263][000000031.520] I/user.sip_app_main_task_func after process STATE_READY</span><br />

### **场景四：多网卡联网组合通话保持测试**

先断开 wifi 和以太网，用 4g 注册，通话建立的时候再打开 wifi 或者接上以太网，通话能够保持。

#### SIP 和音频初始化：

[2026-05-18 18:32:49.383][000000009.273] I/user.4G网卡httpdns域名解析成功</span><br />
[2026-05-18 18:32:49.388][000000009.274] I/user.httpdns baidu.com 110.242.74.102</span><br />
[2026-05-18 18:32:49.392][000000009.274] I/user.设置网卡 4G</span><br />
[2026-05-18 18:32:49.399][000000009.275] I/user.netdrv_multiple_notify_cbfunc use new adapter 4G 1</span><br />
[2026-05-18 18:32:49.404][000000009.276] I/user.exnetif publish network status 4G 1</span><br />
<mark>[2026-05-18 18:32:49.409][000000009.276] dft adapter change from 4 to 1</span><br />
[2026-05-18 18:32:49.648][000000009.539] I/user.sip_app_main_task_func recv IP_READY 1 4</span><br /></mark>
[2026-05-18 18:32:49.650][000000009.540] I/user.start 开始初始化 SIP，当前状态: STATE_INITING</span><br />
<mark>[2026-05-18 18:32:49.655][000000009.541] I/user.exaudio.setup 使用ES8311 I2S模式初始化</span><br /></mark>
[2026-05-18 18:32:49.659][000000009.541] I2C_MasterSetup 426:I2C0, Total 65 HCNT 22 LCNT 40</span><br />
[2026-05-18 18:32:49.727][000000009.617] D/audio codec init es8311 </span><br />
[2026-05-18 18:32:50.293][000000010.175] I/user.exaudio.setup 声道数已设置为:1(1=单声道,2=双声道)</span><br />
[2026-05-18 18:32:50.297][000000010.175] I/user.audio_drv exaudio.setup初始化成功</span><br />
[2026-05-18 18:32:50.465][000000010.359] I/user.audio_drv 已设置通话音量为: 40</span><br />
[2026-05-18 18:32:50.657][000000010.543] I/user.audio_drv 已设置麦克风音量为: 98</span><br />

#### 4g 联网注册 SIP，日志如下：

<mark>[2026-05-18 18:32:50.722][000000010.603] I/user.exsip current adapter set: 1</span><br /></mark>
[2026-05-18 18:32:50.760][000000010.608] I/user.sip SIP task uses locked adapter: nil transport: udp</span><br />
[2026-05-18 18:32:50.765][000000010.609] I/user.sip locked_adapter initialized to default: 1</span><br />
[2026-05-18 18:32:50.769][000000010.610] I/user.sip creating socket with adapter: 1 locked_adapter: 1</span><br />
[2026-05-18 18:32:50.775][000000010.611] D/socket connect to 180.152.6.34,8910</span><br />
[2026-05-18 18:32:50.779][000000010.612] I/user.exsip started adapter nil</span><br />
[2026-05-18 18:32:50.789][000000010.616] I/user.sip send REGISTER 180.152.6.34 8910</span><br />
[2026-05-18 18:32:50.801][000000010.619] I/user.exsip event: lifecycle action: online</span><br />
[2026-05-18 18:32:50.803][000000010.619] I/user.exsip lifecycle: online</span><br />
[2026-05-18 18:32:50.808][000000010.619] I/user.sip_callback STATE_INITING lifecycle online table: 0C7EC730 nil</span><br />
[2026-05-18 18:32:50.813][000000010.620] I/user.sip_callback lifecycle event: online</span><br />
[2026-05-18 18:32:50.821][000000010.620] I/user.sip_callback SIP 服务已在线，本地IP地址为： 10.19.168.88</span><br />
[2026-05-18 18:32:50.831][000000010.721] I/user.sip resp 401 Unauthorized from 180.152.6.34 8910</span><br />
[2026-05-18 18:32:50.847][000000010.729] I/user.sip send REGISTER (auth) cseq 2</span><br />
[2026-05-18 18:32:50.859][000000010.731] I/user.exsip event: register action: challenge</span><br />
[2026-05-18 18:32:50.865][000000010.732] I/user.sip_callback STATE_INITING register challenge table: 0C7C85D0 nil</span><br />
[2026-05-18 18:32:50.873][000000010.733] I/user.sip_callback 收到认证挑战，继续注册流程</span><br />
[2026-05-18 18:32:50.926][000000010.816] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-18 18:32:50.929][000000010.818] I/user.sip next register in 570 sec</span><br />
[2026-05-18 18:32:50.934][000000010.819] I/user.sip UDP OPTIONS keepalive started, interval 25000 ms</span><br />
[2026-05-18 18:32:50.945][000000010.820] I/user.exsip event: register action: ok</span><br />
[2026-05-18 18:32:50.949][000000010.820] I/user.sip_callback STATE_INITING register ok table: 0C7DB3D0 nil</span><br />
[2026-05-18 18:32:50.954][000000010.821] I/user.sip_callback 注册成功，有效期: 600 SIP响应头: table: 0C7C8118</span><br />
<mark>[2026-05-18 18:32:50.960][000000010.821] I/user.sip_callback STATE_INITING ready nil nil nil</span><br />
[2026-05-18 18:32:50.968][000000010.822] I/user.sip_callback SIP 服务已就绪 当前SIP状态: STATE_INITING</span><br /></mark>
[2026-05-18 18:32:50.973][000000010.823] I/user.sip_app_main_task_func waitMsg STATE_INITING sip_callback MSG_READY nil</span><br />


#### 拨号测试

##### 单击 boot 键拨号

[2026-05-19 12:02:17.816][000000087.020] I/user.sip_app_key 按下BOOT键</span><br />
[2026-05-19 12:02:17.818][000000087.021] I/user.sip_app_main_task_func waitMsg STATE_READY sip_app_key MSG_DIAL 100001</span><br />
[2026-05-19 12:02:17.824][000000087.022] I/user.exsip calling: 100001</span><br />
[2026-05-19 12:02:17.926][000000087.127] I/user.sip_app_main_task_func after process STATE_DIALING</span><br />
[2026-05-19 12:02:17.928][000000087.127] I/user.sip cmd call 100001</span><br />
[2026-05-19 12:02:17.935][000000087.129] I/user.test ip 10.18.1.217</span><br />
[2026-05-19 12:02:17.940][000000087.131] I/user.sip setting call timeout 30 seconds</span><br />
[2026-05-19 12:02:17.946][000000087.134] I/user.sip send INVITE sip:100001@180.152.6.34</span><br />
[2026-05-19 12:02:18.099][000000087.301] I/user.sip resp 407 Proxy Authentication Required from 180.152.6.34 8910</span><br />
[2026-05-19 12:02:18.119][000000087.317] I/user.exsip event: call action: auth_retry</span><br />
[2026-05-19 12:02:18.226][000000087.434] I/user.sip resp 100 Trying from 180.152.6.34 8910</span><br />
[2026-05-19 12:02:18.526][000000087.728] I/user.sip resp 180 Ringing from 180.152.6.34 8910</span><br />
[2026-05-19 12:02:18.528][000000087.731] I/user.sip invite provisional response 180 Ringing</span><br />
[2026-05-19 12:02:18.539][000000087.732] I/user.exsip event: call action: ringing</span><br />
[2026-05-19 12:02:18.545][000000087.733] I/user.sip_callback STATE_DIALING call ringing table: 0C7A2720 nil</span><br />
<mark>[2026-05-19 12:02:18.560][000000087.734] I/user.sip_callback call event sub_event= ringing</span><br />
[2026-05-19 12:02:18.574][000000087.734] I/user.sip_callback 对方响铃中</span><br /></mark>

##### 对方接听，通话建立

[2026-05-19 12:02:41.321][000000110.523] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-19 12:02:41.325][000000110.526] I/user.sip parsing remote SDP v=0</span><br />
o=FreeSWITCH 1779148314 1779148315 IN IP4 180.152.6.34</span><br />
s=FreeSWITCH</span><br />
c=IN IP4 180.152.6.34</span><br />
t=0 0</span><br />
m=audio 15048 RTP/AVP 0 101</span><br />
a=rtpmap:0 PCMU/8000</span><br />
a=rtpmap:101 telephone-event/8000</span><br />
a=fmtp:101 0-15</span><br />
a=ptime:20</span><br />

[2026-05-19 12:02:41.331][000000110.528] I/user.sip stopping all call timers, clearing timeout_timer</span><br />
[2026-05-19 12:02:41.348][000000110.534] I/user.exsip event: media action: ready</span><br />
[2026-05-19 12:02:41.359][000000110.535] I/user.exsip media ready 180.152.6.34 15048 PCMU</span><br />
[2026-05-19 12:02:41.366][000000110.535] I/user.exsip start voip engine with adapter: 1 remote: 180.152.6.34:15048</span><br />
[2026-05-19 12:02:41.373][000000110.537] I/user.exsip voip engine started 180.152.6.34:15048 codec=PCMU adapter nil</span><br />
<mark>[2026-05-19 12:02:41.380][000000110.537] I/user.sip_callback STATE_DIALING media ready table: 0C799CE8 nil</span><br />
[2026-05-19 12:02:41.393][000000110.538] I/user.sip_callback 媒体通道就绪 180.152.6.34:15048</span><br /></mark>
[2026-05-19 12:02:41.407][000000110.538] I/user.sip call established (outgoing)</span><br />
[2026-05-19 12:02:41.420][000000110.539] I/user.exsip event: call action: established</span><br />
[2026-05-19 12:02:41.427][000000110.539] I/user.sip_callback STATE_DIALING call connected table: 0C799608 nil</span><br />
<mark>[2026-05-19 12:02:41.442][000000110.540] I/user.sip_callback call event sub_event= connected</span><br />
[2026-05-19 12:02:41.456][000000110.540] I/user.sip_callback 通话已建立</span><br /></mark>
[2026-05-19 12:02:41.476][000000110.541] I/user.sip_app_main_task_func waitMsg STATE_DIALING sip_callback MSG_CONNECTED nil</span><br />
[2026-05-19 12:02:41.489][000000110.542] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-19 12:02:41.495][000000110.543] I/user.sip_app_key 通话建立成功</span><br />
[2026-05-19 12:02:41.500][000000110.544] D/voip voip task started</span><br />
[2026-05-19 12:02:41.508][000000110.544] D/voip voip start event</span><br />
[2026-05-19 12:02:41.512][000000110.545] E/voip voip config: remote=180.152.6.34:15048 codec=0 ptime=20</span><br />
[2026-05-19 12:02:41.518][000000110.545] E/voip voio origin: samples=8000</span><br />
[2026-05-19 12:02:41.525][000000110.545] E/voip voio frame: samples=160 bytes=320</span><br />
[2026-05-19 12:02:41.530][000000110.553] I/voip aec ready frame=160 tail_ms=200 denoise=1</span><br />
[2026-05-19 12:02:41.536][000000110.562] E/voip udp socket created and connected to 180.152.6.34:15048</span><br />
[2026-05-19 12:02:41.547][000000110.562] luat_i2s_save_old_config 279:i2s1 save old param</span><br />
[2026-05-19 12:02:41.558][000000110.579] E/voip audio started: multimedia_id=0 sample_rate=8000 backend=1</span><br />
[2026-05-19 12:02:41.566][000000110.580] I/user.exsip voip state: started</span><br />
<mark>[2026-05-19 12:02:41.572][000000110.580] I/user.sip_callback STATE_CONNECTED voip state started nil</span><br />
[2026-05-19 12:02:41.590][000000110.581] I/user.sip_callback VoIP状态: started</span><br /></mark>
[2026-05-19 12:02:41.606][000000110.582] I/voip voip running: 180.152.6.34:15048 codec=0 ptime=20</span><br />
<mark>[2026-05-19 12:02:46.379][000000115.579] I/user.sip_callback STATE_CONNECTED voip stats table: 0C798C50 nil</span><br />
[2026-05-19 12:02:46.395][000000115.580] I/user.sip_callback VoIP统计 - 发送: 250 接收: 235 丢失: 0</span><br /></mark>

##### 单击 PWRKEY 键，挂断通话

结束原因为： local_hangup(我方主动挂断)，日志如下：

[2026-05-19 12:02:49.312][000000118.510] I/user.sip_app_key 按下POWERKEY键</span><br />
[2026-05-19 12:02:49.316][000000118.511] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_app_key MSG_HANGUP nil</span><br />
[2026-05-19 12:02:49.321][000000118.512] I/user.exsip hanging up</span><br />
[2026-05-19 12:02:49.328][000000118.512] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-19 12:02:49.334][000000118.513] I/user.sip cmd hangup </span><br />
[2026-05-19 12:02:49.340][000000118.514] I/user.sip BYE uri sip:100001@180.152.6.34:8910;transport=udp from <sip:100000@180.152.6.34>;tag=38642507a004911a to <sip:100001@180.152.6.34>;tag=ta1p23Zar55ja routes 0</span><br />
[2026-05-19 12:02:49.350][000000118.517] I/user.sip send BYE</span><br />
[2026-05-19 12:02:49.407][000000118.608] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-19 12:02:49.415][000000118.611] I/user.exsip event: media action: stop</span><br />
[2026-05-19 12:02:49.421][000000118.612] I/user.exsip voip engine stopping</span><br />
<mark>[2026-05-19 12:02:49.427][000000118.612] I/user.sip_callback STATE_CONNECTED media stop table: 0C794F20 nil</span><br />
[2026-05-19 12:02:49.442][000000118.613] I/user.sip_callback 媒体通道已关闭，关闭原因： local_hangup</span><br /></mark>
[2026-05-19 12:02:49.458][000000118.613] I/user.sip call cleared</span><br />
[2026-05-19 12:02:49.471][000000118.614] I/user.exsip event: call action: ended</span><br />
[2026-05-19 12:02:49.476][000000118.614] I/user.exsip voip engine stopping</span><br />
[2026-05-19 12:02:49.482][000000118.615] I/user.sip_callback STATE_CONNECTED call ended table: 0C794E78 nil</span><br />
<mark>[2026-05-19 12:02:49.498][000000118.615] I/user.sip_callback call event sub_event= ended</span><br />
[2026-05-19 12:02:49.514][000000118.616] I/user.sip_callback 通话已结束，结束原因为： local_hangup 通话对象： table: 0C7A9198</span><br /></mark>
[2026-05-19 12:02:49.531][000000118.617] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_callback MSG_DISCONNECTED local_hangup</span><br />
[2026-05-19 12:02:49.548][000000118.618] I/user.sip_app_main_task_func after process STATE_READY</span><br />
[2026-05-19 12:02:49.553][000000118.618] I/user.sip_app_key 通话已断开</span><br />
[2026-05-19 12:02:49.558][000000118.624] D/voip voip stop event</span><br />
[2026-05-19 12:02:49.566][000000118.625] luat_i2s_load_old_config 297:i2s0 load old param</span><br />
[2026-05-19 12:02:49.571][000000118.628] I/user.exsip voip state: stopped</span><br />
<mark>[2026-05-19 12:02:49.577][000000118.629] I/user.sip_callback STATE_READY voip state stopped nil</span><br />
[2026-05-19 12:02:49.593][000000118.629] I/user.sip_callback VoIP状态: stopped</span><br /></mark>
[2026-05-19 12:02:49.613][000000118.630] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_PLAY_HUNGUP local_hangup</span><br />
[2026-05-19 12:02:49.633][000000118.631] I/user.sip_app_main_task_func after process STATE_READY</span><br />

#### 来电测试

##### 收到来电

[2026-05-19 12:28:29.467][000001658.652] I/user.sip req INVITE from 180.152.6.34 8910</span><br />
[2026-05-19 12:28:29.470][000001658.654] I/user.sip parsing remote SDP v=0</span><br />
o=FreeSWITCH 1779149470 1779149471 IN IP4 180.152.6.34</span><br />
s=FreeSWITCH</span><br />
c=IN IP4 180.152.6.34</span><br />
t=0 0</span><br />
m=audio 15440 RTP/AVP 102 0 8 103 101</span><br />
a=rtpmap:102 opus/48000/2</span><br />
a=fmtp:102 useinbandfec=1; maxaveragebitrate=30000; maxplaybackrate=48000; ptime=20; minptime=10; maxptime=40; stereo=1</span><br />
a=rtpmap:0 PCMU/8000</span><br />
a=rtpmap:8 PCMA/8000</span><br />
a=rtpmap:103 telephone-event/48000</span><br />
a=fmtp:103 0-15</span><br />
a=rtpmap:101 telephone-event/8000</span><br />
a=fmtp:101 0-15</span><br />
a=ptime:20</span><br />

[2026-05-19 12:28:29.485][000001658.664] I/user.exsip event: call action: incoming</span><br />
[2026-05-19 12:28:29.491][000001658.665] I/user.sip_callback STATE_READY call incoming table: 0C7933F0 nil</span><br />
<mark>[2026-05-19 12:28:29.519][000001658.665] I/user.sip_callback call event sub_event= incoming</span><br />
[2026-05-19 12:28:29.544][000001658.666] I/user.sip_callback 来电: "Extension 100001" <sip:100001@180.152.6.34>;tag=SrHecpBa2NH8F sip:100000@10.18.1.217:5062;received=36.7.99.190:5062 <sip:100000@10.18.1.217:5062;received=36.7.99.190:5062>;tag=333567a86744559a</span><br /></mark>
[2026-05-19 12:28:29.578][000001658.667] I/user.exsip event: call action: ringing</span><br />
[2026-05-19 12:28:29.584][000001658.667] I/user.sip_callback STATE_READY call ringing table: 0C793008 nil</span><br />
<mark>[2026-05-19 12:28:29.612][000001658.668] I/user.sip_callback call event sub_event= ringing</span><br />
[2026-05-19 12:28:29.638][000001658.668] I/user.sip_callback 对方响铃中</span><br /></mark>
[2026-05-19 12:28:29.671][000001658.669] I/user.exsip event: media action: offer</span><br />
[2026-05-19 12:28:29.677][000001658.670] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_INCOMING "Extension 100001" <sip:100001@180.152.6.34>;tag=SrHecpBa2NH8F</span><br />
[2026-05-19 12:28:29.718][000001658.777] I/user.sip_app_main_task_func after process STATE_INCOMING</span><br />
[2026-05-19 12:28:29.723][000001658.778] I/user.sip_app_key 呼入中，来电号码： 100001</span><br />
[2026-05-19 12:28:29.728][000001658.794] I/user.sip send OPTIONS ping</span><br />
[2026-05-19 12:28:29.738][000001658.891] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />

##### 单击 boot 键接听来电

[2026-05-19 12:28:37.708][000001666.884] I/user.sip_app_key 按下BOOT键</span><br />
[2026-05-19 12:28:37.715][000001666.884] I/user.sip_app_key 呼入中，接听</span><br />
[2026-05-19 12:28:37.722][000001666.885] I/user.sip_app_main_task_func waitMsg STATE_INCOMING sip_app_key MSG_ACCEPT nil</span><br />
[2026-05-19 12:28:37.728][000001666.886] I/user.exsip answering call</span><br />
[2026-05-19 12:28:37.733][000001666.886] I/user.sip_app_main_task_func after process STATE_INCOMING</span><br />
[2026-05-19 12:28:37.741][000001666.887] I/user.sip cmd answer </span><br />
[2026-05-19 12:28:37.746][000001666.888] I/user.test ip 10.18.1.217</span><br />
[2026-05-19 12:28:37.752][000001666.891] I/user.sip answer 200 OK</span><br />
[2026-05-19 12:28:37.861][000001667.045] I/user.sip req ACK from 180.152.6.34 8910</span><br />
[2026-05-19 12:28:37.877][000001667.048] I/user.exsip event: media action: ready</span><br />
[2026-05-19 12:28:37.882][000001667.048] I/user.exsip media ready 180.152.6.34 15440 PCMU</span><br />
[2026-05-19 12:28:37.893][000001667.049] I/user.exsip start voip engine with adapter: 1 remote: 180.152.6.34:15440</span><br />
[2026-05-19 12:28:37.900][000001667.050] I/user.exsip voip engine started 180.152.6.34:15440 codec=PCMU adapter nil</span><br />
<mark>[2026-05-19 12:28:37.907][000001667.050] I/user.sip_callback STATE_INCOMING media ready table: 0C7A69F0 nil</span><br />
[2026-05-19 12:28:37.935][000001667.051] I/user.sip_callback 媒体通道就绪 180.152.6.34:15440</span><br /></mark>
[2026-05-19 12:28:37.964][000001667.051] I/user.sip call established (incoming)</span><br />
[2026-05-19 12:28:37.976][000001667.052] I/user.exsip event: call action: established</span><br />
[2026-05-19 12:28:37.981][000001667.053] I/user.sip_callback STATE_INCOMING call connected table: 0C7A6180 nil</span><br />
<mark>[2026-05-19 12:28:38.010][000001667.054] I/user.sip_callback call event sub_event= connected</span><br />
[2026-05-19 12:28:38.039][000001667.054] I/user.sip_callback 通话已建立</span><br /></mark>
[2026-05-19 12:28:38.067][000001667.055] I/user.sip_app_main_task_func waitMsg STATE_INCOMING sip_callback MSG_CONNECTED nil</span><br />
[2026-05-19 12:28:38.095][000001667.056] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-19 12:28:38.100][000001667.057] I/user.sip_app_key 通话建立成功</span><br />
[2026-05-19 12:28:38.107][000001667.057] D/voip voip start event</span><br />
[2026-05-19 12:28:38.114][000001667.058] E/voip voip config: remote=180.152.6.34:15440 codec=0 ptime=20</span><br />
[2026-05-19 12:28:38.120][000001667.058] E/voip voio origin: samples=8000</span><br />
[2026-05-19 12:28:38.126][000001667.059] E/voip voio frame: samples=160 bytes=320</span><br />
[2026-05-19 12:28:38.132][000001667.066] I/voip aec ready frame=160 tail_ms=200 denoise=1</span><br />
[2026-05-19 12:28:38.143][000001667.076] E/voip udp socket created and connected to 180.152.6.34:15440</span><br />
[2026-05-19 12:28:38.151][000001667.076] luat_i2s_save_old_config 279:i2s1 save old param</span><br />
[2026-05-19 12:28:38.158][000001667.094] E/voip audio started: multimedia_id=0 sample_rate=8000 backend=1</span><br />
[2026-05-19 12:28:38.166][000001667.095] I/user.exsip voip state: started</span><br />
<mark>[2026-05-19 12:28:38.173][000001667.095] I/user.sip_callback STATE_CONNECTED voip state started nil</span><br />
[2026-05-19 12:28:38.201][000001667.096] I/user.sip_callback VoIP状态: started</span><br /></mark>
[2026-05-19 12:28:38.231][000001667.097] I/voip voip running: 180.152.6.34:15440 codec=0 ptime=20</span><br />
<mark>[2026-05-19 12:28:42.913][000001672.094] I/user.sip_callback STATE_CONNECTED voip stats table: 0C7A5868 nil</span><br />
[2026-05-19 12:28:42.940][000001672.095] I/user.sip_callback VoIP统计 - 发送: 250 接收: 226 丢失: 0</span><br /></mark>

##### 单击 PWRKEY 键，挂断通话

结束原因为： local_hangup(我方主动挂断)，日志如下：

[2026-05-19 12:28:45.442][000001674.618] I/user.sip_app_key 按下POWERKEY键</span><br />
[2026-05-19 12:28:45.444][000001674.619] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_app_key MSG_HANGUP nil</span><br />
[2026-05-19 12:28:45.450][000001674.619] I/user.exsip hanging up</span><br />
[2026-05-19 12:28:45.456][000001674.620] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-19 12:28:45.466][000001674.621] I/user.sip cmd hangup </span><br />
[2026-05-19 12:28:45.474][000001674.622] I/user.sip BYE uri sip:mod_sofia@180.152.6.34:8910 from <sip:100000@10.18.1.217:5062;</span><br />received=36.7.99.190:5062>;tag=333567a86744559a to "Extension 100001" <sip:100001@180.152.6.34>;tag=SrHecpBa2NH8F routes 0</span><br />
[2026-05-19 12:28:45.481][000001674.625] I/user.sip send BYE</span><br />
[2026-05-19 12:28:45.537][000001674.726] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-19 12:28:45.554][000001674.729] I/user.exsip event: media action: stop</span><br />
[2026-05-19 12:28:45.560][000001674.729] I/user.exsip voip engine stopping</span><br />
<mark>[2026-05-19 12:28:45.567][000001674.730] I/user.sip_callback STATE_CONNECTED media stop table: 0C7B0358 nil</span><br /></span><br />
[2026-05-19 12:28:45.596][000001674.730] I/user.sip_callback 媒体通道已关闭，关闭原因： local_hangup</span><br /></mark>
[2026-05-19 12:28:45.627][000001674.731] I/user.sip call cleared</span><br />
[2026-05-19 12:28:45.639][000001674.732] I/user.exsip event: call action: ended</span><br />
[2026-05-19 12:28:45.645][000001674.733] I/user.exsip voip engine stopping</span><br />
[2026-05-19 12:28:45.651][000001674.733] I/user.sip_callback STATE_CONNECTED call ended table: 0C7B0268 nil</span><br />
<mark>[2026-05-19 12:28:45.681][000001674.734] I/user.sip_callback call event sub_event= ended</span><br />
[2026-05-19 12:28:45.713][000001674.734] I/user.sip_callback 通话已结束，结束原因为： local_hangup 通话对象： table: 0C779AD0</span><br /></mark>
[2026-05-19 12:28:45.751][000001674.736] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_callback MSG_DISCONNECTED local_hangup</span><br />
[2026-05-19 12:28:45.783][000001674.737] I/user.sip_app_main_task_func after process STATE_READY</span><br />
[2026-05-19 12:28:45.789][000001674.737] I/user.sip_app_key 通话已断开</span><br />
[2026-05-19 12:28:45.794][000001674.740] D/voip voip stop event</span><br />
[2026-05-19 12:28:45.803][000001674.741] luat_i2s_load_old_config 297:i2s0 load old param</span><br />
[2026-05-19 12:28:45.808][000001674.743] I/user.exsip voip state: stopped</span><br />
<mark>[2026-05-19 12:28:45.815][000001674.744] I/user.sip_callback STATE_READY voip state stopped nil</span><br />
[2026-05-19 12:28:45.850][000001674.744] I/user.sip_callback VoIP状态: stopped</span><br /></mark>
[2026-05-19 12:28:45.882][000001674.745] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_PLAY_HUNGUP local_hangup</span><br />
[2026-05-19 12:28:45.915][000001674.746] I/user.sip_app_main_task_func after process STATE_READY</span><br />

#### 通话保持测试

##### 收到来电

[2026-05-18 18:36:28.788][000000228.679] I/user.sip req INVITE from 180.152.6.34 8910</span><br />
[2026-05-18 18:36:28.803][000000228.681] I/user.sip parsing remote SDP v=0</span><br />
o=FreeSWITCH 1779084963 1779084964 IN IP4 180.152.6.34</span><br />
s=FreeSWITCH</span><br />
c=IN IP4 180.152.6.34</span><br />
t=0 0</span><br />
m=audio 15626 RTP/AVP 8 0 101</span><br />
a=rtpmap:8 PCMA/8000</span><br />
a=rtpmap:0 PCMU/8000</span><br />
a=rtpmap:101 telephone-event/8000</span><br />
a=fmtp:101 0-15</span><br />
a=ptime:20</span><br />

[2026-05-18 18:36:28.811][000000228.692] I/user.exsip event: call action: incoming</span><br />
[2026-05-18 18:36:28.816][000000228.692] I/user.sip_callback STATE_READY call incoming table: 0C7E2BD0 nil</span><br />
<mark>[2026-05-18 18:36:28.825][000000228.693] I/user.sip_callback call event sub_event= incoming</span><br />
[2026-05-18 18:36:28.835][000000228.693] I/user.sip_callback 来电: "Extension 100001" <sip:100001@180.152.6.34>;tag=SSy8D698NKK7K sip:100000@10.19.168.88:5062;received=36.7.99.179:5062 <sip:100000@10.19.168.88:5062;received=36.7.99.179:5062>;tag=6375ca298dc28a56</span><br /></span><br /></mark>
[2026-05-18 18:36:28.846][000000228.694] I/user.exsip event: call action: ringing</span><br />
[2026-05-18 18:36:28.850][000000228.695] I/user.sip_callback STATE_READY call ringing table: 0C7E2888 nil</span><br />
<mark>[2026-05-18 18:36:28.857][000000228.695] I/user.sip_callback call event sub_event= ringing</span><br />
[2026-05-18 18:36:28.867][000000228.696] I/user.sip_callback 对方响铃中</span><br /></mark>
[2026-05-18 18:36:28.879][000000228.697] I/user.exsip event: media action: offer</span><br />
[2026-05-18 18:36:28.884][000000228.698] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_INCOMING "Extension 100001" <sip:100001@180.152.6.34>;tag=SSy8D698NKK7K</span><br />
[2026-05-18 18:36:28.926][000000228.803] I/user.sip_app_main_task_func after process STATE_INCOMING</span><br />
[2026-05-18 18:36:28.928][000000228.804] I/user.sip_app_key 呼入中，来电号码： 100001</span><br />

##### 单击 boot 键接听来电

[2026-05-18 18:36:36.417][000000236.299] I/user.sip_app_key 按下BOOT键</span><br />
[2026-05-18 18:36:36.431][000000236.299] I/user.sip_app_key 呼入中，接听</span><br />
[2026-05-18 18:36:36.443][000000236.300] I/user.sip_app_main_task_func waitMsg STATE_INCOMING sip_app_key MSG_ACCEPT nil</span><br />
[2026-05-18 18:36:36.455][000000236.301] I/user.exsip answering call</span><br />
[2026-05-18 18:36:36.469][000000236.301] I/user.sip_app_main_task_func after process STATE_INCOMING</span><br />
[2026-05-18 18:36:36.481][000000236.302] I/user.sip cmd answer </span><br />
[2026-05-18 18:36:36.494][000000236.303] I/user.test ip 10.19.168.88</span><br />
[2026-05-18 18:36:36.510][000000236.306] I/user.sip answer 200 OK</span><br />
[2026-05-18 18:36:36.526][000000236.397] I/user.sip req ACK from 180.152.6.34 8910</span><br />
[2026-05-18 18:36:36.571][000000236.400] I/user.exsip event: media action: ready</span><br />
[2026-05-18 18:36:36.585][000000236.400] I/user.exsip media ready 180.152.6.34 15626 PCMU</span><br />
[2026-05-18 18:36:36.597][000000236.401] I/user.exsip start voip engine with adapter: 1 remote: 180.152.6.34:15626</span><br />
[2026-05-18 18:36:36.609][000000236.402] I/user.exsip voip engine started 180.152.6.34:15626 codec=PCMU adapter nil</span><br />
<mark>[2026-05-18 18:36:36.621][000000236.402] I/user.sip_callback STATE_INCOMING media ready table: 0C797F28 nil</span><br />
[2026-05-18 18:36:36.644][000000236.403] I/user.sip_callback 媒体通道就绪 180.152.6.34:15626</span><br /></mark>
[2026-05-18 18:36:36.668][000000236.403] I/user.sip call established (incoming)</span><br />
[2026-05-18 18:36:36.698][000000236.404] I/user.exsip event: call action: established</span><br />
[2026-05-18 18:36:36.711][000000236.405] I/user.sip_callback STATE_INCOMING call connected table: 0C7976B8 nil</span><br />
<mark>[2026-05-18 18:36:36.731][000000236.405] I/user.sip_callback call event sub_event= connected</span><br />
[2026-05-18 18:36:36.756][000000236.406] I/user.sip_callback 通话已建立</span><br /></mark>
[2026-05-18 18:36:36.778][000000236.407] I/user.sip_app_main_task_func waitMsg STATE_INCOMING sip_callback MSG_CONNECTED nil</span><br />
[2026-05-18 18:36:36.801][000000236.407] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-18 18:36:36.812][000000236.408] I/user.sip_app_key 通话建立成功</span><br />
[2026-05-18 18:36:36.825][000000236.409] D/voip voip task started</span><br />
[2026-05-18 18:36:36.838][000000236.409] D/voip voip start event</span><br />
[2026-05-18 18:36:36.851][000000236.410] E/voip voip config: remote=180.152.6.34:15626 codec=0 ptime=20</span><br />
[2026-05-18 18:36:36.862][000000236.410] E/voip voio origin: samples=8000</span><br />
[2026-05-18 18:36:36.875][000000236.411] E/voip voio frame: samples=160 bytes=320</span><br />
[2026-05-18 18:36:36.887][000000236.418] I/voip aec ready frame=160 tail_ms=200 denoise=1</span><br />
[2026-05-18 18:36:36.901][000000236.426] E/voip udp socket created and connected to 180.152.6.34:15626</span><br />
[2026-05-18 18:36:36.913][000000236.427] luat_i2s_save_old_config 279:i2s1 save old param</span><br />
[2026-05-18 18:36:36.925][000000236.444] E/voip audio started: multimedia_id=0 sample_rate=8000 backend=1</span><br />
[2026-05-18 18:36:36.937][000000236.445] I/user.exsip voip state: started</span><br />
<mark>[2026-05-18 18:36:36.951][000000236.445] I/user.sip_callback STATE_CONNECTED voip state started nil</span><br />
[2026-05-18 18:36:36.974][000000236.446] I/user.sip_callback VoIP状态: started</span><br /></mark>
[2026-05-18 18:36:36.997][000000236.446] I/voip voip running: 180.152.6.34:15626 codec=0 ptime=20</span><br />
<mark>[2026-05-18 18:36:41.557][000000241.444] I/user.sip_callback STATE_CONNECTED voip stats table: 0C796D90 nil</span><br />
[2026-05-18 18:36:41.583][000000241.445] I/user.sip_callback VoIP统计 - 发送: 250 接收: 233 丢失: 0</span><br /></mark>


##### 接听过程中连接网线，通话依旧持续进行

[2026-05-18 18:43:10.826][000000630.711] I/netdrv.ch390x link is up 1 12 100M</span><br />
[2026-05-18 18:43:10.835][000000630.711] D/netdrv 网卡(4)设置为UP</span><br />
[2026-05-18 18:43:10.884][000000630.769] D/ulwip adapter 4 dhcp start netif c101490</span><br />
[2026-05-18 18:43:10.886][000000630.769] D/DHCP dhcp discover DC326261779E</span><br />
[2026-05-18 18:43:10.891][000000630.769] I/ulwip adapter 4 dhcp payload len 282</span><br />
[2026-05-18 18:43:10.944][000000630.828] D/ulwip 收到DHCP数据包(len=300)</span><br />
[2026-05-18 18:43:10.946][000000630.828] D/DHCP find ip 6401a8c0 192.168.1.100</span><br />
[2026-05-18 18:43:10.951][000000630.828] D/DHCP result 2</span><br />
[2026-05-18 18:43:10.957][000000630.828] D/DHCP got offer, send request</span><br />
[2026-05-18 18:43:10.962][000000630.829] I/ulwip adapter 4 dhcp payload len 328</span><br />
[2026-05-18 18:43:10.966][000000630.836] D/ulwip 收到DHCP数据包(len=300)</span><br />
[2026-05-18 18:43:10.972][000000630.836] D/DHCP find ip 6401a8c0 192.168.1.100</span><br />
[2026-05-18 18:43:10.976][000000630.836] D/DHCP result 5</span><br />
[2026-05-18 18:43:10.981][000000630.836] D/DHCP DHCP acquired IP 192.168.1.100</span><br />
[2026-05-18 18:43:10.985][000000630.836] D/ulwip adapter 4 ip 192.168.1.100</span><br />
[2026-05-18 18:43:10.991][000000630.836] D/ulwip adapter 4 mask 255.255.255.0</span><br />
[2026-05-18 18:43:10.996][000000630.836] D/ulwip adapter 4 gateway 192.168.1.1</span><br />
[2026-05-18 18:43:11.002][000000630.836] D/ulwip adapter 4 lease_time 7200s</span><br />
[2026-05-18 18:43:11.010][000000630.836] D/ulwip adapter 4 DNS1:192.168.1.1</span><br />
[2026-05-18 18:43:11.014][000000630.837] D/net network ready 4, setup dns server</span><br />
[2026-05-18 18:43:11.019][000000630.838] D/netdrv IP_READY 4 192.168.1.100</span><br />
[2026-05-18 18:43:11.027][000000630.839] I/user.exsip IP_READY 192.168.1.100 4</span><br />
[2026-05-18 18:43:11.031][000000630.839] I/user.dnsproxy 开始监听</span><br />
[2026-05-18 18:43:11.040][000000630.840] I/user.ip_ready_handle 192.168.1.100 Ethernet state 3 gw 192.168.1.1</span><br />
[2026-05-18 18:43:11.046][000000630.841] I/user.eth_ping_ip nil wifi_ping_ip nil</span><br />
[2026-05-18 18:43:11.052][000000630.841] I/user.sip IP_READY 4</span><br />
[2026-05-18 18:43:11.197][000000631.082] I/user.sip send OPTIONS ping</span><br />
[2026-05-18 18:43:11.271][000000631.157] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-18 18:43:11.452][000000631.339] I/user.Ethernet网卡开始PING</span><br />
[2026-05-18 18:43:11.455][000000631.339] I/user.dns_request Ethernet true</span><br />
[2026-05-18 18:43:11.459][000000631.341] D/net adapter 4 connect 223.5.5.5:80 TCP</span><br />
[2026-05-18 18:43:11.486][000000631.369] I/http http close c192a08</span><br />
[2026-05-18 18:43:11.488][000000631.371] I/user.Ethernet网卡httpdns域名解析成功</span><br />
[2026-05-18 18:43:11.494][000000631.372] I/user.httpdns baidu.com 124.237.177.164</span><br />
[2026-05-18 18:43:11.498][000000631.373] I/user.设置网卡 Ethernet</span><br />
[2026-05-18 18:43:11.507][000000631.373] D/net 设置DNS服务器 id 4 index 0 ip 223.5.5.5</span><br />
[2026-05-18 18:43:11.514][000000631.375] D/net 设置DNS服务器 id 4 index 1 ip 114.114.114.114</span><br />
[2026-05-18 18:43:11.520][000000631.375] I/user.netdrv_multiple_notify_cbfunc use new adapter Ethernet 4</span><br />
[2026-05-18 18:43:11.526][000000631.376] I/user.exnetif publish network status Ethernet 4</span><br />
[2026-05-18 18:43:11.532][000000631.377] dft adapter change from 1 to 4</span><br />
<mark>[2026-05-18 18:43:13.726][000000633.611] I/user.sip_callback STATE_CONNECTED voip stats table: 0C784700 nil</span><br />
[2026-05-18 18:43:13.743][000000633.611] I/user.sip_callback VoIP统计 - 发送: 500 接收: 483 丢失: 0</span><br /></mark>

##### 单击 PWRKEY 键，挂断通话

通话结束，结束原因为： local_hangup(我方主动挂断)，日志如下：

[2026-05-18 18:43:18.724][000000638.608] I/user.sip_app_key 按下POWERKEY键</span><br />
[2026-05-18 18:43:18.726][000000638.609] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_app_key MSG_HANGUP nil</span><br />
[2026-05-18 18:43:18.731][000000638.610] I/user.exsip hanging up</span><br />
[2026-05-18 18:43:18.735][000000638.610] I/user.sip_app_main_task_func after process STATE_CONNECTED</span><br />
[2026-05-18 18:43:18.740][000000638.611] I/user.sip cmd hangup </span><br />
[2026-05-18 18:43:18.748][000000638.612] I/user.sip BYE uri sip:mod_sofia@180.152.6.34:8910 from <sip:100000@10.19.168.88:5062;received=36.7.99.179:5062>;tag=a14e0e45c17bc34a to "Extension 100001" <sip:100001@180.152.6.34>;tag=H89XHBvj3yv7a routes 0</span><br />
[2026-05-18 18:43:18.755][000000638.615] I/user.sip send BYE</span><br />
[2026-05-18 18:43:18.761][000000638.620] I/user.sip_callback STATE_CONNECTED voip stats table: 0C783488 nil</span><br />
[2026-05-18 18:43:18.780][000000638.621] I/user.sip_callback VoIP统计 - 发送: 750 接收: 731 丢失: 0</span><br />
[2026-05-18 18:43:18.848][000000638.733] I/user.sip resp 200 OK from 180.152.6.34 8910</span><br />
[2026-05-18 18:43:18.866][000000638.735] I/user.exsip event: media action: stop</span><br />
[2026-05-18 18:43:18.872][000000638.736] I/user.exsip voip engine stopping</span><br />
[2026-05-18 18:43:18.876][000000638.737] I/user.sip_callback STATE_CONNECTED media stop table: 0C782488 nil</span><br />
[2026-05-18 18:43:18.915][000000638.737] I/user.sip_callback 媒体通道已关闭，关闭原因： local_hangup</span><br />
[2026-05-18 18:43:18.935][000000638.738] I/user.sip call cleared</span><br />
[2026-05-18 18:43:18.944][000000638.739] I/user.exsip event: call action: ended</span><br />
[2026-05-18 18:43:18.952][000000638.740] I/user.exsip voip engine stopping</span><br />
[2026-05-18 18:43:18.956][000000638.741] I/user.sip_callback STATE_CONNECTED call ended table: 0C782398 nil</span><br />
<mark>[2026-05-18 18:43:18.975][000000638.741] I/user.sip_callback call event sub_event= ended</span><br />
[2026-05-18 18:43:18.994][000000638.741] I/user.sip_callback 通话已结束，结束原因为： local_hangup 通话对象： table: 0C791180</span><br /></mark>
[2026-05-18 18:43:19.019][000000638.743] I/user.sip_app_main_task_func waitMsg STATE_CONNECTED sip_callback MSG_DISCONNECTED local_hangup</span><br />
[2026-05-18 18:43:19.036][000000638.743] I/user.sip_app_main_task_func after process STATE_READY</span><br />
[2026-05-18 18:43:19.041][000000638.744] I/user.sip_app_key 通话已断开</span><br />
[2026-05-18 18:43:19.045][000000638.745] D/voip voip stop event</span><br />
[2026-05-18 18:43:19.051][000000638.746] luat_i2s_load_old_config 297:i2s0 load old param</span><br />
[2026-05-18 18:43:19.055][000000638.748] I/user.exsip voip state: stopped</span><br />
<mark>[2026-05-18 18:43:19.060][000000638.749] I/user.sip_callback STATE_READY voip state stopped nil</span><br />
[2026-05-18 18:43:19.081][000000638.749] I/user.sip_callback VoIP状态: stopped</span><br /></mark>
[2026-05-18 18:43:19.100][000000638.750] I/user.sip_app_main_task_func waitMsg STATE_READY sip_callback MSG_PLAY_HUNGUP local_hangup</span><br />

注意：多网融合情况下的 SIP 通话测试，只有在非/来电/拨号/通话状态下，才会切换到高优先级的网卡重新注册

## **七、 总结**

至此，我们通过 Air8000A 演示了在不同网络状态下的拨号，来电、通话、网络切换通话保持全过程，动手试一试吧：

1. **来电**：来电时播报来电号码，单击 boot 键接听，单击 PWRKEY 拒接
2. **拨号**：在无来电的情况下，单击 boot 拨号，拨号过程中可以单击 PWRKEY 取消拨号
3. **网络切换通话保持**：通话过程中出现网络切换不影响通话
