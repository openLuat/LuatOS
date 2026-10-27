## 功能模块介绍

本 demo 演示在 Air1601 系列（含 Air8601/Air8602/Air8603/Air8605/Air8607/Air8607A 整机与
Air1601/Air1602 开发板）上播放合宙嵌入式音视频格式 **HZV** 的完整流程。HZV 把 MJPEG 视频、
MP3/PCM 音频、时间戳和索引封装在同一个 `.hzv` 文件里，解复用、解码和音画同步全部由底层引擎完成，
Lua 侧只负责播放控制。

HZV 格式说明详见：https://docs.openluat.com/protocols/hzv/

项目分为以下核心模块：

1、main.lua：主程序入口，初始化看门狗，按顺序调度屏幕初始化 → TF 卡挂载 → 选片界面 / 自动演示

2、hzv_hw.lua：硬件环境配置模块（型号驱动），把 `HARDWARE_ENV` 映射成一份完整的硬件参数表，
   是**本 demo 唯一的板型差异集中点**，新增板型只需要在这个文件里加一条记录

3、lcd_app.lua：LCD 显示驱动应用模块，用 display 库初始化 RGB 屏、点亮背光、初始化 AirUI

4、sd_app.lua：TF 卡挂载应用模块，按板型初始化 SPI、拉高 SD_EN、挂载 FAT32 到 `/sd`

5、hzv_player.lua：HZV 播放引擎模块，负责扫描素材、创建 `airui.video` 组件、播放控制与统计

6、hzv_ui.lua：选片界面模块（有触摸屏时启用），左侧 HZV 文件列表 + 右侧播放区 +
   底部播放/暂停/停止/音量-/音量+/刷新按钮 + 实时状态显示

7、dont_sick.hzv：默认播放素材（480×320 / 15FPS / MP3 32kHz），随 demo 一起烧进 luadb


## 系统消息介绍

本 demo 不涉及网络，没有使用系统消息。

## 对外接口介绍

1、`hzv_hw.get()`：返回当前 `HARDWARE_ENV` 对应的硬件参数表，未知型号回退默认板型

2、`hzv_hw.pa_set(on)`：按板型打开/关闭功放 PA，`on=true` 打开，`on=false` 关闭

3、`hzv_hw.name()`：返回当前板型中文名

4、`hzv_hw.has_sd()` / `hzv_hw.has_tp()`：查询当前板型是否带 SD 卡 / 是否配置了触摸屏

5、`hzv_hw.volume()`：查询当前板型使用的喇叭软件音量（`audio.vol` 优先，默认 `BOARD_VOLUME`）

6、`lcd_app.init()` / `lcd_app.backlight_on()` / `lcd_app.get_size()`：
   初始化屏幕+AirUI+中文字库（背光仍灭）/ 点亮背光 / 查询屏幕分辨率

7、`sd_app.mount()` / `sd_app.unmount()` / `sd_app.is_mounted()`：TF 卡挂载、卸载与状态查询

8、`hzv_player.scan(dir)`：扫描 `*.hzv` 并返回 `{ {path,name,size}, ... }`，`dir` 可选
   （传 `/luadb` 或 `/sd` 只扫该目录，不传则两个目录都扫）

8.1、`hzv_player.sources()`：返回可切换的素材目录列表 `{ {dir,label,ready}, ... }`，
     `ready=false` 表示 TF 卡未挂载（界面上的目录按钮据此提示）

9、`hzv_player.open(path, rect)`：在 `rect` 区域内居中打开并播放，`rect=nil` 表示整屏；
   `rect.parent` 可指定视频组件的父对象（界面模式下传界面背景容器）

10、`hzv_player.play()` / `pause()` / `stop()` / `destroy()` / `stats()` / `current()`

11、`hzv_player.set_volume(vol)`：设置喇叭软件音量，`vol` 为 0~100，`nil` 表示用板型默认值

