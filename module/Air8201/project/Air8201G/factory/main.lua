--[[
@module  main
@summary 应用主入口（单固件多型号自适应：Air8202 / Air8201G / Air8201H）
@version 5.0
@date    2026.09.16
@usage
启动流程：
1. fskv.init() → board.init()（T0 板型识别，纯字符串判定，无 I/O）
2. sim_slot.init()（读 USIM_DET 电平选卡槽 + 注册热插拔中断）→ FOTA 开机检测 → sys.taskInit(start_app)
3. start_app：加载本地持久化配置（cfg_fetch/db）→ 启动云平台连接（create）→ 启动 app
   （已禁用后台拉取网页端配置，只使用本地/默认配置）
4. 默认开机进入寻宠模式（GPS定位，mode=2），不进入未激活模式（见 app.lua）

版本沿革：
- 004.000.039：电池低压截止保护——未充电且电压≤3.2V 连续确认后执行 YHM2712A 船运模式
  （断开电池关机，USB 插入自动开机续充）；电量 0% 折算线同步下调至 3200mV
- 004.000.040：充电中电压可信门控——拒绝 VBAT 系统轨被抬升产生的 ~4.12V 假值
  （battery 模块以最近可信基准限制充电中单步跳变，防污染值进入缓存与上报）
- 004.000.041：单固件多型号自适应（M1~M4）——
  · 新增 board.lua：hmeta.model 主判据识别板型，profile 注入全部板级引脚/能力
  · battery 拆"电压源 + 充电源"双可插拔实现（adc0/vbat_internal、yhm/vbus/none）
  · gsensor 双驱动（exvib/exs_da267）+ 12bit 原始值跨型号标度归一化
  · GNSS 使能脚、LED 映射、低压截止动作按 profile 分发
  · 产测整体移除（lib/factory.lua 删除、BOOT_MODE 分支删除）
- 004.000.042：修复 8201G 上"板型识别失败 → unknown → 功能全废"（2026-09-17 实机）
  · 根因：Air780EGH 固件未编入 hmeta 库，且 rtos.bsp() 返回 nil → 判据源全失效
  · board.lua：判据源扩为 5 级（hmeta.model/chip → rtos.bsp/firmware → BOARD_DEFAULT），
    多源不一致告警；新增构建期兜底 BOARD_DEFAULT；unknown 不再静默（ERROR 级报错）
  · board.lua：启动日志新增"判据源可用性"一行，一次开机即知哪个 API 可用；
    hmeta 不可用时 8s 后延迟复检，区分"固件缺库"与"开机未就绪"
- 004.000.043：8201G 实机第二轮（2026-09-17）
  · ★ 确认根因：**type(hmeta) == "userdata"**（核心库注册形式不是普通 table），
    旧代码用 type(hmeta)=="table" 硬判把它误判为"库不存在"→ 识别失败 → unknown → 功能全废。
    现 is_hmeta_lib() 改为"取得出可调用的 model 即认"，识别已正常（source=hmeta, id=8201G）。
  · ★ 修复 SIM0 检测脚"先读后配"的顺序错误：官网《GPIO》明确"当管脚为输入模式或中断,
    才能通过 gpio.get() 获取到电平"；原实现先 gpio.get 后 gpio.setup → 开机首读必然失败
    → 回落默认卡槽 SIM1 → 插在 SIM0 的卡不被选中。现改为「先 debounce+setup，再读电平」，
    并打印原始电平用于标定 present_level 极性。
  · 引脚常量改用官网语义名：SIM 检测 gpio.USIM_DET、VBUS 检测 gpio.VBUS（与 WAKEUP2/WAKEUP1 等值）。
  · battery：ADC0 采样全失败时打印 adc.get 逐次原始返回，便于定位通道/量程问题。
- 004.000.045：工程结构规整（2026-09-17）
  · ★ lib/ 只允许存放**合宙官方扩展库**。删除三个自造的"适配层库"：
    lib/bat_voltage.lua、lib/bat_charger.lua（合并进 modules/battery.lua）、
    lib/gs_drv.lua（合并进 modules/sensors/gsensor.lua）。
    三者均为单一消费者，合并后消除了一层不必要的可插拔抽象。
  · ★ 核心库（adc/gpio/hmeta/rtos/mobile）不再做"是否存在/是否支持"的判断，直接调用；
    仅保留对官方语义返回值的处理（如 hmeta.model() 识别不出时返回 nil、
    adc.get() 读取失败返回 -1）。
- 004.000.046：SIM 检测避开开机时序（2026-09-17）
  · 问题：init() 同步执行，刚下发 gpio.setup 就 gpio.get，开机瞬间读数不可信 ——
    既可能读失败，也可能读到"错误但非 nil"的电平（尚未切输入态时可能恒为 0）；
    后者会被判成"SIM0 不在位"→选 SIM1，且电平稳定不产生边沿，热插拔中断也无法纠正。
  · 处置：开机即时读数**只打印、不决策**（也不写入 state.sim0_present）；
    选卡先用 profile 的 boot_default（8201G=0/SIM0）并尽早下发 mobile.simid；
    新增 confirm_slot_later 任务，在开机后 500ms/1500ms 两轮延迟复检，
    以**延迟读数为最终判据**，与当前卡槽不一致才执行一次正式切卡。
- 004.000.047：SIM 检测极性修正 + 电池轮询提前出数（2026-09-17）
  · ★ SIM 检测极性反了：卡插在 SIM0 时检测脚稳定读到 0，而 present_level 原写 1
    → 每次开机都被判成"SIM0 拔出"并切到 SIM1。改为 **present_level = 0（低电平=在位）**，
    三型号统一（硬件均为"上拉 + 卡座检测开关对地"）。
  · ★ 确认 rtos 与 hmeta 同属"非普通 table"的核心库：原 read_bsp/read_firmware 里的
    type(rtos) ~= "table" 守卫同样误杀了可用库（表现为 rtos.bsp=nil）。
    去掉守卫后 rtos.bsp / rtos.firmware 均正常返回。
  · battery：无充电IC通讯的板型（vbus/none）开机等待由 5s 缩短为 1s，更早出电压。
- 004.000.048：LED 时基修正（2026-09-17）
  · ★ 原实现把 mcu.ticks() 直接当毫秒用，但官网明确 tick 单位由平台决定、
    应以 mcu.hz()（每秒 tick 数）为准。若 tick ≠ 1ms，则**全部闪烁频率与窗口时长整体失真**。
    现统一经 T(ms) = ms × mcu.hz() / 1000 换算；mcu.hz()==1000 时行为与原版完全一致。
  · LED 初始化日志增加 tick 基准打印，便于现场核对闪烁节奏是否正确。
- 004.000.049：恢复远程灯控（2026-09-17）
  · modules/remote.lua 的 open_light 命令原先调用 tools.led_set_manual，但该函数在
    004.000.030 清理时被删除 → 命令静默失效却仍回 "ok"（平台侧误判为成功）。
  · 现于 utils/tools.lua 恢复 tools.led_set_manual(enable)，并置于网络灯判定的**最高优先级**：
      enable=true  → 网络/状态灯强制常亮（远程点灯）
      enable=false → 交还自动状态机
    **充电灯不受影响**，始终按充电状态自动显示（避免远程点灯掩盖充电指示）。
- 004.000.050：USB 电源跟随充电状态（2026-09-17）
  · 新需求：充电时打开 USB、不充电时关闭。
  · 官方接口：pm.power(pm.USB, onoff)（官网 @api pm.power 明确列出 pm.USB 为 USB 电源开关；
    usb.* 库是 USB 协议栈 tx/rx/class，不是电源控制）。
  · 在 modules/battery.lua 按充电状态同步，仅在充电源读取成功时动作（状态未知不动作，
    避免误关）；开关 config.USB_POWER_FOLLOW_CHARGE（默认 true）。
  · 因 VBUS 极性若标反会出现"插上 USB 反而关掉 USB、调试口不可用"，故保留总开关。
- 004.000.051：加速度计初始化失败的可定位化（2026-09-17）
  · 现象：8201G 上 gsensor 未初始化 → 1292 三轴不上报、1293/1295 振动流恒 0 样本。
  · gsensor 初始化失败的 ERROR 日志补充后果说明（明确会连带 1292/1293/1295 一起失效）。
  · 新增 diag_i2c()：Setup 失败时自动打印一次 I2C 诊断 ——
    官方 i2c.scan(bus) 列出总线上所有应答地址 + 直接读 DA267 芯片ID 寄存器(0x01, 期望 0x13)，
    用于区分「没上电/总线不通」与「地址或型号判断有误」。
- 004.000.052：I2C 诊断增强（2026-09-17）
  · 实机结论：i2c.scan(1) 全地址空间扫描**无任何器件应答**（全部"传输超时"），
    说明问题不在"地址不对"，而是整条总线没有可通信器件。
  · 诊断增强为三步：目标地址在 **SLOW / FAST 两种速度**下各探一次
    （官网《i2c.scan》明确"如探测不到则修改速度"）+ **换另一路 I2C** 再探一次
    + 官方 i2c.scan 全量扫描。
- 004.000.053：修复 I2C1 外部上拉源未使能（2026-09-17，8201G）
  · ★ 根因（用户据原理图指出，已核实）：8201G 的 I2C1_SDA/SCL 10k 上拉电阻（R16/R17）
    由 **GPIO28（AGPIO8 / 模组 PIN78）** 供电/使能，而**原代码从未碰过 GPIO28**
    → SDA/SCL 无上拉 → 整条总线无任何器件应答
    → 与实机现象完全吻合（i2c.scan 全地址"传输超时"、DA267 芯片ID 校验失败、
      gsensor 初始化失败、1292/1293/1295 全部无数据）。
  · board.lua：8201G 的 gsensor profile 新增 `i2c_pullup_pin = 28`。
  · gsensor.lua：da267 驱动 setup() 第①步在任何 I2C 通信**之前**把该脚拉高，
    并打印使能日志；诊断日志同步输出该引脚值。
  · 仅 8201G 需要：8201H 的 AGPIO8 用作 UART1_RXD，8202 用模组内置 G-Sensor（上拉在模组内）。
- 004.000.054：修复"初始化成功但运行中 I2C 突然全灭"（2026-09-17，8201G）
  · 现象：053 后开机初始化成功（`I2C1 外部上拉源已使能` → DA267 建链、量程/运动检测OK），
    运行约 2.5 分钟后开始持续失败：`I2c_failed ... i2c1 从机地址 26 传输过程发生异常，错误码-6`
    → `E/exs_da267 读取加速度数据失败`，此后不再恢复。
  · ★ 根因：pm.power(pm.WORK_MODE, n) **切换功耗档会复位引脚配置**
    （本工程 lowpower/drv_lowpower.lua 原本就为此写了 `_restore_interrupt()` 恢复中断脚，
     证明该副作用确实存在）。而 053 新加的 **I2C 支撑脚（上拉源 GPIO28 / 供电 GPIO24）
     只在开机设置了一次，切档复位后再无人恢复** → SDA/SCL 失去上拉、器件失去供电 → 持续失败。
  · gsensor.lua：新增 `assert_support()`（幂等重拉上拉源+供电，无阻塞）；
    读取失败时自愈：累加 fail_cnt，限流 2s 后重拉支撑脚；
    **连续失败 ≥3 次**则判定器件掉过电，额外重跑 lib.setup 恢复 range/运动阈值等寄存器；
    成功即清零。恢复验证交给 50ms 后的下一拍采样（上拉建立需要时间，不阻塞读取路径）。
  · gsensor.lua：`_restore_interrupt()` 扩展为**同时恢复中断注册与板级支撑脚**。
  · drv_lowpower.lua / drv_normal.lua：切功耗档后调用上述恢复（两条路径都覆盖）。
  · 验证（Lua 5.3 VM）：模拟"切档复位引脚 → 读取失败 → 自愈重拉 → 下一拍恢复"闭环通过；
    8202（无上拉源）不受影响、不触碰 GPIO28。
- 004.000.055：054 实机反馈 —— 自愈已触发但未救回总线（2026-09-17，8201G）
  · 实机日志：`gsensor I2C 连续失败 8 次 → 重新拉高支撑脚并重配传感器` 确实执行了，
    随后 `I2C2_MasterSetup`（库内 i2c.close + i2c.setup(SLOW) 重建控制器）也执行了，
    但**仍然全部超时**：`I2c_failed 140?i2c1 ... 传输超时`(-13) → `芯片ID校验失败` → `重配传感器失败: false`。
    ★ 关键推论：失败签名（-13 超时）与"完全没有上拉"时**完全一致**，且控制器已重建仍失效
      → **重拉 GPIO28 不足以恢复**，问题不在控制器配置，而在总线物理状态。
  · 自愈升级为三级：① 重拉支撑脚 → ② **给传感器断电重上电**（30s 限流；用于解除
    "器件失电/闩锁后 ESD 二极管钳位 SDA/SCL"——该状态下主控只看到超时而非 NACK，
    且重拉上拉无效）→ ③ 重配寄存器。
  · ★ 决定性诊断：`assert_support()` 现在**校验 gpio.setup 的返回值**。
    官方语义为"输出模式成功返回设置电平的闭包，失败返回 nil"，据此可一次区分：
      ① 重配返回 nil → 该脚已被低功耗配置/PMU 收走，Lua 层再也拿不回来（重拉注定无效）
      ② 重配成功但仍超时 → 引脚正常，是总线被器件钳住（需断电复位）
  · 功耗档切换处新增显式日志（`★ 切功耗档 pm.WORK_MODE = 0/1`，3 处调用点全覆盖），
    便于把"失效时刻"与"切档时刻"对齐定位。
  · 附带发现（非 I2C 根因，仅记录）：库内 60s 运动窗口定时器报 `rtos.timer_start error`
    —— 来自 lib/exs_da267.lua:143/149 的 sys.timerStart（其底层即官方 rtos.timer_start）。
- 004.000.056：I2C1 支撑脚改为「全量拉高」（2026-09-17，用户指示）
  · 思路（用户提出）：**I2C1 上不止一个器件，任一器件未上电，其 ESD 保护二极管就会把
    SDA/SCL 钳在低位** → 主控只看到"传输超时"(-13) 而不是 NACK，且上拉再强也无用。
    这与实机现象（超时而非 NACK、重拉上拉无效、连纯读芯片ID都失败）完全吻合。
  · 原理图核对（Air8201G V1.5）：
      - `99 | VREF/GPIO23` + 网络 `VREF` + 标注 `pressure sensor` + 区块 `SENSOR`
      - `342: CAM_SI0 | CAM_SI1 | I2C1_SCL | I2C1_SDA | CAM_PDN`（I2C1 还引到 24pin 连接器 J18）
    → I2C1 上除 DA267 外还有其它器件/连接器，共用 VREF/供电。
  · ★ 与既有文档对上：05 文档 8202 段原文「PIN99 GPIO23 兼作 G-Sensor 供电 + VREF，
    **必须保持默认输出高**（否则 I2C1 初始化失败）」；且 8202 的 profile 本就是
    `gsensor.power_pin = 23`（lib/exvib.lua:231 注释"gsensor 开关"）→ 同源证据。
    **8201G 此前只设了 24，从未设过 23。**
  · board.lua（8201G）：新增 `gsensor.support_pins = { 28, 23, 24 }`：
      28 = AGPIO8/PIN78  → I2C1 10k 外部上拉（R16/R17）使能【已实机验证】
      23 = VREF/PIN99    → 传感器块供电 + VREF【图/同族】
      24 = AGPIO4/V_BCKP → 传感器与 SIM_CD 上拉供电【图/同族】
  · gsensor.lua：`assert_support()` 改为遍历 `support_pins`（未声明时回退为[上拉源,供电]，
    8201H/8202 现状不变）；**只拉高，绝不拉低** —— 断电复位仍只动 power_pin(24)，
    避免扰动 VREF 这类参考/供电源。
  · 自愈因此覆盖"VREF/支撑脚被外部扰动"这一新场景（每次 I2C 失败都会重新拉高）。
  · 验证（Lua 5.3 VM）：{28,23,24} 全量拉高 ✅；23 被扰动后自愈拉回并下一拍恢复 ✅；
    断电复位路径仅出现 `gpio:24=0`，**未出现 `gpio:23=0` / `gpio:28=0`** ✅；
    未声明 support_pins 时回退路径不变 ✅。
- 004.000.057：056 实机反馈 —— 发现 GPIO23/24 角色可能搞反（2026-09-17，8201G）
  · 056 实测结果：`板级 I2C1 支撑脚已全部拉高（28/23/24）` + 初始化成功 ✅；
    但 **I2C 仍在运行中失败**（18:40:58 `-6`）→ 全量拉高未解决该故障。
  · 硬证据（BSP 日志）：`bsp_bus_init io gpio23 output 1`
    → **GPIO23 是板级出厂即拉高的电源脚**（与 05 文档「PIN99 GPIO23 兼作 G-Sensor 供电+VREF，
      必须保持默认输出高」完全一致）。
  · ★★ 重大发现 —— 同族 8202 的 profile 里两个脚是分工的：
        `gsensor.power_pin = 23`（传感器供电/Vref）
        `wdt = { impl="air153c", feed_pin = 24, enable = true }`（看门狗喂狗脚）
      且 config.lua:120 记载硬件接线「AGPIO24 → NPN → WTDOG」，
      Air153C 超时固定 240s、喂狗周期需 >150s，喂狗动作是**输出低脉冲**。
      → **8201G 上我们把 24 当成 gsensor 供电并恒定拉高**：
        恒高 = 空闲态 = **从不喂狗 → Air153C 240s 超时 → 复位循环（R-18 被静态触发）**。
        实机印证：I2C 自愈后 2s 模块重启；开机间隔约 135s。
  · 处置（本版只做安全动作，不擅改硬件语义）：
      - `board.lua`（8201G）：新增 `power_cycle_recover = false`；
        并在 profile 内完整记录**正方/反方/硬证据**与两种后续二选一方案。
      - `gsensor.lua`：断电重上电改为**需 profile 显式开启**（默认关闭）——
        它是唯一会拉低 GPIO24 的动作，若 24 实为喂狗脚则有干扰风险。
      - GPIO24 的"拉高"行为**保持不变**（与 053~056 一致，不新增风险）。
  · 附带确认（好消息）：本版实机 `hmeta` 可用 ——
      `[board] 判据源: hmeta类型=table hmeta.model=Air780EGH hmeta.chip=EC718HM`，
      `source=hmeta` → **板型识别全链路正常**，此前"hmeta 取不到"的问题不再出现。
- 004.000.058：纠正引脚角色误判，恢复"断电重上电"（2026-09-18，用户确认口径）
  · ★ 用户权威确认：**8201G 无外接看门狗（无 Air153C）；GPIO24 是 G-Sensor 供电，接 V_BCKP。**
    → `gsensor.power_pin = 24` **本来就是对的**（05 文档「V_BCKP 由 GPIO24 控制供电」判定正确）；
      `wdt = { impl = "none" }` 也正确。
    → 057 中"GPIO24 可能是喂狗脚 / R-18 被静态触发"的判断**作废**：
      那次 18:41 重启**不是看门狗复位**。误判来源是 config.lua 那句
      「AGPIO24 → NPN → WTDOG」—— 那是 **8202 的接线**，我错误外推到了 8201G。
  · board.lua：8201G profile 的引脚角色注释改为权威口径；
    **`power_cycle_recover` 由 false 改回 true** —— GPIO24 就是传感器电源，
    切断 200ms 正是"器件失电/闩锁后 ESD 钳位总线"这类故障的正解（30s 限流）。
  · gsensor.lua：断电重上电的注释按确认后的事实重写（保留 `power_cycle_recover` 开关，
    便于其它板型按需关闭）。
  · config.lua：在 `WDT_CONFIG` 处显式标注"该接线描述仅适用于 8202，勿外推"，
    避免后续再次误判（本次教训）。
  · 保留不变：`support_pins = { 28, 23, 24 }`（上拉源 / VREF / 传感器供电）全量拉高。
- 004.000.059：长日志定位 —— 故障是 I2C 控制器状态，不是器件/线路（2026-09-18）
  · 长日志（11:09:49~11:10:04，794 行）关键事实：
      1) `I2c_failed` **117 次，全部错误码 -6「传输过程发生异常」，"传输超时"0 次**
         —— 与本轮之前几版的 -13 超时完全不同（056 加入 GPIO23 之后变形）。
      2) `gpio.setup 失败` **0 次** → 支撑脚(LED 28/23/24)可正常重配，**"引脚被收走"排除**。
      3) `11:10:04.278 重新配置传感器寄存器` → `11:10:04.293 初始化完成，量程: 2 g` ✅
         —— **lib.setup() 内含的 `i2c.close()+i2c.setup(SLOW)` 一跑总线即恢复**，
         且其后寄存器写 + 读芯片ID 全部通过。
         → ★ **器件是活的、线路是通的**；"器件失电 / ESD 钳位总线"假设**被证伪**。
      4) 失效起点：`11:09:58.216 流式采样开启(20Hz)`、
         `11:09:58.218/238 ★ 切功耗档 WORK_MODE=0`、`11:09:58.239 已恢复：中断+支撑脚`，
         首次失败 `11:09:58.240` —— 四者相隔 24ms，**无法区分**。
      5) `INT触发` 2 次（含 11:10:04.110）→ 传感器仍能拉中断线，佐证其活着。
      6) `判据源: hmeta.model=Air780EGH ... rtos.bsp=Air780EGH rtos.firmware=LuatOS-SoC_V2052_Air780EGH`
         → hmeta/rtos 全部可用，板型识别链路完整。
  · 处置：
      - gsensor.lua：**新增 `reinit_bus()`（官方 i2c.close + i2c.setup）作为第一优先恢复**
        （200ms 限流、只碰 i2c 不动 GPIO），在 read_g 检测到失败时立刻执行；
        其余三级自愈（重拉支撑脚/断电重上电/重配寄存器）保持为后续兜底。
      - gsensor.lua：新增**开机 30 秒总线探针**（每 2s 读一次，仅状态翻转时打印）
        —— 用于下次把"总线开始失败"的时刻与 `stream_start()` / `pm.power(WORK_MODE=0)`
        的时间线对齐，判定到底是谁打断的。
      - gsensor.lua：修正 heal() 里"器件失电→ESD钳位→超时(-13)"的旧叙事（已证伪）。
  · 验证：语法/依赖校验 PASS。
