# **SIP DEMO 项目说明（Air8201H）**

## **一、项目概述**

Air8201H 基于 Air780EHM 模组，BTB扩展板未引出SPI接口，不支持以太网联网，仅支持4G联网方式。

SIP DEMO 项目是一个基于 Air8201H 开发板的 SIP 通话演示项目，通过 Air8201H 开发板实现 SIP 通话功能，仅支持 4G 单网卡联网方式。

### **文件结构**

```lua
sip/Air8201H/
├── main.lua：主程序入口，加载网络驱动模块、SIP通话模块和按键处理
├── sip_app/
│   ├── sip_app_main.lua：sip主入口;
│   ├── sip_app_key.lua：按键相关处理;
├── netdrv/
│   ├── netdrv_4g.lua：4g网络模块
├── netdrv_device.lua：网络设备驱动模块，仅加载4G网卡驱动
├── audio_drv.lua: 管理音频设备初始化与控制
├── tts_speaker.lua：语音播报
```

## **二、演示功能概述**

1. 单网卡测试 sip 功能：4g 联网测试 sip 功能

**注意**：Air8201H 不支持以太网联网，因此仅提供4G单网卡测试场景。

本文使用 Air8201H 开发板，演示 4g 联网测试 sip 功能。

### **场景一：4g 单网卡联网测试**

1. **网络设备驱动模块**：根据选择的网络类型在 **netdrv_device.lua** 文件中加载对应的网络驱动，这里选择 4g 驱动（require "netdrv_4g"）。
2. **音频设备初始化与控制**：使用 exaudio.setup 统一配置 ES8311 音频编解码芯片和扬声器功放，包括 I2C、I2S 接口设置及音量控制。
3. **拨号/接听**：在无来电的情况下，单击 boot 键进行拨号；收到来电，单击 boot 键进行接听
4. **挂断**：来电/拨号/通话过程中，单击 PWRKEY 键进行挂断

## **三、准备硬件环境**

参考：[硬件环境清单第二章节内容](https://docs.openluat.com/air780ehv/luatos/common/hwenv/)，准备，并组装好硬件环境。

1. Air8201H 开发板一块 +SIM 卡一张 +4g 天线一根，所有硬件环境组装好，实际测试根据需要进行，具体可以参考"演示核心步骤"中的对应操作。
2. TYPE-C USB 数据线一根，Air8201H 开发板和数据线的硬件接线方式为：

- Air8201H 开发板通过 TYPE-C USB 口供电；
- TYPE-C USB 数据线直接插到核心板的 TYPE-C USB 座子，另外一端连接电脑 USB 口；

**注意**：Air8201H 不支持以太网，无需连接网线。

![](https://docs.openluat.com/air780ehv/luatos/app/multimedia/sip/image/sip_Air780EHV.png)

## **四、准备软件环境**

### **4.1 工具 + 内核固件 + 脚本**

1、Luatools 下载调试工具

2、[Air8201H固件](https://docs.openluat.com/air780epm/luatos/firmware/version/#air780ehmluatos)

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
sip/Air8201H/
├── main.lua：主程序入口，加载网络驱动模块、SIP通话模块和按键处理
├── sip_app/
│   ├── sip_app_main.lua：sip主入口;
│   ├── sip_app_key.lua：按键相关处理;
├── netdrv/
│   ├── netdrv_4g.lua：4g网络模块
├── netdrv_device.lua：网络设备驱动模块，仅加载4G网卡驱动
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

**注意**：Air8201H 不支持以太网和多网卡测试场景。

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
o=FreeSWITCH 1779145202 1779145203 IN IP4 180.152.6.34
s=FreeSWITCH
c=IN IP4 180.152.6.34
t=0 0
m=audio 16780 RTP/AVP 8 0 101
a=rtpmap:8 PCMA/8000
a=rtpmap:0 PCMU/8000
a=rtpmap:101 telephone-event/8000
a=fmtp:101 0-15
a=ptime:20

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
[2026-05-19 11:39:51.998][000000061.380] E/voip voio origin: samples=8000</span><br />
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