12、`hzv_player.get_volume()`：查询当前软件音量

13、`hzv_player.volume_step(delta)`：在当前音量上加减（界面"音量+/-"按钮用），0~100 限幅

14、`hzv_player.start_auto()`：启动无界面自动演示任务（触摸不可用时由 main.lua 调用）

15、`hzv_ui.start()`：初始化触摸并创建选片界面，成功返回 `true`，无触摸/初始化失败返回 `false`

16、`hzv_ui.select(index)`：按序号播放列表里的文件；`hzv_ui.close()`：销毁界面


## 演示功能概述

### 1、主程序入口模块（main.lua）

- 初始化项目信息和版本号（PROJECT / VERSION）
- 初始化看门狗，并定时喂狗
- 启动后依次执行：屏幕与 AirUI 初始化 → TF 卡挂载（失败不影响播放）→ 选片界面 / 自动演示
- 有触摸就进选片界面，触摸不可用就退回自动演示，保证没有触摸屏的板子也能跑
- 最后运行 `sys.run()`

### 2、硬件环境配置模块（hzv_hw.lua）

- `HARDWARE_ENV` 型号字符串 → 完整硬件参数表的映射
- 参数表分五组：
  - `lcd`：分辨率、RGB 时序、复位脚、供电使能脚、背光方式（PWM 调光 / GPIO 直拉 / 随供电脚点亮）
  - `audio`：功放 PA 使能脚与有效电平（HZV 带音轨，PA 不使能就只有画面没有声音）
  - `tp`：触摸屏（GT911）的 I2C 端口、复位/中断脚、I2C 复用表；`nil` 表示该板不接触摸屏
  - `sd`：TF 卡所在 SPI 总线、片选、供电使能脚（SD_EN）、挂载后时钟
  - `name`：板型中文名，只用于日志打印
- 业务模块只读参数，不出现 `if HARDWARE_ENV == ...` 这类板型判断

### 3、LCD 显示模块（lcd_app.lua）

- `display.init("custom", ...)` 初始化 RGB 屏（`id` 显式给 0，AirUI 取的是默认屏）
- **开屏时序（照 8607 出厂固件，解决开机花屏）**：
  1. `backlight_prepare()`：PWM 占空比 0 / GPIO 输出低，先把背光压灭；
  2. `display.init("custom", ...)` 初始化 RGB 屏；
  3. `display.fill(0, 0, w, h, 0x0000)` 把整屏刷黑（RGB 屏帧缓冲持续扫描，写完立即生效）；
  4. `airui.init(w, h)` + `airui.font_load()` 加载中文字库；
  5. 建界面 / 打开视频；
  6. `sys.wait(200)` 等首帧 → `lcd_app.backlight_on()` 点亮背光。
  关键原则是"背光最后亮"：RGB 屏上电后显存是随机内容，先点背光就会看到花屏/白屏，
  所以这里特意等到界面和首帧都画完再点灯。
- 背光点亮方式按参数表：PWM 调光 / GPIO 直拉 / 由 `pin_pwr` 一起点亮；`backlight_on()` 幂等
- `airui.init(w, h)` 初始化 AirUI，供 `airui.video` 创建视频组件
- `airui.font_load({type="hzfont", size=16, cache_size=1024, antialias=1})` 加载固件内置中文字库，
  **必须在 airui.init 之后调用**，否则界面上所有中文（标题、按钮、状态栏）都是方块，
  按钮就看不出是什么功能；8607 出厂固件也是在 `drv/lcd/lcd_common.lua` 里紧跟着加载字库
- PC 模拟器上跳过 `display.init`（AirUI 走 SDL2 窗口，避免出现两个窗口）

### 4、TF 卡模块（sd_app.lua）