- 004.000.060：059 实机反馈 —— 故障是"间歇性传输异常"，不是全灭（2026-09-18）
  · 本版日志（t=3.1~16.5s）关键事实：
      1) `t=9.887 gsensor_stream: 4 样本` → 流式采样**曾经成功**；
         `t=10.211` 首次失败，此后失败持续到日志结束。
      2) **15 次 `i2c.close()+i2c.setup()` 重建──全部无效** ❌
         → 与上一份日志"`lib.setup()` 一跑就恢复"**矛盾**。
         差别：`lib.setup()` 除重建控制器外还会**重写一批器件寄存器**
         → **器件寄存器状态才是关键，单纯重建控制器不够。**
      3) `断电重上电`/`重新配置传感器` **0 次**，而 tier-1（重拉支撑脚）出现 3 次
         → `fail_cnt` 从未达 3 → 存在"`i2c_failed` 出现但**没有**配对'读取失败'"的情形
         → **失败是间歇的**（部分读失败但仍返回数据），总线**时好时坏**。
      4) 网络时间线压在故障起点上：
         `t=7.571 NETIF_LINK_ON` → `t=8.645 socket connect` → `t=9.535 getip 200`
         → `t=9.887 首次数据上报` → **`t=10.211 首次 I2C 失败`**
         → 指向"**射频/网络突发活动干扰 I2C**"（RF 突发 EMI）。
         旁证：故障码是 -6「传输过程发生异常」而非 -13「超时」、故障间歇、
         上拉/断电/控制器重建**全都无效** —— 三条都符合"电气干扰"而非"器件/配置故障"。
         硬件侧也合理：I2C1 的 10k 上拉（1.8V 域）偏弱，且 I2C1 还引到 24pin 连接器 J18（走线长）。
  · 处置：
      - gsensor.lua：**读取层加短重试**（`READ_RETRY = 3`，失败间隔 2ms 退避）
        —— 针对"间歇性传输异常"，可骑过短时干扰，避免上层数据空洞。
      - gsensor.lua：新增累计 `stat_ok`/`stat_fail` 计数，随自愈日志输出
        → 下次可直接量化"间歇程度"（成功率）。
      - gsensor.lua：总线探针首拍无条件打印一次，用于确认探针在跑并给出基线。
      - ★ 修复自愈设计缺陷：`heal()` 原在**每次**执行后都清零 `fail_cnt`，而 tier-1
        每 2s 就会跑一次 → 计数总被抹掉 → `fail_cnt` 永远到不了 3，
        **tier-2/3（断电重上电 / 重配寄存器）从此再也触发不了**（本版日志中均为 0 次）。
        改为**只有"读到有效数据"才清零**；tier-3 另加 10s 限流防止频繁重写寄存器。
      - 注：`reinit_bus()`（纯 i2c.close+setup）在本版实测**无效**（连做 15 次未恢复），
        故 tier-3 的"重配寄存器"才是关键恢复动作，必须能被触发。
  · 待验证（零代码实验，见回复）：**拔掉 SIM 卡跑一次** —— 若 I2C 不再失败，
    即坐实"射频干扰"这条假设（这是目前唯一能同时解释全部现象的解释）。
