--[[
@module  periph_rs485
@summary RS485 外设驱动（config.peripherals 中 type="rs485"，支持多路）
@version 1.6
@date    2026.10.24
@author  江访

=== 配置示例 ===

config/eng_xxx.lua 声明（同一 type 可多条，靠 id 区分）：
   peripherals = {
       { type = "rs485", id = "485_1", name = "非隔离485", uart_id = 1,
         de_pin = 65, power_pin = 14, baud = 9600 },
       { type = "rs485", id = "485_2", name = "隔离485",   uart_id = 1,
         de_pin = nil, power_pin = 14, baud = 9600 },
   }

=== 接口 ===

M.init(params)     → handle | false, err
M.list()           → { {id=, name=, handle=}, ... }
M.get(id)          → handle
M.de_hold(ms)      → ok, ms, pins, bad   把全部 DE 脚拉高 ms 毫秒再回接收态（现场量方向脚用）
M.reset_all()      → 关闭全部实例并清空注册表

handle.id / handle.name / handle.params
handle:start()     → ok, err     上电 + DE 置接收态 + 打开串口
handle:send(data)  → ok, err     串行发送一帧：DE 置发送态 → 发送 → 等发送完成 → DE 置接收态
handle:recv()      → data|nil    取走环形缓冲里的全部接收数据（拉取式）
handle:stop()      → ok          关闭串口 + DE 置接收态 + 释放供电
handle:status()    → { enabled=bool, info=string }

=== 事件 ===

收到数据时逐包广播：sys.publish("PERIPH_RX", handle.id, data)
订阅方（如 ui/rs485_test_win.lua）自行拼历史记录，驱动不维护发送历史。

=== 约定 ===

- power_pin 为所在供电域总使能脚，多路共用同一 power_pin：引用计数管理，每次 start 都重申高电平
  （不只首路：供电域可能被别的路径拉低过）。power_hold = true 表示该域由 config.power_on
  常供电（如 8603 的 485_EN = GPIO64），驱动只补高、不关断；其余域仍是末路断电才拉低
- de_pin 可为 nil（该路 DE 未引出 / 自动方向），缺失时自己不驱动。**本路缺 de_pin 又在同一
  串口上配了别的 de_pin 时，发送会翻的是兄弟路的 DE**：本路的收发器仍停在接收态、发不出去，
  日志会打 `本路缺 de_pin，发送时翻的是同串口其它路的 DE` 告警，这种路必须补上真实 DE 脚
- **同一 uart_id 上各路的 DE 脚一起切向**：共用一根 TX 的多路是同一帧从各自的收发器同时
  出去，发的时候把这一串口上出现过的所有 de_pin 一起拉高、发完一起拉低。只翻自己那一路，
  另一路的收发器仍停在接收态，那一侧的物理口就发不出数据
- 同一 uart_id 上的多条记录共享一个物理串口：**只有该串口的第一路才 uart.setup**，
  后续各路只并入用户表。uart.setup 对已打开的串口会报 "uartX is opened!" 并返回失败，
  逐路 setup 会让第二路必然 start 失败。同理只有末路 stop 时才 uart.close
- 同一 uart_id 上的多条记录共享该串口的收发计数与环形缓冲；一路收到数据会逐条广播
  PERIPH_RX，同串口的其它路也会各收到一份。**这是串口镜像，不是各路各自的收包**：
  跨路判定必须要求收发两端在不同 uart_id 上，否则自己的回环会经镜像被误判成对端收到
- 同一 uart_id 上各路波特率应保持一致；不一致时沿用先打开那路的波特率并告警
- de_pin 接收态为低电平，发送态为高电平。**空闲时就是低电平**：半双工总线平时必须停在接收态，
  所以打开串口后方向脚一直是 0V 是对的，它只在每一帧的发送窗口里拉高（9600 波特率发 3 字节约
  6~8ms），万用表量永远是 0V。要确认它真的会翻，用 `M.de_hold(ms)` 拉高一段够长的时间再量
- **半双工自回环**：485 收发器会在发送期间把总线上的自己发的字节回采到 RX。
  发送窗口（串口占用期间）收到的字节一律丢弃，窗口前后各 uart.rxClear 一次清残留，
  避免把自己的回环当成对端数据
- **同一串口发送串行化**：tx_busy 按 uart_id 记账，前一帧的 DE 释放完成前不发下一帧，
  否则连续发送会互相踩 DE 方向切换
- **发送完成判定**：DE 必须覆盖整帧。先等满按波特率估算的帧时长（(字节数+2)×12 位 + 2ms），
  再看 uart.on(id,"sent") 有没有到，没到就继续等到它来（最多再等两倍预算），再调 uart.wait485
  等平台自己排空移位寄存器，末尾 2ms 让停止位出完、总线释放。**不拿 sent 提前结束**：有些固件
  的 sent 在 FIFO 排空就触发，比移位发完早，提前松 DE 会把帧尾截掉，对端收到半帧就当没收到。
  连着没到过 sent 就当固件不支持这个回调（记 sent_off），之后只按估算的帧时长等，不白等
- 现场排查看这几条日志：`发送 <id> UART<n> <len> 字节 DE=<脚号:电平,…>`、`发送完成 <id> 等Xms
  预算Yms sent已到|sent未到 wait485=<N> DE=<脚号:电平,…>`、`发送失败 <id> <原因>`、
  `收到 UART<n> <len> 字节 广播<N>路`、`UART<n> 发送期间丢弃回环`、`收包回调空读`。
  DE 那段带**回读电平**，发前是 `脚:1`、发完是 `脚:0`；电平不对说明方向脚没写进去。
  `收包回调空读` 说明串口中断到了但读不出字节；连这条都没有就是链路上根本没进数据。
  一条 `发送` 都没有说明发送没走到驱动。收不到对端数据先看这几条分清
  「没发出去」「DE 没切成发送态」「发了但 DE 提前松」「发出去了但对端没回」
- 所有 uart.* / gpio.* 调用 pcall 包裹，失败返回 false + 错误串
- 供电脚经 airlink_pin 下发：GPIO ≥100 的 WiFi 侧脚等 airlink 链路就绪后再驱动
]]