- 按板型拉高 TF 卡供电使能脚（SD_EN），SPI 先用 400kHz 低速初始化
- 同一 SPI 总线上的从设备初始化前先拉高片选，防止互相干扰
- `fatfs.mount()` 挂载 FAT32 到 `/sd`，传 `power_pin` 让驱动做一次完整断电-上电复位
- 关闭自动格式化（`auto_format=false`），避免挂载异常时误格式化用户卡
- 挂载成功后打印卡空间信息
- 板型参数表里 `sd=nil` 的板子（如 Air8607A 无 SD 卡座）自动跳过挂载

### 5、HZV 播放引擎（hzv_player.lua）

- 素材扫描：`scan(dir)` 扫 `/sd` 和 `/luadb`（`dir` 可选，只扫指定目录），列出所有 `*.hzv`。
  扫描时对每个条目做 `io.exists` 复核，避免"列表里有、点开报文件不存在"。
  注意 luadb 的挂载前缀是 `/luadb/`（带尾斜杠）、fatfs 是 `/sd`（不带），
  `io.lsdir` 的入参必须与挂载前缀一致，否则 VFS 匹配不到挂载点会返回 0 条（本 demo 已兼容两种写法）
- 分辨率探测：用 `videoplayer.open/info/close` 读 HZV 真实分辨率，把视频组件在指定区域内居中
  （探测不到时按区域尺寸创建，组件首帧解码后会按视频实际尺寸自动纠正）
- 创建 `airui.video` 组件：`format="hzv"`、`backend="videoplayer"`、`decode_mode="hw"`、`loop=true`
- 播放控制：`play()` / `pause()` / `stop()` / `destroy()`，播放时开 PA、暂停/停止时关 PA
- 统计接口 `stats()`：读取 `video:get_stats()` 给界面显示
  - `fps`：实际呈现帧率（非容器声明值）
  - `av_delta_ms`：音视频时间差，偶发波动属正常，持续单向增长才是失步
  - `dropped_frames`：因落后而跳过的帧数，持续增长说明解码或存储带宽吃紧
  - `audio_underruns`：音频 FIFO 欠载次数，持续增加要查存储速度与解码负载
  - `clock_mode`：正常硬件播放应为 `sample-counter`；`decode_mode` 优先确保是 `hw`
- `start_auto()`：无触摸屏时的自动演示，打开第一个素材后**一直连续循环播放**（不做暂停/停止），
  每 2 秒把 fps / 丢帧 / 音画差打到日志里，适合长时间连播观察稳定性

### 6、选片界面（hzv_ui.lua）

- 触摸初始化：按 `hzv_hw.tp` 做 I2C 引脚复用 → `i2c.setup` → `tp.init("gt911", ...)` →
  `airui.device_bind_touch(tp_device)`，任一步失败即返回 `false`，由 main.lua 退回自动演示
- 布局（按屏幕分辨率自适应，1024×600 下）：
  - 顶部 56px 标题栏：左侧"HZV 视频库"标题，右侧显示"当前目录 · 文件数量"
  - 左侧 30% 宽区域分两块：
    - 顶部 46px 目录切换栏：**内置存储（/luadb）/ TF 卡（/sd）** 两个按钮，
      选中哪个就只列该目录下的 `*.hzv`，选中项用深蓝底色标出；TF 卡没插时按钮照样能点，状态栏会提示
    - 下方文件列表：每个 `*.hzv` 一项，点击即换片，正在播放的那项高亮（切换目录后如果当前文件
      在新列表里，高亮会自动补上，播放不会被打断）
  - 右侧播放区：视频在区域内居中显示（组件不支持缩放，保持原始分辨率）
  - 底部 64px 工具栏：**7 个按钮**（播放 / 暂停 / 停止 / 音量- / 音量+ / 刷新 / 全屏），
    按钮文字是中文，依赖 `airui.font_load` 加载的中文字库才能显示
  - 全屏模式（点"全屏"）：隐藏标题栏/目录栏/文件列表/工具栏，播放区域换成整屏，
    底部浮出一条控制栏（播放 / 暂停 / 退出全屏 + 状态文字），点"退出全屏"还原界面
  - 工具栏右侧状态栏只显示两项：`fps 15.0 · 音量 30`