- 004.000.061：★ 找到漏掉的支撑脚 GPIO26（2026-09-18，用户提示查官方库用法）
  · 用户提示核对"库调用/引脚用法是否与官方一致" → 在 SDK 找到官方 Air8201G DA267 示例：
      module/Air8201/demo/gsensor/da267_app.lua
      ```
      gpio.setup(POWER_PIN, 1)   -- GPIO24: DA267供电
      if HARDWARE_ENV == "G" then
          gpio.setup(28, 1)      -- Air8201G: 开启I2C1总线上拉
          gpio.setup(26, 1)      -- Air8201G: 开启I2C1外围供电   ★ 我们漏了！
      end
      ```
  · → 官方明确：**8201G 的 I2C1 支撑脚是三只 —— 24 / 28 / 26**。本工程此前只有 24、28，
    还自行推测了 23（官方示例未列，但 BSP 出厂已配 `output 1`，保留无害）。
    **漏掉的 26 才是关键**：它是 I2C1「外围器件区」的供电使能。
  · 原理图佐证（Air8201G V1.5）：`25 | GPIO26` 紧邻 **NS2520**
    （`1|GND 2|CSB 3|SDI 4|SCK 5|SDO 8|VDD`，SDK 官方扩展库中即有 `exs_ns2520.lua`），
    且图上另有 `SENSOR` 区块 / `pressure sensor` 标注 / `I2C1` 引至 24pin 连接器 `J18`
    → **I2C1 上确实挂着 DA267 之外的器件，它们由 GPIO26 供电**。
  · ★ 这与全部现象吻合：**同总线器件未上电 → 其 ESD 保护二极管钳住 SDA/SCL**
    → 主控看到 -6「传输过程发生异常」（而非 -13 超时）、**间歇性**、
    与总线活动量相关、且**重拉上拉/断电/重建控制器全都无效**。
  · 代码：board.lua（8201G）`support_pins = { 24, 28, 26, 23 }`（四只全部拉高）。
    注：断电重上电仍只动 `power_pin = 24`，**不会**拉低 26/28（避免切断外围供电）。
  · 附：官方 demo 的 `int_pin = (HARDWARE_ENV=="G") and 20 or 39`、`POWER_PIN=24`、
    `addr=0x26` 与本工程 8201G 配置完全一致 ✅（映射无误；`exs_da267.lua` 与 SDK 官方
    文件 **SHA256 完全相同**：3C7A68EF...C68B1A）。
