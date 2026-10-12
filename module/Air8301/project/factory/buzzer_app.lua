--[[
@module  buzzer_app
@summary 蜂鸣器业务编排：按键音 / 测试提示音 / 曲目演奏（8301出厂固件）
@version 1.0
@date    2026.10.08
@author  江访
@usage
本模块只做业务编排，PWM 通道操作全部下沉到 buzzer_drv（PWM2/PIN98 唯一占用者），
曲谱数据与演奏节拍在 music 模块，本模块不直接调用 pwm 接口。

订阅的消息（3 个）：
1、BUZZER_BEEP_REQUEST  ：测试提示音，响 0.5 秒（沿用原接口，产测 BUZZER_TEST 语义不变）
2、KEY_BEEP_REQUEST     ：全局按键音，响 80 毫秒（由 key_beep 模块统一注入到全部按钮）
3、BUZZER_MUSIC_REQUEST ：立即演奏曲目（蜂鸣器测试页"播放歌曲"按钮）

开机静音（v2.1 变更）：
开机不再自动演奏曲目（上电突然发声体验不佳），只在应用内主动操作时才发声。
演奏入口统一为 BUZZER_MUSIC_REQUEST 消息（蜂鸣器测试页「播放歌曲」按钮发布），
本模块不再内置任何开机自动播放逻辑。

互斥策略：
按键音(80ms) < 测试提示音(0.5s) < 曲目(约18s) 共用同一扬声器，
由 buzzer_drv 统一维护占用标记：曲目播放期间的按键音直接丢弃，
按键音未结束时的曲目播放会短暂等待后开始。
]]

local buzzer_drv = require "buzzer_drv"
local music      = require "music"

-- ==================== 参数 ====================
local TEST_BEEP_MS        = 500    -- 测试提示音时长（沿用原 0.5 秒）
local TEST_BEEP_WAIT_MS   = 3000   -- 测试提示音等待扬声器空闲的时长
local KEY_BEEP_MS         = 80     -- 按键音时长（人机交互反馈音，干脆利落、连点不糊）
local KEY_BEEP_WAIT_MS    = 60     -- 按键音等待时长，超时即丢弃本次按键音

--[[
测试提示音协程：响 0.5 秒

@local
@function test_beep_task
]]
local function test_beep_task()
    buzzer_drv.beep(TEST_BEEP_MS, "test", TEST_BEEP_WAIT_MS)
end

--[[
按键音协程：响 80 毫秒（扬声器忙则丢弃，不排队、不打断）

@local
@function key_beep_task
]]
local function key_beep_task()
    buzzer_drv.beep(KEY_BEEP_MS, "key", KEY_BEEP_WAIT_MS)
end

--[[
曲目演奏协程

@local
@function music_task
]]
local function music_task()
    music.play()
end

--[[
BUZZER_BEEP_REQUEST 订阅回调：启动测试提示音协程

@local
@function on_beep_request
]]
local function on_beep_request()
    log.info("buzzer_app", "beep", TEST_BEEP_MS .. "ms")
    sys.taskInit(test_beep_task)
end

--[[
KEY_BEEP_REQUEST 订阅回调：启动按键音协程

@local
@function on_key_beep_request
]]
local function on_key_beep_request()
    -- 调试日志：确认按钮点击已触发按键音请求（验证完成后可删除本行）
    log.debug("buzzer_app", "key beep", KEY_BEEP_MS .. "ms")
    sys.taskInit(key_beep_task)
end

--[[
BUZZER_MUSIC_REQUEST 订阅回调：启动曲目演奏协程

@local
@function on_music_request
]]
local function on_music_request()
    log.info("buzzer_app", "music request")
    sys.taskInit(music_task)
end

sys.subscribe("BUZZER_BEEP_REQUEST", on_beep_request)
sys.subscribe("KEY_BEEP_REQUEST", on_key_beep_request)
sys.subscribe("BUZZER_MUSIC_REQUEST", on_music_request)

-- 开机静音：不再自动演奏曲目（v2.1 变更），曲目仅在应用内手动触发

log.info("buzzer_app", "init done")