- fps 由界面自己算（`total_frames` 增量 / `mcu.ticks()` 时间差），不用 `get_stats().fps`：
  实测该字段在部分固件上返回 `1e-308` 这类无效值，直接显示会出现
  `0.00000000000000e-308`；丢帧、音画差等原始统计不在界面上显示，仍会由
  `hzv_player.log_stats()` 打到日志里
- 音量按钮每次 **±5**（`hzv_player.volume_step(±5)`），刻度 **0~100**（100=原始音量、0=静音），
  点完立即刷新状态栏
- 启动时自动播放列表里的第一个文件；点"刷新"会重扫**当前选中目录**（插拔卡后不用重启）
- 全屏实现要点：
  - 全屏只是把"可用播放区域"换成整屏；`airui.video` 不支持缩放，画面仍按素材原始分辨率居中，
    1024×600 上播 480×320 素材，四周照样是黑边；
  - 进/退全屏都会 `destroy` 旧组件并按新区域重新 `open`（音频要重新整段抽取，约 0.1~0.3 秒黑屏，属正常）；
  - 浮动控制栏必须**在视频之后创建**：同一父对象里 LVGL 按创建顺序绘制，后建的控件才压得住画面；
  - 各栏用容器 `set_hidden` 显隐，老固件没有该接口时只是栏位不消失，播放和点击都不受影响；
  - 素材比屏幕大（如 1280×720）时组件会强制把控件尺寸改回素材尺寸，超出屏幕的部分被裁掉，
    只能在整屏里看到中间一块。

> 注意：HZV 的音画同步完全在底层完成，Lua 侧**不需要设置 `interval`**，也**不需要定时调
> `step()` / `skip()`**。这是 HZV 与老式"mjpg + mp3 双文件手动同步"方案最大的区别。


## 硬件环境配置（HARDWARE_ENV）

各开发板的屏幕引脚、背光方式、功放使能脚、TF 卡供电脚都不同，通过 `hzv_hw.lua` 顶部的
`HARDWARE_ENV` 变量切换，**默认 `8601_DEV_BOARD`**。

**参数取值原则：每一行都与对应型号出厂固件的配置保持一致，不自行推测。**

| HARDWARE_ENV 值 | 适用板型 | LCD_RST | LCD 供电/使能 | 背光 | PA(有效电平) | 触摸(GT911) | SD 卡(SPI/CS/EN/时钟) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `8601_DEV_BOARD`（默认） | Air8601 引擎 7寸 | GPIO15 | 无 | PWM3 | GPIO74(**低**) | RST56/INT51 | 1/GPIO8/GPIO65/20MHz |
| `8602_DEV_BOARD` | Air8602 工业模组 7/9/10寸 | GPIO15 | 无 | PWM3 | GPIO73(**低**) | RST72/INT51 | 1/GPIO8⚠/GPIO74/20MHz |
| `8603_DEV_BOARD` | Air8603M/Air8603W 10寸 | GPIO15 | 无 | PWM3 | 无(Air1103 常供 GPIO73) | RST72/INT51 | 1/GPIO8/GPIO74/20MHz |
| `8605_DEV_BOARD` | Air8605 10寸 | GPIO15 | 无 | PWM3 | 无(Air1103 常供 GPIO73) | RST**不传**/INT51 | 1/GPIO8/GPIO74/20MHz |
| `8607_DEV_BOARD` | Air8607 10寸(Air1603 主控) | GPIO15 | 无 | PWM3 | GPIO73(高) | RST14/INT51 | 1/GPIO8/GPIO74/20MHz |
| `8607A_DEV_BOARD` | Air8607A 10寸(带 UVC) | GPIO15 | 无 | PWM3 | GPIO73(高) | RST14/INT51 | **无 SD 卡座** |
| `1601_EVB_V11` | Air1601 V1.1 EVB 7寸 | GPIO15 | 无 | **GPIO2 直驱(无 PWM)** | GPIO12(高) | RST3/INT51 | 1/GPIO8/无/40MHz |
| `1601_EVB_V12` | Air1601/Air1602 V1.2 EVB 7寸 | GPIO15 | GPIO57(LCD_EN) | PWM3 | GPIO73(**低**) | RST3/INT51 | 1/GPIO8/GPIO56/8MHz |