- 004.000.062：★ GPIO26 修复实机验证通过 + 清理调试日志（2026-09-18）
  · 实机日志（约 37 秒，1106 行）**全部正常**：
      `I2c_failed` 0 次、`读取加速度数据失败` 0 次、自愈 0 次触发；
      `支撑脚已全部拉高（全量清单= 24,28,26,23）` → `初始化完成，量程: 2 g`；
      20Hz 流式采样 10 秒收到 **198/200 个样本**（修复前仅 4 个）。
    → **根因确认：漏使能 GPIO26（I2C1 外围供电）**，导致同总线器件失电、
      其 ESD 二极管钳住 SDA/SCL，表现为间歇性 -6「传输过程发生异常」。
  · 清理调试日志（本次排障用，已无用）：
      - **删除** 开机 30 秒 I2C 总线探针（`bus_probe_task` / `[探针]` 日志）及其 taskInit；
      - **降级为 log.debug**（默认不输出，排障时改回 log.info 即可）：
        `INT触发 距上次震动`（震动灵敏度标定用）、
        `切功耗档 pm.WORK_MODE = 0/1`（drv_normal / drv_lowpower / active_mode 三处）。
  · 保留（均为**仅故障时**才输出的恢复路径日志，正常运行时零噪音）：
      `I2C 读取失败 → 重建 I2C 控制器` / `重新拉高板级支撑脚` /
      `重新配置传感器寄存器` / `给传感器断电重上电`，
      以及开机一行 `[board] 判据源: ...`（板型识别排障关键信息）。
  · 补充（防再犯）：`board.report()` 新增一行 `[board] I2C1 支撑脚: ...`，
    把"哪些脚必须在 I2C 前拉高"显式打印出来 —— 此前报告里只有"供电=24"，
    正是这行不完整导致我在 24 / 23 / 26 之间反复猜测。
