--[[
@module  video_source
@summary 点播视频源：把本地 H.264 裸流切成"访问单元"并按节拍推给平台
@version 1.0
@date    2026.10.15
@usage
780EHV 没有摄像头接口，本 demo 点播时推的是一个本地 H.264 annex-b 文件
(默认 /luadb/demo.h264)，循环推。

本模块对外三个接口：
  video_source.load(path)            —— 读文件并切成访问单元(AU)，返回源对象
  video_source.next_frame_policy(pushed) —— 推流节拍与"文件放完了怎么办"
  video_source.push_loop(sess, cli)  —— 一路会话的持续推流循环，会话结束才返回

为什么"切 AU"这件事要单独做：平台/媒体服务器按帧收流，一次 push_frame 应该是一张完整的图
(一个 VCL NAL 及其前面的 SPS/PPS/SEI)。整文件丢进去会被当成一张巨大的图，
平台侧表现为"有流无画"。切割点靠 annex-b 起始码找：
起始码有 3 字节(00 00 01)和 4 字节(00 00 00 01)两种，NAL 头字节永远紧跟 00 00 01 之后，
所以切片起点和头字节位置要分开记(4 字节码时二者差一个字节)。

本模块只在本 demo 内使用，由 gb28181_app.lua require。
]]

local M = {}

-- 单帧推送间隔(毫秒)。仅作为 next_frame_policy 的默认值，策略里可以不用它。
-- 自带 demo.h264 是 25fps，按 40ms 推：与源一致，也让视频/音频 PES 的比例
-- 和 PC 参考流一致（约 2 个音频 PES 对 1 帧视频）
M.FRAME_INTERVAL_MS = 40

--=============================================================================
-- 一、annex-b 切访问单元(纯字符串处理，不依赖硬件)
--=============================================================================

