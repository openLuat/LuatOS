## 功能模块介绍

1、main.lua：主程序入口，加载网络驱动与 SIP、语音业务模块；

2、config.lua：项目集中配置，包含 SIP 服务器与账号、1103 音频参数、默认拨号目标；

3、netdrv_4g.lua / netdrv_device.lua：4G 网络驱动，通过蜂窝网卡建立数据通道；

4、sip_app_main.lua：SIP 注册 / 呼出 / 接听 / 挂断状态机，媒体由 audio_drv 的桥接层提供；

5、sip_app_voice.lua：Air1103 离线语音识别模块，识别"接听电话""挂断电话"并转为接听 / 挂断指令；

6、audio_drv.lua：Air1103 音频初始化及 SIP PCM 适配，基于 exaudio 完成播放、air1103 直接采集 MIC。

## 演示功能概述

1、SIP 注册与双向通话：

- 设备开机后向 SIP 服务器（默认 cc.luatos.com:8910）注册；
- 注册成功进入 READY 状态，可呼出或接听；
- 通话采用 Audio V2 PCM 桥接，麦克风经 1103 采集、重采样后与 VoIP 互通。

2、语音接听：

- 电脑或话机呼入后设备进入 INCOMING 状态并振铃；
- 直接对 1103 说"接听电话"（兼容"接通电话"），识别后自动接听并进入 CONNECTED。

3、语音挂断：

- 通话中任意时刻对 1103 说"挂断电话"，识别后自动挂断。

4、Air1103 离线语音识别：

- 采用外挂 Air1103 语音芯片（固件 V1.1.8 及以上）；
- 支持免唤醒词指令，无需先说"你好小智"；
- 识别仅注册 on_identify 回调，与麦克风上行互不干扰。

## 演示硬件环境

1、Air8784 整机（Air780EHM 主控 + 外挂 Air1103 语音芯片）：

2、硬件接口说明：

- Air1103 通过 UART1 与主控通信，波特率 2M；
- 1103 电源由主控 GPIO22 控制（高电平开启）；
- 插入带流量的 4G SIM 卡，网络数据走蜂窝网卡。

## 演示软件环境

1、Luatools 下载调试工具；

2、Air8784固件要求：

- 编写demo时使用固件的是 `LuatOS-SoC_V2054_Air780EHV_13.soc` ；
- 测试时请选择版本≥V2054的固件 [Air8784 固件](https://docs.openluat.com/air780ehm/luatos/firmware/version/)

3、Air1103固件要求:

- Air1103需使用 `LM_701_AEC_UART_PCM_PCM_linein-spk_OSC_KEY03_HeZhou-V1.1.8.fw` 固件才能支持"接听电话"和"挂断电话"两个指令；
- demo烧录到模组，上电初始化后可以直接对Air8784整机喊"接听电话"和"挂断电话"，看是否有对应的日志打印来判断1103固件是否支持这两个指令。

## 演示核心步骤

1、修改 config.lua：

- 确认 sip_server_addr / sip_username / sip_password 已填写；
- 默认 sip_username = imei().."0"，对方账号即为 imei().."0"；
- 拨号目标 dial_number 改成对端分机号（如 imei().."1" 仅作占位，需改成真实账号）；
- 确认 audio.uart_id=1、audio.power_gpio=22 与板子实际接法一致。

2、使用 Luatools 烧录内核固件与 demo 脚本；

3、烧录后设备自动开机，等待 SIP 注册（日志出现 STATE READY）；

4、用电脑或话机呼叫本机账号，待振铃后说"接听电话"完成接听；

5、通话中随时说"挂断电话"完成挂断。

## 运行日志示例

```log
I/user.sip_app_voice 语音接听/挂断已启用：当前V1.1.8固件无需使用唤醒词，直接说[接听电话]或[挂断电话]即可触发语音指令
I/user.sip_app STATE READY
I/user.exsip event: call action: incoming
I/user.sip_app CALL incoming
I/user.sip_app STATE INCOMING
I/user.sip_app_voice Air1103识别到: 接听电话
I/user.sip_app_voice >>> 语音指令[接听电话]
I/user.exsip answering call
I/user.sip_app STATE ANSWERING
I/user.sip_app CALL connected
I/user.sip_app STATE CONNECTED
I/user.sip_app_voice Air1103识别到: 挂断电话
I/user.sip_app_voice >>> 语音指令[挂断电话]
I/user.exsip hanging up
I/user.sip_app STATE HANGING_UP
I/user.sip_app CALL ended
I/user.sip_app STATE READY
```

通过 Luatools 工具，可以查看设备的运行日志，确认语音指令的识别与通话状态切换。