- 004.000.063：对齐《工业模组出厂固件规划》的 AirCloud 上报字段（2026-09-23）
  · 依据：官方参考工程 module/Air780EPM/project/Air8780_factory
    （app/aircloud/aircloud_app.lua v1.2.0 2026.09.20）—— 文档 §3.1/§3.2 的权威实现。
  · 官方**必填**字段：SIGNAL_STRENGTH_4G(782) / CUSTOM_DEVICE_ID(1293) /
    CUSTOM_PROJECT_NAME(1294) / TIMESTAMP(1280)。
    官方**可选**字段：TEMPERATURE(256) / HUMIDITY(257) / PARTICULATE(258) /
    ENV_TEMPERATURE(263) / GNSS_LATITUDE(513) / GNSS_LONGITUDE(512)。
  · 本次**仅做纯新增**（改动现有报文的部分另发审批）：
      - 新增 TIMESTAMP(1280)：三处上报路径（active_mode / boot_lbs_report / create 兜底帧）全部补齐。
      - 新增 ENV_TEMPERATURE(263)：CPU 内部温度，按官方口径 `adc.CH_CPU 原始值 ÷ 1000`；
        实时上报模式(1s/帧)下跳过以避免高频开关 ADC；读不到则不插（可选字段）。
      - 已确认可用：`excloud.FIELD_MEANINGS.TIMESTAMP/ENV_TEMPERATURE`、
        `excloud.DATA_TYPES.FLOAT`(=0x1)、`adc.CH_CPU` 均已存在 ✅。
  · 待审批（涉及修改现有报文，未动）：
      ① Tag 1293/1294 语义撞车：本项目用作 三轴流式(1293)/NMEA流式(1294)，
         与官方 CUSTOM_DEVICE_ID(1293)/CUSTOM_PROJECT_NAME(1294) 冲突；
      ② GNSS 经纬度(512/513) 本项目发 ASCII，官方要求 FLOAT；
      ③ 上报周期默认 300s(GNSS关)/10s(GNSS开)，文档要求 180s；
      ④ 下行 CONTROL_COMMAND(19) 的 `cycle:N` / `led:blink|on|off` 尚未实现。
