--[[
@module  pinyin
@summary 应用层拼音 → 中文词表（失物招领场景，不依赖固件 LUAT_USE_PINYIN 词库）
@version 1.0
@date    2026.10.30

=== 为什么需要它 ===
airui 的键盘虽然内置 LVGL 拼音 IME，但固件默认不编译 LVGL 自带词典
（luat_airui_conf.h: LV_IME_PINYIN_USE_DEFAULT_DICT 0），候选词可能为空。
这里用一张应用层词表兜底：键盘打字母 → 本模块前缀匹配 → 界面显示候选 → 点击上屏。

=== 词表范围 ===
只覆盖失物招领场景：物品名称、地点、招领/认领高频词。
新增词条只需往 ENTRIES 里加 {"拼音", "词"} 一行。
]]

local M = {}

-- {拼音, 中文}
local ENTRIES = {
    -- 物品名称
    { "shouji", "手机" }, { "qianbao", "钱包" }, { "yaoshi", "钥匙" },
    { "yaoshikou", "钥匙扣" }, { "shubao", "书包" }, { "beibao", "背包" },
    { "shoutibao", "手提包" }, { "shuibei", "水杯" }, { "baowenbei", "保温杯" },
    { "yusan", "雨伞" }, { "erji", "耳机" }, { "chongdianbao", "充电宝" },
    { "shujuxian", "数据线" }, { "shenfenzheng", "身份证" }, { "yinhangka", "银行卡" },
    { "gongjiaoka", "公交卡" }, { "xiaoyuanka", "校园卡" }, { "fanka", "饭卡" },
    { "yanjing", "眼镜" }, { "maozi", "帽子" }, { "weijin", "围巾" },
    { "shoutao", "手套" }, { "wanju", "玩具" }, { "diannao", "电脑" },
    { "bijiben", "笔记本" }, { "pingban", "平板" }, { "xiangji", "相机" },
    { "shoubiao", "手表" }, { "shouhuan", "手环" }, { "xinglixiang", "行李箱" },
    { "kuaidi", "快递" }, { "wenjian", "文件" }, { "wenjianjia", "文件夹" },
    { "gongpai", "工牌" }, { "menjinka", "门禁卡" }, { "shuji", "书籍" },
    { "wenju", "文具" }, { "yifu", "衣服" }, { "waitao", "外套" },
    { "zixingche", "自行车" }, { "diandongche", "电动车" }, { "chongdianqi", "充电器" },
    { "chongdianxian", "充电线" },

    -- 地点
    { "jiaoshi", "教室" }, { "tushuguan", "图书馆" }, { "shitang", "食堂" },
    { "caochang", "操场" }, { "xiaomenkou", "校门口" }, { "bangonglou", "办公楼" },
    { "shiyanshi", "实验室" }, { "tiyuguan", "体育馆" }, { "sushe", "宿舍" },
    { "dating", "大厅" }, { "qiantai", "前台" }, { "chaoshi", "超市" },
    { "chezhan", "车站" }, { "ditie", "地铁" }, { "gongjiao", "公交" },
    { "gongyuan", "公园" }, { "shangchang", "商场" }, { "tingchechang", "停车场" },
    { "huiyishi", "会议室" }, { "zoulang", "走廊" }, { "loutijian", "楼梯间" },
    { "weishengjian", "卫生间" }, { "kafeiting", "咖啡厅" }, { "canting", "餐厅" },
    { "menkou", "门口" },

    -- 招领 / 认领高频词
    { "yishi", "遗失" }, { "jiandao", "捡到" }, { "shide", "拾得" },
    { "lingqu", "领取" }, { "renling", "认领" }, { "lianxi", "联系" },
    { "fangshi", "方式" }, { "dianhua", "电话" }, { "qing", "请" },
    { "xiexie", "谢谢" }, { "shizhu", "失主" }, { "wuzhu", "物主" },
    { "haoxinren", "好心人" }, { "guihuan", "归还" }, { "ganxie", "感谢" },
    { "gonggao", "公告" }, { "gongshi", "公示" }, { "benren", "本人" },
    { "hedui", "核对" }, { "zhengming", "证明" }, { "chushi", "出示" },
    { "zhengjian", "证件" },

    -- 高频单字
    { "shou", "手" }, { "ji", "机" }, { "qian", "钱" }, { "bao", "包" },
    { "san", "伞" }, { "ka", "卡" }, { "biao", "表" }, { "shu", "书" },
    { "che", "车" }, { "men", "门" }, { "lou", "楼" }, { "ceng", "层" },
    { "hao", "号" }, { "shi", "室" }, { "guan", "馆" }, { "chang", "场" },
    { "yuan", "园" }, { "zhan", "站" }, { "jie", "街" }, { "lu", "路" },
    { "shi", "是" }, { "de", "的" }, { "wo", "我" }, { "ni", "你" },
    { "ta", "他" }, { "he", "和" }, { "zai", "在" }, { "you", "有" },
    { "yi", "一" }, { "ge", "个" }, { "er", "二" }, { "san", "三" },
}

-- 按首字母分桶，避免每次按键全表扫描（Air1603 主频不高，能省则省）
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
    -- 2) 前缀匹配
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