local airlink_pin = require "airlink_pin"

local M = {}

-- 环形缓冲保留条数
local RING_MAX = 8

-- 已登记实例：id → handle
local instances = {}
-- 已登记实例：uart_id → { handle, ... }
local uart_users = {}
-- 供电脚引用计数：pin → 次数
local power_ref = {}
-- 串口发送占用：uart_id → true（发送期间收包按半双工回环丢弃，下一帧须等它释放）
local tx_busy = {}
-- 串口发送完成标记：uart_id → true（uart.on(id,"sent") 置位，发送任务消费）
local tx_sent = {}
-- 该串口的 sent 回调从没到过：固件多半不支持它，不再为它多等（每次发送结算时记）
local sent_off = {}
-- 各串口用到过的 DE 脚：uart_id → { pin, ... }（登记时就记，与该路是否已打开无关）
local uart_de_pins = {}

-- 校验位 → uart 校验常量
local function parity_to_const(p)
    if type(p) == "number" then return p end
    local s = tostring(p or "N"):upper()
    if s == "E" or s == "EVEN" then return uart.Even end
    if s == "O" or s == "ODD" then return uart.Odd end
    return uart.None
end

-- 等待毫秒，非协程环境跳过（sys.wait 只能在可让出的协程里调）
local function safe_wait(ms)
    if not ms or ms <= 0 then return end
    if not (coroutine and coroutine.isyieldable and coroutine.isyieldable()) then return end
    pcall(sys.wait, ms)
end

-- 读取 GPIO 电平（回读用，判 pin_set 有没有真生效）
local function pin_get(pin)
    if not pin then return nil end
    local ok, v = pcall(gpio.get, pin)
    if ok then return v end
    return nil
end

