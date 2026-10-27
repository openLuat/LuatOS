--[[
@module  ev_pinyin
@summary 应用层拼音 → 中文词表（不依赖固件 LUAT_USE_PINYIN 词库）
@version 1.0
@date    2026.10.23

=== 为什么需要它 ===
airui 的键盘虽然内置 LVGL 拼音 IME，但 components/airui/inc/luat_airui_conf.h 里
  #define LV_IME_PINYIN_USE_DEFAULT_DICT 0
也就是"不编译 LVGL 自带词典"，只靠固件宏 LUAT_USE_PINYIN 注入 luat_pinyin 词库。
固件没开这个宏时，IME 能创建、能敲字母，但候选词为空，等于打不出中文。

这里用一张应用层词表兜底：键盘打字母 → 本模块前缀匹配 → 界面显示候选 → 点击上屏。
真机固件若已开 LUAT_USE_PINYIN，本模块同样可用（字母照样进入输入框），互不冲突。

=== 词表范围 ===
只覆盖充电站播报场景（更好的是"小而准"）：状态、动作、礼貌用语、计量单位。
新增词条只需往 ENTRIES 里加 {"拼音", "词"} 一行。
]]
local M = {}

-- {拼音, 中文}
local ENTRIES = {
    -- 充电业务词
    { "chongdian", "充电" }, { "chongdianzhuang", "充电桩" }, { "chongman", "充满" },
    { "wancheng", "完成" }, { "yuchong", "预充" }, { "yongwan", "用完" },
    { "jine", "金额" }, { "feiyong", "费用" }, { "chaoshi", "超时" },
    { "chewei", "车位" }, { "cheliang", "车辆" }, { "shili", "驶离" },
    { "zhanyong", "占用" }, { "quyu", "区域" }, { "bizhan", "闭站" },
    { "nuoche", "挪车" }, { "fenzhong", "分钟" }, { "xiaoshi", "小时" },

    -- 提示 / 礼貌用语
    { "qingwu", "请勿" }, { "qing", "请" }, { "jiji", "即将" }, { "jinkuai", "尽快" },
    { "ganxie", "感谢" }, { "peihe", "配合" }, { "chuxing", "出行" }, { "yukuai", "愉快" },
    { "zhuyi", "注意" }, { "anquan", "安全" }, { "tishi", "提示" }, { "tixing", "提醒" },
    { "huanying", "欢迎" }, { "guanglin", "光临" }, { "fuwu", "服务" },
    { "ninhao", "您好" }, { "xiexie", "谢谢" }, { "zaijian", "再见" },

    -- 高频单字
    { "che", "车" }, { "wei", "位" }, { "dian", "电" }, { "chong", "充" },
    { "wan", "完" }, { "cheng", "成" }, { "shi", "时" }, { "shi", "事" },
    { "fei", "费" }, { "yong", "用" }, { "nin", "您" }, { "hao", "好" },
    { "hao", "号" }, { "xie", "谢" }, { "zhu", "祝" }, { "kuai", "快" },
    { "le", "乐" }, { "an", "安" }, { "quan", "全" }, { "yi", "已" },
    { "jiang", "将" }, { "chan", "产" }, { "sheng", "生" }, { "chao", "超" },
    { "li", "离" }, { "zhan", "占" }, { "zhan", "站" }, { "ben", "本" },
    { "qu", "区" }, { "yu", "域" }, { "yu", "预" }, { "yu", "愉" },
    { "ji", "即" }, { "bi", "闭" }, { "jin", "尽" }, { "nuo", "挪" },
    { "gan", "感" }, { "pei", "配" }, { "he", "合" }, { "chu", "出" },
    { "xing", "行" }, { "xing", "醒" }, { "zhu", "注" }, { "ti", "提" },
    { "ying", "迎" }, { "guang", "光" }, { "lin", "临" }, { "fu", "服" },
    { "wu", "务" }, { "wu", "勿" }, { "liang", "辆" }, { "tai", "台" },
    { "zhuang", "桩" }, { "man", "满" }, { "du", "度" }, { "fen", "分" },
    { "zhong", "钟" }, { "xiao", "小" }, { "miao", "秒" }, { "ci", "次" },
    { "hui", "会" }, { "jing", "经" }, { "guo", "过" }, { "da", "大" },
    { "zhong", "中" }, { "wen", "温" }, { "xin", "馨" },
}

-- 按首字母分桶，避免每次按键都全表扫描（Air1603 主频不高，能省则省）
local bucket = {}
local function build()
    for _, e in ipairs(ENTRIES) do
        local py, word = e[1], e[2]
        local k = py:sub(1, 1)
        local t = bucket[k]
        if not t then
            t = {}
            bucket[k] = t
        end
        t[#t + 1] = { py = py, word = word }
    end
end
build()

--[[按拼音前缀查候选词
@string py  已输入的小写字母串
@int limit  最多返回多少条（默认 6）
@return table 候选词数组（精确匹配在前，前缀匹配在后）
]]
function M.lookup(py, limit)
    limit = limit or 6
    local out = {}
    if type(py) ~= "string" or py == "" then return out end
    py = py:lower()
    local t = bucket[py:sub(1, 1)]
    if not t then return out end

    -- 1) 全拼精确匹配（同音多字会全部返回）
    for _, e in ipairs(t) do
        if e.py == py then
            out[#out + 1] = e.word
            if #out >= limit then return out end
        end
    end
    -- 2) 前缀匹配，短词优先，便于"边打边出"
    local n = #py
    for _, e in ipairs(t) do
        if #out >= limit then break end
        if e.py ~= py and #e.py > n and e.py:sub(1, n) == py then
            out[#out + 1] = e.word
        end
    end
    return out
end

return M
