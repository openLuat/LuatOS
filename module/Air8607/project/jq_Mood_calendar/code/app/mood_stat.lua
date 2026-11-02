--[[
@module  mood_stat
@summary 心情统计与治愈系祝福语 / 安慰语生成
@author  蒋骞
@version 1.0
@date    2026.10.30

=== 心情指数怎么算 ===
指数 = 当月所有已记录日子的分数平均值，保留 1 位小数（1.0 ~ 5.0）。
没记录就不算 0 分，而是显示 "--"，避免「空白的一个月」被当成「很糟的一个月」。

=== 祝福语怎么选 ===
按指数分 5 段，每段准备了 4 句（每句拆成 3 个短行，方便固定宽度排版）。
同一段里用 os.time() 取模轮换，所以同一天多次点击会看到不同的句子，
但同一次报告内文字是稳定的（不会自己跳动）。

只用常用汉字和中文标点：
hzfont 字库里没有的符号（如中点「·」、emoji）会显示成空白，一律不用。
]]
local conf = require "conf"
local du = require "date_util"

local M = {}

local MOODS = conf.moods

-- 分数 -> 档位
local BY_SCORE = {}
for i = 1, #MOODS do
    BY_SCORE[MOODS[i].score] = MOODS[i]
end

--[[按分数取档位定义]]
function M.mood(score)
    return BY_SCORE[score]
end

-- ==================== 祝福语库 ====================
-- 每段按 min（指数下限）从高到低匹配，第一个满足 avg >= min 的生效。
local BLESS = {
    {
        min = 4.5,
        list = {
            { "这个月的你，", "像晒过太阳的被子，", "暖烘烘的。" },
            { "日子被你过成蜜桃味，", "甜得很安静。", "请继续喜欢生活。" },
            { "你的笑，", "这个月应该出现很多次，", "愿它一直都有理由。" },
            { "谢谢你这么用力地生活，", "也请继续，", "被生活温柔对待。" },
        },
    },
    {
        min = 4.0,
        list = {
            { "大部分日子都是晴天，", "偶尔飘过一朵云，", "也都是好的。" },
            { "稳稳的幸福最难得，", "这个月，", "你做到了。" },
            { "不急不忙地把日子过好，", "这本身，", "就很了不起。" },
            { "你已经很棒了，", "记得给自己，", "留一点偷懒的时间。" },
        },
    },
    {
        min = 3.2,
        list = {
            { "有晴天也有小雨，", "这才是完整的，", "一个月呀。" },
            { "不完美也没关系，", "你已经，", "很努力了。" },
            { "慢一点也可以，", "风景不会跑掉，", "它一直在等你。" },
            { "这个月辛苦啦，", "给自己泡一杯，", "热热的东西吧。" },
        },
    },
    {
        min = 2.5,
        list = {
            { "有点起伏的一个月，", "允许自己，", "偶尔情绪低落。" },
            { "累了就靠一靠，", "肩膀是用来歇的，", "不用扛下所有。" },
            { "你已经撑过了，", "很多不容易的日子，", "很了不起。" },
            { "不用急着好起来，", "慢慢来，", "我一直都在。" },
        },
    },
    {
        min = 0,
        list = {
            { "这个月很难，", "但你还在这里，", "这就已经很好了。" },
            { "难过的时候不用坚强，", "哭出来，", "也没关系。" },
            { "把心里的石头，", "先放下来一会儿吧，", "我陪着你。" },
            { "天黑得再久，", "也总会亮的，", "先好好睡一觉。" },
        },
    },
}

-- 本月一条记录都没有
local EMPTY = {
    { "这个月还很空，", "点一个日子，", "把心情放进来吧。" },
}

-- ==================== 统计 ====================
--[[统计某月数据
@param table data { [day] = score }
@return table {
    y, m, days,        -- 年月与本月天数
    n,                 -- 已记录天数
    avg,               -- 平均分（无记录时为 nil）
    cnt,               -- { [score] = 次数 }
    best, worst,       -- { day = , score = }，无记录时为 nil
    top,               -- 出现最多的分数（并列取高分）
}
]]
function M.summary(data, y, m)
    data = data or {}
    local days = du.days_in_month(y, m)
    local n, sum = 0, 0
    local cnt = {}
    local best, worst = nil, nil

    for d = 1, days do
        local s = data[d]
        if s then
            n = n + 1
            sum = sum + s
            cnt[s] = (cnt[s] or 0) + 1
            if not best or s > best.score then best = { day = d, score = s } end
            if not worst or s < worst.score then worst = { day = d, score = s } end
        end
    end

    -- 出现最多的档位（并列时取高分，让报告更偏正面）
    local top, top_cnt = nil, 0
    for i = 1, #MOODS do
        local sc = MOODS[i].score
        local c = cnt[sc] or 0
        if c > top_cnt then top, top_cnt = sc, c end
    end

    return {
        y = y, m = m, days = days,
        n = n,
        avg = (n > 0) and (sum / n) or nil,
        cnt = cnt,
        best = best,
        worst = worst,
        top = top,
    }
end

--[[指数对应的短评（右面板 / 报告里的一句话定性）]]
function M.word(avg)
    if not avg then return "还没开始记录" end
    if avg >= 4.5 then return "闪闪发光的一个月" end
    if avg >= 4.0 then return "挺好的，稳稳的" end
    if avg >= 3.2 then return "还不错，有晴有雨" end
    if avg >= 2.5 then return "有点起伏，辛苦啦" end
    return "辛苦了，先抱抱你"
end

--[[挑一句祝福语 / 安慰语
@return table 3 个短行组成的数组
]]
function M.compliment(sum)
    local n = sum and sum.n or 0
    if n == 0 then return EMPTY[1] end

    local avg = sum.avg or 3
    local picked = BLESS[#BLESS]
    for i = 1, #BLESS do
        if avg >= BLESS[i].min then
            picked = BLESS[i]
            break
        end
    end

    local list = picked.list
    local idx = (os.time() % #list) + 1
    return list[idx]
end

--[[把 3 行文字合成一个带换行的字符串（LVGL label 认 \n）]]
function M.join(lines)
    if not lines then return "" end
    return table.concat(lines, "\n")
end

--[[一行摘要，例如「已记录 18 天，本月 31 天」]]
function M.summary_line(sum)
    if not sum then return "" end
    if sum.n == 0 then
        return string.format("本月 %d 天，还没有记录", sum.days)
    end
    return string.format("已记录 %d 天，本月 %d 天", sum.n, sum.days)
end

return M
