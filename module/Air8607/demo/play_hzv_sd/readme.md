## 功能模块介绍

本 demo 演示在 **Air8607 整机**（Air1603 主控 + 10 寸 1024×600 RGB 屏）上**触摸点选**播放
**SD 卡（TF 卡）里的 HZV 音视频文件**。

HZV 是合宙嵌入式音视频格式，把 MJPEG 视频、MP3/PCM 音频、时间戳和索引封装在同一个 `.hzv`
文件里，解复用、解码和音画同步全部由底层引擎完成，Lua 侧只负责播放控制。HZV 格式说明详见：
https://docs.openluat.com/protocols/hzv/

素材全部放在 TF 卡上，不需要占用模块的内置文件系统（luadb）分区，卡里放多少素材都可以。
开机后屏幕上先出现素材清单，点文件名播放，播放中点"返回列表"按钮回到清单再选。

项目分为以下核心模块：

1、main.lua：主程序入口，初始化看门狗，按顺序调度 屏幕初始化 → 触摸初始化 → TF 卡挂载 →
   扫描素材 → 列出素材清单 → 点亮背光，并处理选片与返回两条系统消息

2、lcd_app.lua：LCD 显示初始化模块，压灭背光、用 display 库初始化 RGB 屏、刷黑整屏、
   初始化 AirUI、加载中文字库

3、tp_app.lua：触摸初始化模块，初始化 I2C1 与 GT911、绑定到 AirUI、补回触摸总线配置

4、sd_app.lua：TF 卡模块，初始化 SPI1、拉高 SD_EN 供电、挂载 FAT32 到 `/sd`、列举卡上的 `*.hzv`

5、file_list.lua：素材选择列表页模块，建全屏清单、列出素材行、触摸点选发消息

6、hzv_player.lua：HZV 播放引擎模块，创建 `airui.video` 组件、控制功放与音量、
   控制播放进度与返回、打印播放统计

## 系统消息介绍

模块之间用两条系统消息传递页面切换，发送方与接收方互不 require，避免循环依赖：

| 消息名 | 参数 | 发送方 | 含义 |
| --- | --- | --- | --- |
| `HZV_PLAY_REQ` | `index` 素材序号 | file_list.lua | 点素材行发 `index>=1`，点"顺序播放全部"发 `index=0` |
| `HZV_BACK_REQ` | 无 | hzv_player.lua | 点返回按钮、点画面、播放结束时发，回到素材清单 |

接收方是 main.lua，用 `sys.subscribe` 订阅后做页面切换：起播前 `file_list.hide()`，
返回时 `hzv_player.stop()` + `file_list.show()`。

## 对外接口介绍

1、`lcd_app.init()`：初始化屏幕、AirUI 与中文字库（背光保持熄灭），成功返回 `true`

2、`lcd_app.backlight_on()`：点亮背光，幂等，可重复调用

3、`lcd_app.get_size()`：返回屏幕分辨率 `width, height`

4、`tp_app.init()`：初始化 GT911 触摸屏并绑定到 AirUI，成功返回 `true`

5、`tp_app.i2c_restore()`：立即补回触摸 I2C 总线配置

6、`tp_app.recover(delay_ms)`：延迟一发补回触摸 I2C 总线配置，不传延迟用 300ms

7、`sd_app.mount()`：挂载 TF 卡到 `/sd`，成功返回 `true`

8、`sd_app.unmount()`：卸载 `/sd` 并关闭 SPI 总线

9、`sd_app.is_mounted()`：查询 TF 卡是否已挂载

10、`sd_app.list_hzv()`：返回 `/sd` 根目录下的 HZV 素材列表 `{ {path=, name=, size=}, ... }`，
    按文件名升序排列

11、`file_list.init(files)`：按素材列表建出全屏选择页

12、`file_list.show()`：显示素材选择页

13、`file_list.hide()`：隐藏素材选择页，给视频让出画面

14、`hzv_player.set_playlist(files)`：保存素材列表

15、`hzv_player.play_one(index)`：只播第 `index` 条，播完回到清单