-- DE 脚电平回读串：形如 "58:1,57:0"，排查看电平有没有真写进去
local function de_level_text(pins)
    local out = {}
    for i = 1, #pins do
        out[#out + 1] = tostring(pins[i]) .. ":" .. tostring(pin_get(pins[i]))
    end
    return table.concat(out, ",")
end

-- 方向脚列表串：形如 "GPIO58/GPIO57"，界面上直接显示
local function pin_name_text(pins)
    local out = {}
    for i = 1, #pins do
        out[i] = "GPIO" .. tostring(pins[i])
    end
    return table.concat(out, "/")
end

-- 设置 GPIO 电平（WiFi 侧脚等 airlink 链路就绪后下发）
local function pin_set(pin, level)
    if not pin then return end
    airlink_pin.set(pin, level)
end

-- 本串口上所有路的 DE 脚（去重），extra 用于补上尚未入表的那一路
-- 同一 uart_id 的多路共用一根 TX：发的时候它们是同一帧从各自的收发器同时出去，
-- DE 必须一起切向，只翻自己那一路会让另一路的收发器仍停在接收态、帧发不出去
local function de_pins_of(uart_id, extra)
    local seen, out = {}, {}
    local function add(pin)
        if pin and not seen[pin] then
            seen[pin] = true
            out[#out + 1] = pin
        end
    end
    -- 登记表按 uart 记 DE 脚，与该路是否已 start 无关：只开一路时另一路的 DE 也得跟着翻
    local reg = uart_de_pins[uart_id]
    if reg then
        for i = 1, #reg do add(reg[i]) end
    end
    local users = uart_users[uart_id]
    if users then
        for i = 1, #users do add(users[i].params.de_pin) end
    end
    add(extra)
    return out
end

-- 一起切换本串口上全部 DE 脚
local function de_set(uart_id, level, extra)
    local pins = de_pins_of(uart_id, extra)
    for i = 1, #pins do pin_set(pins[i], level) end
end

-- 供电脚上电（引用计数 +1）
-- 每次都重申高电平，不只在首路：供电域可能被别的路径拉低过，进来就得把电平钉住
local function power_acquire(pin, hold)
    if not pin then return end
    local n = (power_ref[pin] or 0) + 1
    power_ref[pin] = n
    pin_set(pin, 1)
    if n == 1 then
        log.info("periph_rs485", "485 供电上电", "GPIO" .. tostring(pin))
    end
end

-- 供电脚断电（引用计数 -1，末路才拉低）
-- power_hold 的供电域由 config.power_on 常供电（如 8603 的 485_EN = GPIO64），
-- 驱动只负责补高，不负责关断，否则关掉最后一路会把整组 485 的电一起掐掉
local function power_release(pin, hold)
    if not pin then return end
    local n = power_ref[pin] or 0
    if n <= 1 then
        power_ref[pin] = nil
        if n ~= 1 then return end
        if hold or pin == 12 then
            log.info("periph_rs485", "485 供电保持", "GPIO" .. tostring(pin))
        else
            pin_set(pin, 0)
            log.info("periph_rs485", "485 供电断电", "GPIO" .. tostring(pin))
        end
        return
    end
    power_ref[pin] = n - 1
end

-- 串口发送完成回调：置位标记，发送任务据此提前释放 DE（uart 未支持 sent 时靠估算兜底）
local function on_sent(uart_id)
    tx_sent[uart_id] = true
end

-- 把串口接收缓冲读空，拼成本次收到的完整数据块
-- 半双工 485 一次中断只读 len 字节会留下残片，下一片要等下一次中断，慢一拍
local function read_all(uart_id)
    local out = ""
    repeat
        local ok, s = pcall(uart.read, uart_id, 256)
        if not ok or type(s) ~= "string" or #s == 0 then break end
        out = out .. s
    until false
    return out
end

-- 串口接收回调：读空缓冲写入环形缓冲、累计接收计数并广播给订阅方
-- 回调到了但读不出字节也记一条：只靠「有没有收到日志」分不清「没收到」和「读不到」
local function on_receive(uart_id, len)
    local users = uart_users[uart_id]
    if not users then return end
    local data = read_all(uart_id)
    if #data == 0 then
        local ok_sz, sz = pcall(uart.rxSize, uart_id)
        log.warn("periph_rs485", "收包回调空读", "UART" .. tostring(uart_id),
                 "len=" .. tostring(len), "rxSize=" .. tostring(ok_sz and sz or "?"))
        return
    end
    -- 发送窗口内收到的是自己的回环（半双工收发器会回采），丢弃不上报
    if tx_busy[uart_id] then
        log.info("periph_rs485", "UART" .. tostring(uart_id) .. " 发送期间丢弃回环", #data, "字节")
        return
    end
    log.info("periph_rs485", "收到", "UART" .. tostring(uart_id), #data, "字节",
             "广播" .. tostring(#users) .. "路")
    for i = 1, #users do
        local h = users[i]
        h.rx_count = h.rx_count + #data
        local ring = h.rx_ring
        ring[#ring + 1] = data
        while #ring > RING_MAX do table.remove(ring, 1) end
        sys.publish("PERIPH_RX", h.id, data)
    end
end

-- 计算 DE 方向切换等待时长（毫秒）
local function tx_delay_ms(self, datalen)
    local p = self.params
    if p.tx_delay then return p.tx_delay end
    local baud = p.baud or 9600
    if baud <= 0 then return 5 end
    return math.floor((datalen + 2) * 12 * 1000 / baud) + 2
end

-- 等这一帧真正出完再释放 DE
-- DE 必须覆盖整帧：先等满按波特率估算的帧时长，再看 uart.on(id,"sent") 有没有到，
-- 没到就继续等到它来（或再等满两个预算），再用 uart.wait485 等平台的移位寄存器排空，
-- 末尾 2ms 让停止位出完、总线释放
-- 不拿 sent 提前结束：有些固件的 sent 在 FIFO 排空就触发，比移位发完早，提前松 DE 会截断帧
-- 每次发送都确认一下 sent 到没到，连着没到就当固件不支持它（sent_off），之后只按估算等
-- 返回 等待毫秒, sent到没到, uart.wait485 的返回（不为 0 说明估算的等待还不够长）
local function wait_tx_done(uart_id, budget_ms)
    if not budget_ms or budget_ms < 1 then budget_ms = 1 end
    local waited = 0
    while waited < budget_ms do
        if not (coroutine and coroutine.isyieldable and coroutine.isyieldable()) then break end
        pcall(sys.wait, 1)
        waited = waited + 1
    end
    local sent_ok = tx_sent[uart_id] and true or false
    while not sent_ok and not sent_off[uart_id] and waited < budget_ms * 3 do
        if not (coroutine and coroutine.isyieldable and coroutine.isyieldable()) then break end
        pcall(sys.wait, 1)
        waited = waited + 1
        sent_ok = tx_sent[uart_id] and true or false
    end
    sent_ok = tx_sent[uart_id] and true or false
    sent_off[uart_id] = not sent_ok
    tx_sent[uart_id] = nil
    -- 平台自己的「等 485 发完」：mcu 有移位寄存器空中断的芯片上靠它兜住最后一段
    local ok_w, loops = pcall(uart.wait485, uart_id)
    if not ok_w then loops = 0 end
    safe_wait(2)
    return waited, sent_ok, loops
end

-- 抢串口发送占用：同一串口的前一帧没发完不许发下一帧，否则 DE 方向会被踩乱
local function tx_acquire(uart_id)
    local waited = 0
    while tx_busy[uart_id] and waited < 2000 do
        if not (coroutine and coroutine.isyieldable and coroutine.isyieldable()) then break end
        pcall(sys.wait, 2)
        waited = waited + 2
    end
    tx_busy[uart_id] = true
end

-- 释放串口发送占用
local function tx_release(uart_id)
    tx_busy[uart_id] = nil
    tx_sent[uart_id] = nil
end

-- 打开串口（上电 → DE 接收态 → 本串口首路才 uart.setup）
local function rs485_start(self)
    local p = self and self.params
    if not p then return false, "invalid handle" end
    if not p.uart_id then return false, "missing uart_id" end
    if self.enabled then return true end

    power_acquire(p.power_pin, p.power_hold)
    de_set(p.uart_id, 0, p.de_pin)

    local baud = p.baud or 9600
    local users = uart_users[p.uart_id]
    if not users then
        users = {}
        uart_users[p.uart_id] = users
    end

    if #users == 0 then
        local ok, ret = pcall(uart.setup, p.uart_id, baud, p.databits or 8, p.stopbits or 1,
                              parity_to_const(p.parity))
        if not ok or (ret ~= nil and ret ~= 0) then
            uart_users[p.uart_id] = nil
            power_release(p.power_pin, p.power_hold)
            return false, string.format("UART%d 打开失败: %s", p.uart_id, tostring(ret))
        end
        ok, ret = pcall(uart.on, p.uart_id, "receive", on_receive)
        if not ok then
            log.warn("periph_rs485", "接收回调注册失败", self.id, ret)
        end
        ok, ret = pcall(uart.on, p.uart_id, "sent", on_sent)
        if not ok then
            log.warn("periph_rs485", "发送完成回调注册失败", self.id, ret)
        end
    else
        -- 该串口已由同表其它路打开：直接并入用户表，沿用已建好的串口与接收回调
        local owner = users[1]
        if owner.baud and owner.baud ~= baud then
            log.warn("periph_rs485", "同一 UART 波特率不一致，沿用已打开的",
                     p.uart_id, owner.baud, baud)
            baud = owner.baud
        end
    end

    self.baud     = baud
    self.tx_count = 0
    self.rx_count = 0
    self.rx_ring  = {}
    self.enabled  = true
    users[#users + 1] = self

    log.info("periph_rs485", "485 已打开", self.id, p.uart_id, baud, #users,
             "DE=" .. de_level_text(de_pins_of(p.uart_id, p.de_pin)))
    return true
end

-- 发送数据（DE 切换到发送态，发完等真正出完再切回接收态）
-- 半双工 485 自己发的字节会被收发器回采到 RX，整个发送窗口按回环丢弃，
-- 窗口前后各清一次串口接收缓冲，残片不会被当成对端发来的数据
local function rs485_send(self, data)
    if not self or not self.enabled then return false, "not started" end
    if type(data) ~= "string" or #data == 0 then return false, "empty data" end
    local p = self.params
    local uid = p.uart_id

    tx_acquire(uid)
    pcall(uart.rxClear, uid)          -- 丢掉占用前的历史残留
    local de_pins = de_pins_of(uid, p.de_pin)
    de_set(uid, 1)
    log.info("periph_rs485", "发送", self.id, "UART" .. tostring(uid), #data, "字节",
             "DE=" .. de_level_text(de_pins))
    -- 本路没配 de_pin 却在翻兄弟路的 DE：翻的是别人的收发器，本路的收发器停在接收态发不出去
    if not p.de_pin and #de_pins > 0 then
        log.warn("periph_rs485", "本路缺 de_pin，发送时翻的是同串口其它路的 DE",
                 self.id, "UART" .. tostring(uid), "DE=" .. table.concat(de_pins, ","))
    end

    local ok, ret = pcall(uart.write, uid, data)
    if not ok then
        de_set(uid, 0)
        pcall(uart.rxClear, uid)
        tx_release(uid)
        log.warn("periph_rs485", "发送失败", self.id, tostring(ret))
        return false, "uart.write: " .. tostring(ret)
    end

    local budget = tx_delay_ms(self, #data)
    local waited, sent_ok, wait485 = wait_tx_done(uid, budget)
    de_set(uid, 0)
    pcall(uart.rxClear, uid)          -- 丢掉发送窗口里回采进来的自己的字节
    tx_release(uid)
    log.info("periph_rs485", "发送完成", self.id, "等" .. tostring(waited) .. "ms",
             "预算" .. tostring(budget) .. "ms", sent_ok and "sent已到" or "sent未到",
             "wait485=" .. tostring(wait485), "DE=" .. de_level_text(de_pins))

    if type(ret) == "number" and ret > 0 then
        self.tx_count = self.tx_count + ret
    else
        self.tx_count = self.tx_count + #data
    end
    return true
end

-- 取走环形缓冲里的全部接收数据（拉取式；订阅 PERIPH_RX 的一方无需调用）
local function rs485_recv(self)
    if not self then return nil end
    local ring = self.rx_ring
    if type(ring) ~= "table" or #ring == 0 then return nil end
    local data = table.concat(ring)
    self.rx_ring = {}
    return data
end

-- 关闭串口（DE 接收态 → 释放供电）
local function rs485_stop(self)
    if not self then return false end
    if not self.enabled then return true end
    local p = self.params

    if p.uart_id then
        local users = uart_users[p.uart_id]
        if users then
            for i = #users, 1, -1 do
                if users[i] == self then table.remove(users, i) end
            end
            if #users == 0 then
                uart_users[p.uart_id] = nil
                tx_release(p.uart_id)
                pcall(uart.close, p.uart_id)
            end
        end
    end
    de_set(p.uart_id, 0, p.de_pin)
    power_release(p.power_pin, p.power_hold)
    self.enabled = false
    log.info("periph_rs485", "485 已关闭", self.id)
    return true
end

-- 读取状态
local function rs485_status(self)
    if not self then return { enabled = false, info = "invalid" } end
    local p = self.params or {}
    local de = p.de_pin and ("DE:GPIO" .. tostring(p.de_pin)) or "DE:自动"
    return {
        enabled = self.enabled and true or false,
        info = string.format("%s | UART%d | %s | %d", self.id or p.id or "?",
                             p.uart_id or 0, de, self.baud or p.baud or 9600),
        stats = { tx = self.tx_count or 0, rx = self.rx_count or 0 },
    }
end

-- 创建 handle 并挂载方法
local function make_handle(params)
    local h = {
        id      = params.id,
        name    = params.name or params.id,
        params  = params,
        enabled = false,
        tx_count = 0,
        rx_count = 0,
        rx_ring  = {},
    }
    h.start  = rs485_start
    h.send   = rs485_send
    h.recv   = rs485_recv
    h.stop   = rs485_stop
    h.status = rs485_status
    return h
end

--[[
登记 RS485 实例（不打开串口）
@param table params  config.peripherals 条目
@return table|false  handle 或 false, 错误串
]]
function M.init(params)
    if type(params) ~= "table" then return false, "params must be table" end
    if not params.id then return false, "missing id" end
    if not params.uart_id then return false, "missing uart_id" end
    if instances[params.id] then return false, "duplicated id: " .. tostring(params.id) end
    local h = make_handle(params)
    instances[params.id] = h
    -- 记下这一串口用到的 DE 脚：同串口多路共用一根 TX，发的时候要一起切向，
    -- 且与该路是否已打开无关（只开一路时另一路的 DE 也得跟着翻）
    if params.de_pin then
        local reg = uart_de_pins[params.uart_id]
        if not reg then
            reg = {}
            uart_de_pins[params.uart_id] = reg
        end
        local dup = false
        for i = 1, #reg do
            if reg[i] == params.de_pin then dup = true end
        end
        if not dup then reg[#reg + 1] = params.de_pin end
    end
    log.info("periph_rs485", "485 已登记", params.id, params.uart_id)
    return h
end

--[[
列出已登记实例
@return table  { {id=, name=, handle=}, ... }
]]
function M.list()
    local out = {}
    for id, h in pairs(instances) do
        out[#out + 1] = { id = id, name = h.name, handle = h }
    end
    return out
end

--[[
取单个实例 handle
@param string id  实例 id
@return table|nil  handle
]]
function M.get(id)
    return instances[id]
end

--[[
方向脚自检：把全部已登记的 DE 脚拉高一段时间再回接收态
供现场用万用表量方向脚用：正常发送窗口只有几毫秒，表笔看不出电平跳变
拉高期间逐脚回读电平，回读不是高电平的脚列进 bad
@param number ms  保持高电平的毫秒数，缺省 2000，钳在 100~10000
@return boolean, number, string, string
  是否执行, 实际保持的毫秒数, 拉高的方向脚(形如 "GPIO65/GPIO46"),
  回读不到位的脚(形如 "GPIO46"，全部到位为空串)
]]
function M.de_hold(ms)
    ms = tonumber(ms) or 2000
    if ms < 100 then ms = 100 end
    if ms > 10000 then ms = 10000 end

    local pins, seen = {}, {}
    local function add(pin)
        if pin and not seen[pin] then
            seen[pin] = true
            pins[#pins + 1] = pin
        end
    end
    for _, reg in pairs(uart_de_pins) do
        for i = 1, #reg do add(reg[i]) end
    end
    for _, h in pairs(instances) do
        add(h.params and h.params.de_pin)
    end
    if #pins == 0 then return false, 0, "", "" end

    for i = 1, #pins do pin_set(pins[i], 1) end
    log.info("periph_rs485", "DE 自检拉高", de_level_text(pins), "保持", ms, "ms")
    local bad = {}
    for i = 1, #pins do
        if pin_get(pins[i]) ~= 1 then bad[#bad + 1] = pins[i] end
    end
    safe_wait(ms)
    for i = 1, #pins do pin_set(pins[i], 0) end
    log.info("periph_rs485", "DE 自检回接收态", de_level_text(pins))
    return true, ms, pin_name_text(pins), pin_name_text(bad)
end

-- 关闭全部实例并清空注册表
function M.reset_all()
    for id, h in pairs(instances) do
        pcall(h.stop, h)
        instances[id] = nil
    end
    uart_users = {}
    power_ref = {}
    tx_busy = {}
    tx_sent = {}
    sent_off = {}
    uart_de_pins = {}
    return true
end

return M