- 004.000.064：按《工业模组出厂固件规划》审批结果执行（2026-09-23）
  · 用户审批：①号段迁移 同意 ②经纬度按官方改 FLOAT ③新建独立 180s 上报任务 ④下行控制并存
  · ① **字段号段迁移（避与官方撞车）**：本项目自定义 1292~1295 → **1300~1303**
        1300=单点三轴(原1292)  1301=20Hz三轴流(原1293)
        1302=NMEA流(原1294)    1303=实时1秒三轴流(原1295)
      并将 **1293/1294 让给官方语义**：CUSTOM_DEVICE_ID(hmeta.devid()) / CUSTOM_PROJECT_NAME(PROJECT)，
      已加入 active_mode 主上报（官方**必填**）。
      · excloud.lua：新增 `FIELD_MEANINGS.CUSTOM_DEVICE_ID=1293 / CUSTOM_PROJECT_NAME=1294` 常量，
        并在注释中记录 1300 号段映射；
      · 同步更正各文件里引用旧编号的注释（active_mode / location / remote / gsensor / board / excloud），
        并在 active_mode 头部加了**号段迁移公告**（注明历史注释可能仍有旧编号，以 field_meaning 为准）。
  · ② **经纬度 512/513 改为 FLOAT**（官方口径）：active_mode + boot_lbs_report 两处，
      由 ASCII `tostring()` 改为 `tonumber()` 传 FLOAT；解析不出数字则不上报该字段。
  · ③ **新增 modules/factory_report.lua**：独立 180s 周期上报任务（不与现有业务冲突）
      - 字段严格按官方：必填 782/1293/1294/1280；可选 263(CPU温度, adc.CH_CPU÷1000) /
        513/512(LBS, location.get_lbs_location)。
      - 复用 boot_lbs_report 的成熟模式（等 IP_READY → 等 CLOUD_CONNECTED → 周期上报），
        失败不影响下一轮；`create.send_aircloud` 为唯一上行通道。
      - 周期默认 180s，可经下行 `cycle:N` 修改，**写入 fskv 断电不丢**；每轮重读，下一轮生效。
      - app.lua 中 `factory_report.start()` 启动（幂等）。
  · ④ **下行 CONTROL_COMMAND(19) 处理，与既有 REMOTE_COMMAND 并存**（create.lua）：
      - `cycle:N`（≥5s）→ factory_report.set_cycle；`led:blink|on|off` → tools.led_force。
      - 结果通过 CONTROL_RESPONSE(20, ASCII) 回复。
      - **并存**：tag 19 处理完后**仍照常发布 REMOTE_COMMAND**，既有协议零回归。
      - utils/tools.lua：新增最高优先级的 `led_force` 通道（on/off/blink5s），
        命中时跳过自动 LED 状态机，blink 到期自动交还。
  · 未改动：复用官方 exs_da267 的传感器链路、现有 active_mode 上报节奏与内容。