16、`hzv_player.play_all()`：从第一条开始顺序轮播整张表，轮完回到清单

17、`hzv_player.stop()`：停止播放，销毁视频组件与返回按钮并关闭功放

18、`hzv_player.stats()`：返回 `video:get_stats()` 的结果，没有播放时返回 `nil`

## 演示功能概述

### 1、主程序入口模块（main.lua）

按固定顺序完成一次开机流程：

1. `lcd_app.init()` 初始化屏幕、AirUI 与中文字库，失败直接退出（此时什么都显示不了）；
2. `tp_app.init()` 初始化触摸屏，失败只留日志，清单还在但点不动；
3. `sd_app.mount()` 挂载 TF 卡，`sd_app.list_hzv()` 扫描卡上的 `*.hzv`；
4. `hzv_player.set_playlist(files)` 保存播放列表；
5. `file_list.init(files)` + `file_list.show()` 列出素材清单；
6. `sys.wait(200)` 之后 `lcd_app.backlight_on()` 点亮背光，开机过程不出现花屏。

开机之后由两条系统消息驱动：`HZV_PLAY_REQ` 起播，`HZV_BACK_REQ` 回清单。

### 2、LCD 显示模块（lcd_app.lua）

顺序固定为「压灭背光 → 初始化屏 → 刷黑 → 初始化 AirUI → 加载字库 → 最后点灯」：

1. `pwm.setup(PWM_BACKLIGHT_CH, PWM_BACKLIGHT_FREQ, 0)` + `pwm.start`，背光占空比 0；
2. `display.init("custom", {...})` 初始化 1024×600 RGB 屏，`pin_rst = GPIO15`；
3. `display.getSize()` 取真实分辨率，`display.fill` 刷黑整屏；
4. `airui.init(width, height)` 初始化 AirUI；
5. `airui.font_load({type="hzfont", ...})` 加载固件内置中文矢量字库，
   不加载则清单上的中文全部显示成方块；
6. `backlight_on()` 把 PWM3 占空比设到 `PWM_BACKLIGHT_DUTY`。

RGB 屏的帧缓冲由显示控制器持续扫描输出，上电时显存里是随机内容，背光一旦提前点亮就会看到
花屏/白屏，所以整个初始化过程背光保持熄灭。

### 3、触摸模块（tp_app.lua）

1. `i2c.setup(1, 0, true)` 初始化 I2C1，第三参 `true` 是轮询模式；
2. `tp.init("gt911", param)` 初始化 GT911，参数里带 `port=1`、`pin_rst=14`、`pin_int=51`、
   `int_type=tp.FALLING`、`w=1024`、`h=600`；
3. `airui.device_bind_touch(device)` 把触摸设备绑定到 AirUI，绑定之后按钮的 `on_click` 才会触发；
4. `i2c_restore()` 按同样的端口、速率、轮询模式再调一次 `i2c.setup`。

内核 tp 库一次上电只接受一次 `tp.init`，重复调用返回 `nil` 并打印 `tp has been initialized`，
所以本模块只认首次成功，之后只补总线配置。

### 4、TF 卡模块（sd_app.lua）

1. `gpio.setup(SD_PIN_EN, 1)` 拉高 GPIO74 给 TF 卡供电；
2. `spi.setup(SD_SPI_ID, ...)` 以 400kHz 低速初始化 SPI1，`gpio.setup(SD_PIN_CS, 1)` 先拉高片选；
3. `fatfs.mount(fatfs.SPI, "/sd", ...)` 挂载到 `/sd`，时钟 20MHz，挂载失败不自动格式化；
4. `fatfs.getfree("/sd")` 打印卡容量，确认卡被正确识别；
5. `list_hzv()` 用 `io.lsdir` 列举 `/sd` 根目录的普通文件，只保留扩展名为 `.hzv` 的条目。

### 5、素材选择列表页（file_list.lua）

