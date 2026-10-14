--[[
@module  dio
@summary 对外数字 IO（DI 中断输入 / DO 输出）—— Air8203 工业场景专属
@version 0.1（框架骨架）
@date    2026.09.28

=== 硬件事实（【官网-8203 产品页】对外接口说明，原文口径） ===
  · GPIO22M   中断输入，湿接点，高电平触发 GPIO22 中断
  · WAKEUP2M  中断输入，湿接点，高电平触发 WAKEUP2 中断
  · GPIO38M   输出；GPIO38 输出高时，GPIO38M 为低；GPIO38 输出低时，GPIO38M 为高
  · GPIO28M   输出；GPIO28 输出高时，GPIO28M 为低；GPIO28 输出低时，GPIO28M 为高
  · 补充说明：GPIO38 在低功耗模式下**无法保持高电平**，相应 GPIO38M 无法保持低电平
              GPIO28 为 AGPIO，低功耗模式下**可以保持**电平输出高或低

=== 由上述事实推出的 3 条设计约束 ===

  ① **DO 是反相的**（主控输出高 → 端子为低）
     → 业务层用"端子语义"编程时，必须取反。本模块统一在 wrap 层取反，
       对上层暴露 do_set(ch,端子电平)，避免反相逻辑散落到业务代码。

  ② **只有 GPIO28M 能在休眠下保持**（AGPIO）
     → 需要"掉电不丢状态"的 DO 通道必须分配在 28 上；
       GPIO38M 只适合"运行期有效、休眠即失效"的场景。
       本模块在 init() 里显式打印这一约束，避免用错通道。

  ③ **DI 是湿接点 + 高电平触发**
     → 外部提供 24V/湿接点信号，板载三极管隔离后进主控。
       因此主控侧看到的是**反相后的内部电平**，触发电平极性**【待核】**。

=== 与 8202G 的关系 ===
8202/8201 是消费类定位器，没有这套对外 IO；这是 8203 工业场景新增的能力。
因此在 8202G 项目里没有可复用的模块，属于**全新实现**。
唯一可复用的是 utils/tools.lua 里 LED 状态机的"手动覆盖优先级"写法思路。

=== 【待核】清单（P1） ===
  a) DI 中断的触发电平（gpio.RISING / FALLING / BOTH）与内部上拉
  b) WAKEUP2M 在 LuatOS 侧对应的语义常量名（gpio.USIM_DET 与 WAKEUP2 同名同脚）
     ⚠️ 注意：PIN79 既叫 USIM_DET 也叫 WAKEUP2，而 USIM_DET 已被 SIM 在位检测占用
        → **SIM 检测与 WAKEUP2M 中断输入可能抢同一个脚**，必须核对原理图确认
        （若确实复用，语义上二者本就是一回事：SIM 卡座与对外端子共用一路输入）
  c) DO 上电默认电平（避免上电瞬间对外部设备造成误动作）
  d) 对外端子的编号顺序（J100 10PIN / J101 5PIN 的排列，须与图纸/丝印对齐）
]]

local dio = {}

local config = require("config")
local CFG = config.DIO_CONFIG or {}

local state = {
    inited  = false,
    do_pins = {},   -- { [ch] = gpio号 }
    di_pins = {},   -- { [ch] = gpio号 }
}

-- 逻辑电平 → 端子电平（硬件反相）
local function to_terminal_level(logic_level)
    if CFG.DO_INVERT then
        return (logic_level == 1) and 0 or 1
    end
    return logic_level
end

--[[
初始化对外数字 IO。
]]
function dio.init()
    if state.inited then return true end
    if CFG.ENABLE == false then
        log.info("dio", "对外数字 IO 已禁用")
        return false
    end

    -- ===== DO 输出通道 =====
    local do_list = CFG.DO_PINS or {}
    for i, pin in ipairs(do_list) do
        if pin then
            state.do_pins[i] = pin
            local boot = (CFG.DO_BOOT_LEVEL and CFG.DO_BOOT_LEVEL[i]) or 0
            gpio.setup(pin, to_terminal_level(boot))
            if i == 1 then
                log.info("dio", string.format("DO%d = GPIO%d（AGPIO，休眠可保持）初始端子电平=%d",
                    i, pin, to_terminal_level(boot)))
            else
                log.info("dio", string.format("DO%d = GPIO%d（⚠️ 非 AGPIO，休眠下无法保持）初始端子电平=%d",
                    i, pin, to_terminal_level(boot)))
            end
        end
    end

    -- ===== DI 中断输入通道 =====
    -- ⚠️ 湿接点高电平触发，但经三极管隔离后的主控侧极性问题【待核】
    --    确认前不注册中断，只打印配置，避免误触发刷屏/误上报
    local di_list = CFG.DI_PINS or {}
    for i, pin in ipairs(di_list) do
        if pin then
            state.di_pins[i] = pin
            log.warn("dio", string.format(
                "DI%d = GPIO%d 已记录，但触发电平极性未确认 → 暂不注册中断（【待核】）", i, pin))
            -- 确认后启用：
            -- gpio.debounce(pin, CFG.DI_DEBOUNCE_MS or 50)
            -- gpio.setup(pin, function(level)
            --     sys.publish("DIO_DI", { ch = i, level = level })
            -- end, gpio.PULLUP, gpio.RISING)
        end
    end

    state.inited = true
    log.info("dio", "对外数字 IO 初始化完成（DO 反相=" .. tostring(CFG.DO_INVERT) .. "）")

    -- 业务侧可用事件：DIO_DI（DI 变化）/ 下行命令 set_do（见 remote.lua）
    return true
end

--[[
设置 DO 通道输出（按**端子语义**，内部自动处理硬件反相）。

@param number ch    通道号（1 起）
@param number level 端子电平：1=端子高 / 0=端子低
@return boolean
]]
function dio.do_set(ch, level)
    local pin = state.do_pins[ch]
    if not pin then return false, "无此通道: " .. tostring(ch) end
    gpio.set(pin, to_terminal_level(level))
    log.info("dio", string.format("DO%d(GPIO%d) → 端子电平 %d", ch, pin, level))
    return true
end

--[[
读取 DO 通道当前**端子电平**（把主控内部电平再反相回端子语义）。
]]
function dio.do_get(ch)
    local pin = state.do_pins[ch]
    if not pin then return nil end
    local internal = gpio.get(pin)
    return to_terminal_level(internal)   -- 反相是对合运算，再算一次即还原
end

--[[
读取 DI 通道当前电平（主控侧原始电平，非端子电平 —— 因隔离级反相极性待核）。
]]
function dio.di_get(ch)
    local pin = state.di_pins[ch]
    if not pin then return nil end
    return gpio.get(pin)
end

function dio.on_di(cb)
    sys.subscribe("DIO_DI", cb)
end

function dio.get_status()
    return {
        inited  = state.inited,
        do_pins = state.do_pins,
        di_pins = state.di_pins,
    }
end

return dio