- 004.000.044：8201G 实机第三轮（2026-09-17）
  · 电池：实测 ADC0 稳定读到 3390mV（×分压=14690mV，正好是应有值 969mV 的 3.499 倍）
    → 高度怀疑 adc.setRange() 未生效（软件按 3.8V 档换算 ×3.5，硬件却未走分压）。
    新增一次性诊断：打印量程常量实际数值 + 同一通道在"关分压/开分压"两种量程下的读数
    + 模组内部 VBAT 通道(adc.CH_VBAT)对照值 → 一次开机即可定论。
  · SIM：卡实体插在 SIM0，而 8201G 的兜底卡槽原为 SIM1（沿用 8202 双卡槽历史默认值）
    → 检测脚读不到时会长期停在 SIM1，表现为"插卡不识别"。改为 boot_default = 0(SIM0)。
  · SIM：新增「2s 延迟复检 + 自动纠正卡槽」，避免开机早期读数失败导致长期用错卡槽。
]]
PROJECT = "Air8202"
VERSION = "004.000.064"
FOTA_MODE = 3  -- 3=libfota3(默认,只能合宙人员根据客户提供的IMEI升级,客户无法自行操作), 2=libfota2(IoT平台,客户自行管理)

-- ====== 项目密钥（FOTA升级使用，libfota3 和 libfota2 统一从此读取） ======
PRODUCT_KEY = "qXY4ibFBFnnRoEFPRTuCl3k1wu4vq1WX"
-- ==========================================================================

-- ====== ★ 构建期兜底板型 BOARD_DEFAULT（仅在"型号自报失败"时生效） ======
-- 型号判据只有一个：**hmeta.model()**（官网指定，LuatOS 核心库）。
-- board.lua 已把它作为第一优先级判据源（按全局访问；工程红线：核心库不得用模块加载方式引用）。
--
-- 背景（2026-09-17 上机实测，Air780EGH 固件 LuatOS-SoC_V2052）：
--   该次运行中 hmeta.model() 取到 nil，rtos.bsp() 也为 nil
--   （SDK 实现为 lua_pushstring(L, luat_os_bsp())，本 BSP 下该值为空）
--   → 全部字符串判据源失效 → 落入 unknown 兜底
--   → **静默关闭 SIM 在位检测 / LED / 电池 / 充电检测 / 看门狗**，表现为
--     "能开机、能打印日志，但插卡不识别、电压恒 0、功能全废"。
--   注意：C 层 luat_hmeta_model_name() 实测是好的（pins 库已成功取得 "Air780EGH"），
--   所以 004.000.042 补了「判据源可用性」启动日志 + 8s 延迟复检，
--   用于区分「核心库未就绪/取不到」与「T0 时机未到（后续可用）」。
--
-- ★★ 给哪个型号出固件，就把下面改成哪个：
--      BOARD_DEFAULT = "8201G"   -- Air8201G（主控 Air780EGH）
--      BOARD_DEFAULT = "8201H"   -- Air8201H（主控 Air780EHM）
--      BOARD_DEFAULT = "8202"    -- Air8202 （主控 Air780EGG）
--    改完必须重新烧录。切勿把为某型号构建的固件烧到其它型号板上。
--
-- 说明：这是**兜底**，不是覆盖。hmeta.model() 能自报型号时自动识别照常生效
--       （source=hmeta），本常量不参与。
-- 取值：nil / "8202" / "8201G" / "8201H"；填错或填 nil 且判据全失效 → unknown + 显式报错。
BOARD_DEFAULT = nil
-- ==========================================================================