1. 建一个 1024×600 的全屏容器做清单页底，放标题、提示文字、"顺序播放全部"按钮；
2. 建素材列表容器，每条素材一行 `airui.button`，按钮文字是 `序号 + 文件名`；
3. 行数超出列表容器高度时上下滑动翻看，列表容器自带滚动条；
4. 点素材行发 `HZV_PLAY_REQ` 消息，序号就是该行在列表里的位置；
5. 点"顺序播放全部"发 `HZV_PLAY_REQ` 消息，序号固定为 0；
6. `show()` / `hide()` 用 `set_hidden` 切换整页显隐。

所有素材行共用一个具名点击回调，回调里用按钮文字反查素材序号，所以不需要给每一行单独造回调函数。

### 6、HZV 播放引擎（hzv_player.lua）

1. `videoplayer.open / info / close` 探测素材的真实分辨率；
2. 按屏幕尺寸居中计算组件位置，`airui.video` 不支持缩放，素材比屏幕大时按屏幕裁上限；
3. 创建组件：`format="hzv"`、`backend="videoplayer"`、`decode_mode="hw"`、`loop=false`、
   `auto_play=false`、`on_complete` 播放结束回调、`on_click` 点画面返回回调；
4. `audio_v2.soft_volume()` 设置软件音量 → 拉高 PA（GPIO73）→ `video:play()`；
5. 起播之后建"返回列表"按钮放在画面右上角，按钮建在视频之后，保证盖在画面最上层；
6. `on_complete` 只置位结束标记，换素材或回清单的动作由轮播任务做；
7. 轮播任务每 500ms 检查一次结束标记：单条模式发 `HZV_BACK_REQ`，轮播模式换下一条，
   一条打不开就跳过，整轮都打不开或整轮播完发 `HZV_BACK_REQ`；
8. 统计任务每 2000ms 打印一次 `video:get_stats()`；
9. 播放前后调 `tp_app.recover()` 补回触摸 I2C 总线配置。

> 播放结束回调只在 `loop=false` 且读到文件尾时触发，所以本 demo 用的是 `loop=false`。
> 想改成一直循环播一条，把 `loop` 改成 `true`、去掉 `on_complete` 即可。

## Air8607 硬件配置

Air8607 整机的引脚是固定的，不需要改配置，这里列出 demo 用到的部分：

| 项目 | 值 | 说明 |
| --- | --- | --- |
| 主控 | Air1603 | 与 Air1601/Air1602 同平台 |
| 屏幕 | 10 寸 1024×600 RGB | `lcd_display_rgb`，免序列四合一 |
| LCD 复位/显示使能 | `pin_rst = GPIO15`（LCD_DISP） | `display.init` 内部做复位时序 |
| RGB 时序 | hbp=140 hspw=20 hfp=160 vbp=20 vspw=3 vfp=12 | 1024×600 生态实测组 |
| RGB 总线时钟 | 50MHz | `pclk_hz` |
| 背光 | PWM3，1kHz，占空比 100 | PIN55 = GPIO13 |
| 触摸 IC | GT911 | I2C 端口 1 |
| 触摸 I2C | I2C1，SCL = PIN42 = GPIO39，SDA = PIN41 = GPIO38 | `i2c.setup(1, 0, true)` |
| 触摸复位 | `TP_RST = GPIO14` | 传给 `tp.init` 的 `pin_rst` |
| 触摸中断 | `TP_INT = WAKEUP = GPIO51` | `int_type = tp.FALLING` |
| 触摸面板尺寸 | 1024×600 | 与屏幕一一对应，缺了会导致触摸初始化失败 |
| 功放 PA | `GPIO73`（AUDIOPA_EN），**高电平使能** | HT6873，起播前拉高 |
| 软件音量 | `70`（100 为原始音量） | `audio_v2.soft_volume` |
| TF 卡 | SPI1，`SPI1_CS = GPIO8` | 挂载到 `/sd` |
| TF 卡供电 | `SD_EN = GPIO74` | 挂载前拉高 |
| TF 卡 SPI 时钟 | 20MHz | 与出厂固件 `storage.sd_card.speed` 一致 |

## HZV 素材准备