所有板型分辨率均为 1024×600，RGB 时序统一 `140/20/160/20/3/12 @50MHz`；
触摸统一是 GT911 走 I2C1（`int_type = tp.FALLING`），8601/8602/8605 另需把 PIN33/PIN32
复用成 I2C1_CLK/I2C1_SDA（`pins.setup`），其余板型的复用表出厂固件里是空的或已注释。

切换方式（二选一）：

1、直接改 `hzv_hw.lua` 顶部的 `HARDWARE_ENV`；
2、在 `main.lua` 的"硬件环境配置（可选）"处给全局 `HARDWARE_ENV` 赋值，优先级更高。

各板型参数的出厂固件来源（`hzv_hw.lua` 里每条记录上方也写了同样的出处）：

| HARDWARE_ENV 值 | 对应出厂配置文件 |
| --- | --- |
| `8601_DEV_BOARD` | `module/Air8601/project/factory/config/eng_8601_7i_4g.lua`（WiFi 版 `eng_8601_7i_wifi.lua` 硬件一致） |
| `8602_DEV_BOARD` | `module/Air8602/project/factory/config/eng_8602_9i_4g.lua` |
| `8603_DEV_BOARD` | `module/Air1601_Air1602_Air1603_Air1604_Air1605/project/factory/config/eng_8603m_10i_v0.lua` |
| `8605_DEV_BOARD` | `module/Air8605/project/factory/config/eng_8605_10i_4g.lua` |
| `8607_DEV_BOARD` | `module/Air8607/project/factory/config/eng_8607_10i_v0.lua` |
| `8607A_DEV_BOARD` | `module/Air8607/project/factory/config/eng_8607a_10i_v0.lua` |
| `1601_EVB_V11` | `module/Air1601_Air1602_Air1603_Air1604_Air1605/project/Air1601_dev_board_V1.1/factory/config/evb_1601_7i_v11.lua` |
| `1601_EVB_V12` | `module/Air1601_Air1602_Air1603_Air1604_Air1605/project/Air1602_dev_board_V1.2/factory/config/evb_1602_7i_v12.lua` |

需要留意的几处：

1、**PA 有效电平各板不同**：Air8601 的 `AUDIOPA_EN=GPIO74` 与 Air8602 的 `GPIO73` 都是
   **低电平使能**（`pa_on_level=0`），Air8607/Air8607A 的 HT6873 是**高电平使能**。
   拿错电平会出现"只有画面没有声音"或者"一直有底噪"。

2、**Air8603 / Air8605 的音频走 Air1103 语音芯片**（UART），出厂固件**不写 `pa_ctrl`**，
   `GPIO73` 是 Air1103 的供电脚、上电常拉高。所以本 demo 在这两块板上 `pa_pin=nil`，
   不去开关该脚（关掉会把语音芯片断电）。HZV 内置音轨能否出声取决于固件里 Audio V2 的输出
   是否接到 Air1103，本 demo 只保证画面。

3、**Air8602 的 SD 片选需要核对**：出厂固件写的是 `pin_cs = 38`，注释为
   "SPI1_CS0 = PIN38（GPIO 待确认）"——38 是排针 PIN 号而不是 GPIO 号。
   同族 8601/8605/8607 出厂固件都写作 "PIN38 = GPIO8"，因此本 demo 按 GPIO8 填。
   若该板识别不到 TF 卡，优先把 `hzv_hw.lua` 里 `8602_DEV_BOARD` 的 `pin_cs` 换成其它候选值。