-- 初始化 fskv（board.init 读取 board_force 覆盖项需要，app/kvstore 亦依赖）
fskv.init()

-- ====== T0 板型识别（单固件多型号自适应的唯一入口） ======
-- 必须在任何"require 期求值引脚"的模块（config / utils/tools 等）之前完成：
-- 识别为纯字符串判定（hmeta.model 主判据 + rtos.bsp 交叉校验 + fskv board_force 覆盖），
-- 内部无 I/O、无 sys.wait，可安全在此同步调用。
-- 识别结果经 board.profile 注入 config（LED / 充电 CMD / 喂狗脚等），业务层不感知板型。
local board = require("board")
board.init()
-- ======================================================

-- ====== SIM 卡槽选择与热插拔检测（SIM0 在位检测，拔出回落 SIM1） ======
-- 必须在任何联网动作（FOTA / 驻网 / 云连接）之前执行：
--   · 开机读板级 SIM0 检测脚电平（board.profile.sim.det_pin；
--     硬件确认：8202 = WAKEUP0 / 8201G = WAKEUP2 / 8201H = WAKEUP2）→ 高 = SIM0 / 低 = SIM1
--   · 随后把该脚配为热插拔中断：下降沿(拔出) 切 SIM1 / 上升沿(插入) 切 SIM0，
--     切换时按官网要求"进出一次飞行模式"并遵守 simid 与 flymode 的互斥约束
-- 详见 sim_slot.lua
local sim_slot = require("sim_slot")
sim_slot.init()
-- ======================================================================

-- ====== FOTA 升级：开机即执行（与工作模式无关），之后每8小时自动检测一次 ======
-- update.init() 内部为异步后台执行，不阻塞开机流程
local update = require("update")
update.init()
-- ============================================================

-- 正常启动流程：加载本地配置 → 启动云连接 → 启动 app → 后台异步获取最新配置
local function start_app()
    log.info("main", "出厂测试已完成，加载配置")

    -- 1. 加载本地持久化配置（参考 iRTU default.init）
    local cfg_fetch = require("cfg_fetch")
    local sheet = cfg_fetch.init()

    local config = require("config")

    -- 判断本地持久化配置是否为有效定位版配置（含非空 network 通道定义）
    -- 采集版/未配置/空 gnss 一律视为无有效配置，回退默认 AirCloud
    local has_valid_gnss = false
    if sheet and type(sheet.gnss) == "table" then
        local network = sheet.gnss.network
        if type(network) == "table" and type(network.conf) == "table" and #network.conf > 0 then
            has_valid_gnss = true
        end
    end

    if has_valid_gnss then
        -- 有本地有效定位版配置，应用到 config 模块
        config.load_from_server(sheet.gnss, sheet.project_key)
        log.info("main", "已加载本地持久化配置，param_ver:", sheet.param_ver)

        -- 先初始化远程控制模块，确保能接收后续的下行命令
        local remote = require("remote")
        remote.init()

        -- 2. 启动云平台连接（参考 iRTU create.start）
        local create = require("create")
        create.start(sheet)
        log.info("main", "云平台连接已启动")
    else
        log.info("main", "无有效定位版配置（采集版/未配置），使用默认配置")
        -- 默认配置：通道1 连接 AirCloud（TLV 直发合宙云平台）
        local create = require("create")
        create.start({gnss = {network = config.DEFAULT_NETWORK}})
    end

    -- 3. 后台异步获取最新配置 — 本版本已禁用，不向网页端拉取配置
    --    如需恢复，取消下方注释即可
    -- cfg_fetch.start()
    log.info("main", "已禁用网页端配置拉取，使用本地/默认配置")

    -- 4. 启动应用
    local app = require("app")
    sys.wait(2000)
    app.start()

    -- 5. 开机联网后单独执行一次 LBS 定位并上报（独立运行，不与其他逻辑冲突）
    local boot_lbs_report = require("boot_lbs_report")
    boot_lbs_report.start()
end

-- ========== 启动（产测已整体移除） ==========
-- 历史版本的 BOOT_MODE(0/1/2) 与产测分支已按产品决策删除：
-- 本套软件不需要产测功能，启动链固定为唯一路径，避免"未完成产测则进产测"导致
-- 识别失败板型进入错误流程。
log.info("main", "启动应用（板型:", tostring(board.id), "）")
sys.taskInit(start_app)

-- 用户代码已结束---------------------------------------------
sys.run()
-- sys.run()之后不要加任何语句!!!!!