### 1、转换素材

1. 安装 **AirMaster**（Windows x64），用合宙 IoT 账号登录；
2. 用它把普通视频（MP4/MOV/AVI 等）转成 `.hzv`；
3. 首跑建议按 **480×320 / 10FPS**、音频 **MP3 32kHz 单声道 64kbps**、画面 contain + 黑色补边、
   结尾 hold-video、开启包 CRC32 转一条，确认能播之后再按 `10 → 15 → 20 → 24 → 30` FPS
   逐步往上加分辨率和帧率；
4. 屏幕是 1024×600，追求满屏显示时把素材转成 **1024×600**，注意看下面「常见问题」里的内存说明。

### 2、拷贝素材

把转好的 `.hzv` **拷贝到 TF 卡根目录**（FAT32 格式），文件名建议用 ASCII。

插卡上电后 demo 自动扫描 `/sd` 根目录，按文件名升序列进清单。

> 只扫根目录，不递归子目录；单次最多列举 100 个条目。
> 想让某条素材排在清单前面，把文件名改得靠前即可（如 `001_demo.hzv`）。

### 3、素材分辨率与显示位置

`airui.video` 组件不支持缩放，素材按自身分辨率 1:1 显示，在屏幕内居中：

| 素材分辨率 | 1024×600 屏上的显示效果 |
| --- | --- |
| 1024×600 | 满屏 |
| 800×480 | 居中，四周留黑边 |
| 480×320 | 居中，四周留黑边 |

## 演示硬件环境

1、Air8607 整机一块：

- 板载 10 寸 1024×600 RGB 屏（带 GT911 电容触摸）
- 板载喇叭（HZV 带音轨，听不到声音时先查 PA 使能脚 GPIO73）
- 板载 TF 卡座

2、TF 卡一张（**必须**）：FAT32 格式，容量不限，里面至少放一个 `.hzv` 素材

3、TYPE-C USB 数据线一根：

- 整机通过 USB 口供电；
- TYPE-C USB 数据线一端接整机 USB1 口（串口下载/调试），另一端接电脑 USB 口。

## 演示软件环境

1、Luatools 下载调试工具：https://docs.openluat.com/air1601/luatos/common/download/

2、固件：Air1603 平台固件，下载地址 https://docs.openluat.com/air1603/luatos/firmware/1603_version/
   （与 `module/Air1601_Air1602_Air1603_Air1604_Air1605/demo/play_hzv` demo 使用同一套固件要求）

3、固件需启用以下宏：

```
LUAT_USE_DISPLAY
LUAT_USE_AIRUI
LUAT_USE_TP
LUAT_USE_VIDEOPLAYER
LUAT_USE_HZV
LUAT_USE_JPEG_DECODE_HW
LUAT_USE_AUDIO_V2
LUAT_USE_FATFS
```

4、本 demo 的素材全在 TF 卡上，**不占 luadb 分区**，固件编号不用迁就文件系统大小。

5、`video:get_stats()` 是 AirUI V1.2.6 之后新增的接口，固件较老时日志里不会打印播放统计（不影响播放）。

6、软件音量走 `audio_v2.soft_volume()`，取值 0~1000，100 表示原始音量（1.0 倍），
   固件没有这个接口时只打印告警，音量保持固件默认值。

7、界面文字用 `airui.font_load` 加载固件内置的 `hzfont` 中文矢量字库，不需要额外的字库文件。

## 演示核心步骤

1、用 AirMaster 把视频转成 `.hzv`，拷贝到 TF 卡根目录，插进 Air8607 的 TF 卡座。

2、用 Luatools **选择整个 `play_hzv_sd` 目录**，点"下载底层和脚本"烧录；
   demo 有 6 个 `.lua` 文件，全部会被自动加入"脚本和资源列表"。

3、烧录固件：选 Air1603 平台固件，确认上面的宏都已启用。

4、烧录成功后代码自动运行：屏幕先黑一下，然后显示素材清单，清单里每行一个 `.hzv` 文件，
   右上角是"顺序播放全部"按钮。