4、**Air8607A 出厂固件没有 `storage.sd_card` 段**（本板无 SD 卡座），所以该板参数 `sd=nil`，
   只能播放 `/luadb` 下的素材；`main.lua` 会自动跳过挂载。

5、**Air1601 V1.1 EVB 背光只能开关、不能调光**（出厂固件 `pin_bl=GPIO2`，无 PWM）；
   V1.2 EVB 是 `pin_pwr=GPIO57` + PWM3 调光，两者不通用。

> 为什么不能自动识别板型：同一颗 Air1601/Air1602/Air1603 模组会被装在多块底板上，
> `rtos.bsp()` / `hmeta.model()` 只返回模组级信息，无法区分底板版本，所以必须人工指定。


## HZV 素材准备

### 1、默认素材（已随 demo 提供，无需自备）

本目录下的 `dont_sick.hzv` 就是默认素材，参数如下（读容器头得到）：

| 项 | 值 |
| --- | --- |
| 分辨率 | 480 × 320（MJPEG，RGB565 输出） |
| 帧率 | 15 FPS |
| 音频 | MP3，32 kHz，单声道，16 bit |
| 文件大小 | 约 2.9 MB（3,040,640 字节） |

**烧录方式：用 Luatools 选择整个 `play_hzv` 目录，并确认 `dont_sick.hzv` 也在"脚本和资源列表"里**，
点"下载底层和脚本"后它会被写入模块文件系统，运行时路径是 `/luadb/dont_sick.hzv`，上电默认就播它。

> 注意 1：`.hzv` 不是脚本文件，Luatools 只添加 `*.lua` 时它不会被下载。务必在
> "脚本和资源列表"里把它**手动加进去**（确认勾选下载到文件系统），再点"下载底层和脚本"。
> 验证办法：上电后日志里 `扫描到 HZV 文件数量` 后面如果只有 `/sd/...`，说明 luadb 里没有它。
>
> 注意 2（**固件编号必须选对**）：Air1601/Air1602 有两种固件，文件系统（fs）分区差别很大：
>
> | 固件编号 | 文件系统 fs | 脚本区 |
> | --- | --- | --- |
> | **101 号**（本 demo 必须用这个） | **3008 KB** | 1024 KB |
> | 102 号 | 1536 KB | 4096 KB |
>
> `dont_sick.hzv` 是 2969 KB，**只有 101 号固件放得下**（3008 - 2969 ≈ 只剩 39KB 余量，
> 基本顶满 fs 分区，所以不要再往里加别的资源）；102 号固件差 1433KB，选了必然烧不进去。
>
> 如果换的素材比 2.9MB 更大、或者固件只能用 102 号，就把素材放 TF 卡根目录
> （`/sd/dont_sick.hzv`），代码扫 `/sd` 时同样能找到并优先播放。

### 2、换素材 / 加素材

1、安装 AirMaster（Windows x64），用合宙 IoT 账号登录，用它把普通视频（MP4/MOV/AVI 等）转 HZV；
2、按屏分辨率裁好再转：Air1601 系列首跑推荐 **480×320 / 10FPS**、音频
   **MP3 32kHz 单声道 64kbps**、画面 contain + 黑色补边、结尾 hold-video、开启包 CRC32；
3、稳定后再按 `10 → 15 → 20 → 24 → 30` FPS 逐步往上加，60FPS 只用于转换能力验证；
4、产物扩展名是 `.hzv`：
   - 想保持"默认就播它"：直接把文件改名为 `dont_sick.hzv` 覆盖本目录里的同名文件，重新烧录；
   - 想放多个素材让客户自己选：都拷到 TF 卡根目录（`/sd/*.hzv`），界面左侧会全部列出来。