--[[
按"每个 VCL NAL 是一张图"把 annex-b 数据切成访问单元。

断图的判据只有一条：当前已经装了一个 VCL NAL，又遇到一个 VCL NAL。
所以 SPS/PPS/SEI 这类非 VCL 的 NAL 不会被当成新图的起点 —— 一张图 = 它前面的
参数集/SEI + 它的切片。

有一个不那么直观的后果：夹在两张图中间的 SEI，会被归到**前**一张图，
而不是它语义上"描述"的后一张。这与正式组件里的切法一致（已在真实平台联调验证）。
真要按 7.4.1.2.4 严格切，得解析切片的 first_mb_in_slice，代价大得多；
而且对播放没有影响：每个 AU 是按序写进 PS 帧的，媒体服务器重组出的字节流顺序不变。

@param  data string 整个文件的二进制内容
@return table  AU 数组，每个元素是一张图的完整字节(含起始码)
]]
local function split_aus(data)
    -- 第一遍：找出所有起始码的位置，以及紧随其后的 NAL 头字节位置
    local starts, hdrs = {}, {}
    local pos = 1
    while true do
        local s = string.find(data, "\0\0\1", pos, true)
        if not s then break end
        -- 4 字节起始码时，00 00 00 01，实际起点还要往前一个字节
        starts[#starts + 1] = (s > 1 and string.byte(data, s - 1) == 0) and (s - 1) or s
        hdrs[#hdrs + 1] = s + 3
        pos = s + 3
    end

    -- 第二遍：遇到"当前已有 VCL、又来了一个 VCL"就断一张图
    local aus, cur, has_vcl = {}, nil, false
    for i = 1, #starts do
        local stop = starts[i + 1] or (#data + 1)
        local nal_type = string.byte(data, hdrs[i]) % 32
        local is_vcl = (nal_type >= 1 and nal_type <= 5)
        if is_vcl and has_vcl then
            aus[#aus + 1] = cur
            cur, has_vcl = nil, false
        end
        cur = (cur or "") .. string.sub(data, starts[i], stop - 1)
        if is_vcl then has_vcl = true end
    end
    if cur then aus[#aus + 1] = cur end
    return aus
end

--=============================================================================
-- 二、装载视频源
--=============================================================================

--[[
读取 H.264 文件并切好访问单元。

@param  path string 文件路径(如 "/luadb/demo.h264")
@return table|nil, string|nil  src = {aus=, path=, count=}；失败时返回 nil, 原因
]]
function M.load(path)
    local data = io.readFile(path)
    if not data or #data == 0 then
        return nil, "读不到或空文件: " .. tostring(path)
    end
    local aus = split_aus(data)
    if #aus == 0 then
        return nil, "在文件里没找到 annex-b 起始码(确认是 H.264 裸流，不是 mp4/flv): " .. path
    end
    return {aus = aus, path = path, count = #aus}
end

--=============================================================================
-- 三、推流节拍策略
--=============================================================================

--[[
@api video_source.next_frame_policy(pushed)
@summary 决定"推下一帧之前等多久"，以及"文件放完了怎么办"
@param   pushed   number 本次会话已推的帧数(从 1 开始)
@return  delay_ms number 推下一帧前等多少毫秒
@return  action   string "next" 继续推下一帧
                          "restart" 回到文件开头重新推
                          "stop" 结束本次会话

契约(push_loop 已经替你保证的事)：
  · 会话一旦被平台 BYE 掉，push_loop 会在下一帧前就退出，不需要你判断
  · 你返回 "stop" 是"本端主动收尾"，平台那边会看到流停掉
  · 这里的入参只有帧数。要按时间/带宽/积压做决策，push_loop 里能拿到的只有
    mcu.ticks() 和 gb28181.stream_stats(sess.stream).queue，需要时可以在这里取用

当前是最小可用版本：固定节拍、放完从头再来。

可以替换的几种思路，各有代价：
  · 跟着文件本身的帧率走：从 AU 里的 SPS 解析帧率算出 delay。
    写死 100ms 在文件真是 25fps 时会推得太慢，平台侧看到的是"卡顿但不断"
  · 从头循环会让平台花屏到下一个 IDR(文件不是 IDR 开头时更明显)：
    记下最后一个 IDR 的位置，restart 时从那里开始，代价是丢了开头的非 IDR 帧
  · 积压(queued_bytes 一直涨)说明发不动了，此时拉长节拍比硬推更有用；
    但拉得太长媒体服务器会认为流停滞并主动注销 —— 实测那是比卡顿更糟的结果
  · 只想验证链路通不通：直接只推 IDR(nal_type == 5 的帧)，带宽立刻降一个量级
]]
function M.next_frame_policy(pushed)
    return M.FRAME_INTERVAL_MS, "next"
end

--=============================================================================
-- 四、一路会话的推流循环
--=============================================================================

--[[
把媒体流的状态拼成一行。"平台上没画面"时靠它定位卡在哪一段：

  链路=down / 背压(tx_again)持续涨 —— **媒体链没建起来**，包只入队不发。
      点播这条路的建链在 exgb28181client 的 media_open() 里；若那边被跳过
      或判活逻辑有误，现象就是这里的"积压"一直涨到 queue_full，
      而 SIP 侧一切正常。

  链路=up 但 错误(tx_errors)涨 —— 链建起来了，但底层发不出去（网卡/对端）。
  发出去的包数在涨、平台仍无画面 —— 问题不在本设备：要么平台侧没收，
      要么负载不对（看 ssrc / PS 头 / 时间戳）。
]]
local function stream_summary(sess)
    if not sess or not sess.stream or not gb28181 or not gb28181.stream_stats then
        return "流信息不可用"
    end
    local st = gb28181.stream_stats(sess.stream)
    if not st then return "流信息不可用" end
    local q = st.queue or {}
    return string.format("发=%d包/%d字节 背压=%d 错误=%d 半包=%d 积压=%d字节 链路=%s",
        st.tx_packets or 0, st.tx_bytes or 0, st.tx_again or 0,
        st.tx_errors or 0, st.tx_partial or 0, q.queued_bytes or 0,
        st.link_up and "up" or "down")
end

--[[
持续把视频源推给平台，直到这一路会话结束。

@param  sess table  会话表，来自 client.sessions()[call_id]
@param  cli  table  exgb28181client 模块
@return number 本次会话累计推出去的帧数

两个容易踩的坑：
  1) 必须**持续**推，不能推几秒就停。推几秒就停时媒体服务器会判定流停滞并主动注销，
     平台顺势内部清理而且**不给设备发 BYE** —— 设备侧会话从此泄漏，几路之后就永久回 486
  2) 会话可能在任意一帧之间被回收，回收后 sess.stream 会被置 nil，
     用它之前必须判空，否则脚本直接崩
]]
function M.push_loop(sess, cli)
    local src = M.src
    if not src then return 0 end

    local pushed, restarts = 0, 0
    local idx = 1
    local fail_streak = 0

    while cli.sessions()[sess.call_id] do
        local au = src.aus[idx]
        local delay_ms, action = M.next_frame_policy(pushed + 1)

        local ok, err = cli.push_frame(sess, au)
        if ok then
            pushed = pushed + 1
            fail_streak = 0
        elseif err ~= "waiting_idr" then
            -- "waiting_idr" 是正常的：还没等到 IDR，组件在等，不是错误
            -- 其它失败（主要是 queue_full）会**每帧都失败**，逐帧刷屏会把
            -- 有用的日志淹掉，所以只在开头和每 100 次报一次，并带上流的完整状态
            fail_streak = fail_streak + 1
            if fail_streak == 1 or fail_streak % 100 == 0 then
                log.warn("video_source", "推帧失败", idx, err, "连续", fail_streak, "次",
                         stream_summary(sess))
            end
        end

        if action == "stop" then
            log.info("video_source", "策略要求结束本次会话", "已推", pushed, "帧")
            break
        elseif action == "restart" then
            idx = 1
            restarts = restarts + 1
        else
            idx = idx + 1
            if idx > src.count then idx = 1 end   -- 到底了自然回卷
        end

        -- 每 50 帧（按默认 40ms 一帧约 2 秒）报一次账
        if pushed > 0 and pushed % 50 == 0 then
            log.info("video_source", "推流中", "累计", pushed, "帧", stream_summary(sess))
        end

        sys.wait(delay_ms)
    end

    return pushed
end

return M