5、触摸操作：

- **点某一行文件名**：只播这一条，播完自动回到清单；
- **点右上角"顺序播放全部"**：按文件名顺序把整张表播一遍，轮完回到清单；
- **播放中点右上角红色"返回列表"按钮**：立刻停止播放，回到清单；
- **播放中点画面**：效果同上；
- **素材比一屏多**：在清单里上下滑动翻看。

6、查看串口日志，正常运行时的关键日志如下（按代码输出整理，实际时间戳与行号以设备输出为准）：

```
I/user.main PLAY_HZV_SD 001.999.000
I/user.main 开始初始化
I/user.lcd_app 背光预置为熄灭 PWM通道3 占空比0
I/user.lcd_app display.init 成功 1024x600
I/user.lcd_app 屏幕已刷黑 1024x600
I/user.lcd_app airui.init 成功 1024x600
I/user.lcd_app 中文字库加载成功 hzfont 字号20
I/user.main 屏幕初始化完成 1024 600
I/user.tp_app 触摸 I2C 总线初始化 端口1
I/user.tp_app 触摸初始化成功 gt911 尺寸 1024x600
I/user.tp_app 触摸已绑定 AirUI
I/user.sd_app TF 卡供电使能 GPIO74
I/user.sd_app TF 卡挂载成功 /sd
I/user.sd_app 扫描到 HZV 素材数量 2
I/user.sd_app 素材 001_demo.hzv 3072KB
I/user.sd_app 素材 002_demo.hzv 2048KB
I/user.hzv_player 播放列表已设置 素材数量2
I/user.file_list 素材选择页建立完成 素材数量2
I/user.file_list 素材选择页已显示
I/user.lcd_app 背光点亮 PWM通道3 占空比100
I/user.file_list 选中素材 1 01  001_demo.hzv
I/user.main 收到选片消息 1
I/user.file_list 素材选择页已隐藏
I/user.hzv_player 开始播放 1/2 /sd/001_demo.hzv
I/user.hzv_player 素材大小 /sd/001_demo.hzv 3072KB
I/user.hzv_player 探测到视频分辨率 1024x600
I/user.hzv_player 视频组件创建成功 /sd/001_demo.hzv 位置 0 0 尺寸 1024x600
I/user.hzv_player 软件音量设置 70 100 为原始音量
I/user.hzv_player 功放打开 GPIO73 电平 1
I/user.hzv_player video:play /sd/001_demo.hzv
I/user.tp_app 触摸 I2C 总线配置已补回 端口1 轮询模式 true
I/user.hzv_player 播放统计 fps=15 总帧数=30 音视频偏差(ms)=8 丢帧=0 音频欠载=0 解码模式=hw
```

## 常见问题

### 1、TF 卡挂载失败

日志里出现 `E/user.sd_app TF 卡挂载失败`：

- 确认卡插到位，卡是 **FAT32** 格式（exFAT/NTFS 不支持）；
- 换一张卡试，个别卡在 20MHz 下不稳，可把 `sd_app.lua` 里的 `SD_SPI_SPEED` 降到 `10 * 1000 * 1000`；
- 打开 `fatfs.debug(1)` 可以看到更详细的挂载过程。

### 2、屏幕一直黑屏

- 清单里提示 `TF 卡里没有 .hzv 素材`：卡的**根目录**下没有 `.hzv` 文件，
  或者文件放在子目录里了（本 demo 只扫根目录）；
- 日志里 `E/user.main 屏幕初始化失败`：固件没开 `LUAT_USE_DISPLAY`；
- 日志里 `E/user.hzv_player 创建视频组件失败`：按下一条排查。

### 3、清单出来了但点不动

1. 先看日志里有没有 `E/user.tp_app 触摸初始化失败`：
   - 有：固件没开 `LUAT_USE_TP`，或者 I2C1、TP_RST(GPIO14)、TP_INT(GPIO51) 接线不对；
   - `tp.init` 返回 `nil` 时先确认 `w=1024`、`h=600` 有没有传，
     尺寸为空时内核输入适配器会静默拒绝，现象是「能读到 product id 但初始化失败」；