> 默认播放优先级：列表里如果存在 `dont_sick.hzv`（`/sd` 或 `/luadb` 任意一处），
> 它固定排第一并自动播放；没有这个文件时，才按路径排序播第一个 `.hzv`。
> 这个规则在 `hzv_player.lua` 顶部的 `DEFAULT_FILE` 变量里改。


## 演示硬件环境

1、Air8601 / Air8602 / Air8603 / Air8605 / Air8607 / Air8607A 整机开发板，或 Air1601/Air1602 开发板一块：

- 板载或外接 1024×600 RGB 屏
- **触摸屏**（GT911）：有触摸就进选片界面，没有触摸会自动退回自动演示模式
- 板载喇叭或外接喇叭（HZV 带音轨，听不到声音时先查 PA 使能脚）
- TF 卡一张（FAT32）**可选**：默认素材已经烧在 luadb 里，插卡只是为了放更多素材

2、TYPE-C USB 数据线一根：

- 开发板通过 USB 口供电；
- TYPE-C USB 数据线一端接开发板 USB1 口（串口下载/调试），另一端接电脑 USB 口。

串口烧录与拨码开关位置详见 [1601 开发板使用说明](https://docs.openluat.com/air1601/product/shouce/)。


## 演示软件环境

1、Luatools 下载调试工具：https://docs.openluat.com/air1601/luatos/common/download/

2、固件版本：本demo开发测试时使用的固件为[LuatOS-SoC_V1028_Air1603_102.soc](https://docs.openluat.com/air1603/luatos/firmware/1603_version/) ，其他型号开发板使用相应的102号固件烧录即可。

3、固件需启用以下宏（AirUI / videoplayer / HZV reader / JPEG 硬解 / Audio V2 / 触摸）：

```
LUAT_USE_AIRUI
LUAT_USE_VIDEOPLAYER
LUAT_USE_HZV
LUAT_USE_JPEG_DECODE_HW
LUAT_USE_AUDIO_V2
LUAT_USE_TP          （用选片界面时需要，缺了会退回自动演示）
```

4、`video:get_stats()` 是 AirUI V1.2.6 之后新增的接口，固件较老时界面右下角只显示文件名（不影响播放）。

5、`airui.device_bind_touch()` 是 AirUI V1.0.1 之后的接口名（更早的版本叫 `airui.indev_bind_touch`，
调用即报错），老固件触摸会绑不上，此时同样退回自动演示。

6、软件音量走 `audio_v2.soft_volume()`，固件没有这个接口时只打印告警，音量保持固件默认值。

7、测试音频播放建议使用 Air8607 V1028 及以上版本固件。


## 演示核心步骤

1、按实际板子在 `hzv_hw.lua` 顶部改好 `HARDWARE_ENV`（默认 `8601_DEV_BOARD`）。

2、用 Luatools **选择整个 `play_hzv` 目录**，并确认 `dont_sick.hzv` 已加入"脚本和资源列表"
   （`.hzv` 不是 `.lua`，不会被自动加入），点"下载底层和脚本"烧录；
   烧进去后运行时路径是 `/luadb/dont_sick.hzv`，上电默认播放它，不需要另插 TF 卡；
   分区放不下或想放更多素材时，把 `*.hzv` 拷到 TF 卡根目录，界面里会一起列出来。

3、烧录固件：按板型选对应型号的固件，编号选 **101 号**（fs 3008KB，能装下默认素材）。

4、烧录成功后代码自动运行：屏幕点亮（先黑一下再出画面，背光在屏初始化之后才点亮），然后

- **有触摸屏**：进入选片界面，左侧列出扫到的 HZV 文件，自动播放第一个（即 `dont_sick.hzv`）；
  点其它文件名换片，底部可播放/暂停/停止/刷新/全屏，右下角显示 fps 与音量；
- **没有触摸屏或触摸初始化失败**：进入自动演示模式，一直循环播放 `dont_sick.hzv`，日志每 2 秒打印一次播放统计。

5、查看串口日志，正常运行时关键日志如下（节选，触摸屏模式）：

```lua
[2026-10-26 14:20:01.100][LTOS/N][000000000.100]:I/user.main PLAY_HZV 001.999.000
[2026-10-26 14:20:01.220][LTOS/N][000000000.220]:I/user.hzv_hw 当前硬件环境 8601_DEV_BOARD Air8601 引擎开发板(7寸 1024x600) 分辨率 1024x600 LCD_RST=GPIO15 无 LCD_PWR 非GPIO背光 PA=GPIO74 TP_RST=GPIO56 SD_EN=GPIO65
[2026-10-26 14:20:01.230][LTOS/N][000000000.230]:I/user.lcd_app display.init 成功
[2026-10-26 14:20:01.240][LTOS/N][000000000.240]:I/user.lcd_app 背光预置为熄灭(PWM) 通道3 占空比0
[2026-10-26 14:20:01.245][LTOS/N][000000000.245]:I/user.lcd_app 屏幕已刷黑 1024x600
[2026-10-26 14:20:01.256][LTOS/N][000000000.256]:I/user.lcd_app airui.init 成功 1024x600
[2026-10-26 14:20:01.258][LTOS/N][000000000.258]:I/user.lcd_app 中文字库加载成功(hzfont)
[2026-10-26 14:20:01.259][LTOS/N][000000000.259]:I/user.main 屏幕初始化完成 1024 600
[2026-10-26 14:20:01.330][LTOS/N][000000001.330]:I/user.sd_app TF 卡供电使能 GPIO65
[2026-10-26 14:20:01.560][LTOS/N][000000001.560]:I/user.sd_app TF 卡挂载成功 /sd
[2026-10-26 14:20:01.575][LTOS/N][000000001.575]:I/user.hzv_ui 触摸 I2C 引脚复用完成，数量 2
[2026-10-26 14:20:01.640][LTOS/N][000000001.640]:I/user.hzv_ui 触摸初始化成功并已绑定 AirUI
[2026-10-26 14:20:01.660][LTOS/N][000000001.660]:I/user.hzv_ui 选片界面创建完成 1024x600
[2026-10-26 14:20:01.668][LTOS/N][000000001.668]:I/user.hzv_player 扫描到 HZV 文件数量 1 默认播放 /luadb/dont_sick.hzv
[2026-10-26 14:20:01.670][LTOS/N][000000001.670]:I/user.hzv_ui 文件列表刷新完成 1 个
[2026-10-26 14:20:01.680][LTOS/N][000000001.680]:I/user.hzv_ui 选中素材 dont_sick.hzv /luadb/dont_sick.hzv
[2026-10-26 14:20:01.690][LTOS/N][000000001.690]:I/user.hzv_player 素材大小 /luadb/dont_sick.hzv 2969KB
[2026-10-26 14:20:01.695][LTOS/N][000000001.695]:I/user.hzv_player 探测到视频分辨率 480x320
[2026-10-26 14:20:01.700][LTOS/N][000000001.700]:I/user.hzv_player 视频组件创建成功 /luadb/dont_sick.hzv 位置 429 136 尺寸 480x320
[2026-10-26 14:20:01.702][LTOS/N][000000001.702]:I/user.hzv_player 软件音量设置 30 (100 为不衰减)
[2026-10-26 14:20:01.705][LTOS/N][000000001.705]:I/user.hzv_hw 功放打开 GPIO74 电平 0
[2026-10-26 14:20:01.710][LTOS/N][000000001.710]:I/user.main 触摸可用，已进入选片界面
[2026-10-26 14:20:01.910][LTOS/N][000000001.910]:I/user.lcd_app 背光点亮(PWM) 通道3 占空比100
```

没有触摸的板子日志里会出现这两行，随后进入自动演示：

```lua
[I/user.hzv_ui 当前板型没有配置触摸屏 xxx]
[W/user.main 触摸不可用，进入自动演示模式（没有选片界面）]
```