2. 日志里 `E/user.tp_app 触摸绑定 AirUI 失败`：固件里的 AirUI 太老，没有 `airui.device_bind_touch`；
3. 日志里 `W/user.file_list 点中的行不在素材列表里`：清单被重建过，重新上电即可。

### 4、播放之后整块屏点不动

音视频通路会用 `i2c.setup` 重配 I2C1（丢掉轮询模式），如果正好落在触摸读事务中间，
GT911 会停在半事务状态，之后所有读都不应答，现象就是**屏幕亮、日志正常、整块屏点不动**。

本 demo 在起播之后和销毁视频之后各调一次 `tp_app.recover()` 补回总线配置，
日志里应该能看到 `I/user.tp_app 触摸 I2C 总线配置已补回`。

内核 tp 库一次上电只接受一次 `tp.init`，遇到这种情况**只能补总线配置，不能重新 init**。
手动验证时可以在串口里执行 `require("tp_app").i2c_restore()`，触摸恢复就说明是这个问题。

### 5、创建视频组件失败（`airui.video` 返回 nil）

日志里出现 `E/user.hzv_player 创建视频组件失败`：

1. 先确认固件宏齐全：`LUAT_USE_AIRUI` / `LUAT_USE_VIDEOPLAYER` / `LUAT_USE_HZV` /
   `LUAT_USE_JPEG_DECODE_HW` / `LUAT_USE_AUDIO_V2`；
2. 再看日志里有没有 `W/videoplayer` 开头的行：
   - 有 `failed to open HZV`：素材头不对，重新用 AirMaster 转一次；
   - 有 `HZV JPEG decode failed`：素材里的某一帧 JPEG 损坏；
   - **一行都没有**：组件建不出来，往内存方向查（见下一条）。

### 6、大分辨率素材起播失败（480×320 能播，1024×600 不能播）

`airui.video` 的帧缓冲是**两块** `宽×高×2` 的 RGB565 内存，起播首帧还要**一块**同尺寸的解码输出，
所以起播峰值是 3 块连续内存：

| 素材分辨率 | 单块 | 起播峰值 |
| --- | --- | --- |
| 480×320 | 300KB | ≈ 0.9MB |
| 800×480 | 750KB | ≈ 2.2MB |
| 1024×600 | 1.23MB | ≈ 3.7MB |

这些内存必须是**连续**的，内存总量够但碎了同样分配不出来。排查办法：

1. 打开 `main.lua` 里注释掉的内存打印定时器，观察 `rtos.meminfo("sys")` 的余量；
2. 先用 480×320 素材确认播放链路是通的，再逐步往上加分辨率；
3. 素材越少，清单里的行越少，占用的内存越少；本 demo 没有加载图片资源，字库是固件内置的。

> 清单页在起播前用 `set_hidden` 收起，组件本身还在，只是不画不收触摸。
> 真正把内存让给帧缓冲的是「起播时先销毁上一个视频组件、返回清单时销毁当前视频组件」这两步。

### 7、只有画面没有声音

- 功放 PA 是 **GPIO73 高电平使能**，日志里应该有 `I/user.hzv_player 功放打开 GPIO73 电平 1`；
- 确认素材带音轨（AirMaster 转换时不要把音频去掉）；
- 音量参数在 `hzv_player.lua` 的 `SPEAKER_VOLUME`，取值 0~1000，100 为原始音量。

### 8、播完一段之后卡住不再往下播

`on_complete` 只在 `loop=false` 且读到文件尾时触发。检查 `hzv_player.lua` 里创建组件的参数，
确认 `loop = false`、`on_complete = on_play_complete` 都还在；想改成单曲循环时才用 `loop = true`。

### 9、清单里的中文显示成方块

`lcd_app.init()` 里的 `airui.font_load` 没有执行成功，看日志里的 `E/user.lcd_app 中文字库加载失败`。
固件要带中文矢量字库（`hzfont`），并启用 AirUI。
