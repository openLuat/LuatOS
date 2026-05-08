--[[
@module  idiom_solitaire_win
@summary 成语接龙游戏窗口模块
@version 1.0
@date    2026.04.22
@author  LuatOS
]]

--[[
模块说明：
本模块是成语接龙游戏的窗口模块，实现了以下功能：
1. 成语接龙游戏的核心逻辑
2. 三关递进式闯关模式
3. 正确答案检测和干扰词过滤
4. 游戏胜利界面和重玩功能
5. UI界面绘制和交互处理

游戏规则：
- 玩家需要选择以特定字开头的成语进行接龙
- 每关需要答对一定数量的成语才能晋级
- 三关全部通关后显示胜利界面
]]

-- exapp 沙箱里包装后的 exwin 在 _ENV 上；rawget(_G,"exwin") 易误用裸 exwin，退出后无法 exapp.close
local exwin = exwin
if not exwin then
    exwin = require "exwin"
end

-- 窗口ID，用于管理窗口的创建和销毁
local win_id = nil
-- 主游戏容器，包含整个游戏界面
local main_container
-- 胜利界面容器，用于显示通关画面
local victory_container

-- 前向声明（必须在使用前声明）
local resetGameToLevel

-- 成语库 (纯正成语)
-- 包含多个中文成语的成语库，每个成语都是四字成语
-- 用于游戏中的正确成语接龙
local REAL_IDIOM_SET = {
    "一马当先", "先发制人", "人山人海", "海阔天空", "空穴来风", "风花雪月", "月明星稀", "稀奇古怪",
    "怪力乱神", "神采飞扬", "扬眉吐气", "气宇轩昂", "昂首阔步", "步步高升", "升堂入室", "室迩人远",
    "远走高飞", "飞黄腾达", "达官贵人", "人杰地灵", "灵机一动", "动人心弦", "弦外之音", "音信全无",
    "无中生有", "有目共睹", "睹物思人", "人定胜天", "天马行空", "空口无凭", "凭栏远眺", "眺望未来",
    "来日方长", "长命百岁", "岁月如梭", "梭天摸地", "地久天长", "长治久安", "安步当车", "车水马龙",
    "龙飞凤舞", "舞文弄墨", "墨守成规", "规行矩步", "步履维艰", "艰苦卓绝", "绝处逢生", "生龙活虎",
    "虎视眈眈", "眈眈逐逐", "逐鹿中原", "原封不动", "动辄得咎", "咎由自取", "取长补短", "短兵相接",
    "接二连三", "三心二意", "意气风发", "发人深省", "省吃俭用", "用兵如神", "神机妙算", "算无遗策",
    "策马扬鞭", "鞭长莫及", "及锋而试", "试才录用", "用武之地", "地大物博", "博古通今", "今非昔比",
    "比比皆是", "是非分明", "明察秋毫", "毫不介意", "意味深长", "长驱直入", "入木三分", "分秒必争",
    "争先恐后", "后来居上", "上善若水", "水到渠成", "成竹在胸", "胸有成竹", "竹报平安", "安之若素",
    "素不相识", "识途老马", "马到成功", "功高盖主", "主次不分", "分道扬镳", "镳旗飞扬", "扬长而去",
    "去伪存真", "真知灼见", "见仁见智", "智勇双全", "全力以赴", "赴汤蹈火", "火上浇油", "油然而生"
}

-- 干扰词库 (四字词语，非成语，按首字分组)
-- 包含一些四字词语和非成语表达，用于作为干扰选项
-- 这些词语看起来像成语但实际上不是成语
local FAKE_PHRASES = {
    -- 先字开头
    "先入为主", "先天不足", "先天优势", "先见之明", "先来后到", "先礼后兵", "先发制人", "先声夺人",
    "先公后私", "先斩后奏", "先贤列表", "先进事迹", "先进个人", "先锋模范", "先期准备", "先期投入",
    -- 天字开头
    "天方夜谭", "天高云淡", "天寒地冻", "天昏地暗", "天南地北", "天罗地网", "天诛地灭", "天造地设",
    "天长日久", "天差地远", "天愁地惨", "天从人愿", "天大地大", "天低吴楚", "天各一方",
    "天公地道", "天冠地屦", "天荒地老", "天华乱坠", "天潢贵胄", "天荒地老",
    -- 地字开头
    "地大物博", "地利人和", "地广人稀", "地灵人杰", "地上地下", "地下茎基", "地动山摇", "地覆天翻",
    "地广民稀", "地久天长", "地老天荒", "地平天成", "地气上腾", "地质勘探",
    "地尽其利", "地利优势", "地面部队", "地面覆盖", "地方法院", "地方政府", "地方志书",
    -- 人字开头
    "人山人海", "人云亦云", "人杰地灵", "人才济济", "人多势众", "人心所向", "人心惶惶", "人言可畏",
    "人声鼎沸", "人来人往", "人情世故", "人情冷暖", "人迹罕至", "人财两旺", "人定胜天", "人各有志",
    -- 心字开头
    "心想事成", "心旷神怡", "心满意足", "心花怒放", "心平气和", "心有灵犀", "心不在焉", "心猿意马",
    "心神不宁", "心慌意乱", "心灰意冷", "心直口快", "心胸开阔", "心胸狭隘", "心血来潮", "心领神会",
    "心慈面软", "心荡神驰", "心恶搪突", "心烦技痒",
    -- 意字开头
    "意气风发", "意气相投", "意味深长", "意气用事", "意气扬扬", "意料之中", "意想不到", "意料之外",
    "意境高远", "意念集中", "意识清醒", "意识形态", "意志坚定", "意见分歧", "意见一致", "意气轩昂",
    "意气激昂", "意气凌云", "意气自若", "意气自得", "意领神会", "意满志得",
    -- 发字开头
    "发愤图强", "发号施令", "发人深省", "发家致富", "发财致富", "发迹变泰", "发展迅速", "发展缓慢",
    "发挥作用", "发挥特长", "发挥优势", "发挥余热", "发奋图强", "发奋学习", "发奋工作", "发明创造",
    "发威震主", "发政施仁", "发奸摘覆", "发奸擿伏", "发蒙振落",
    -- 强字开头
    "强强联合", "强本节用", "强词夺理", "强人所难", "强弩之末", "强颜欢笑", "强取豪夺", "强死赖活",
    "强兵富国", "强不凌弱", "强敌环视", "强国度用", "强干弱枝", "强弓劲弩", "强记博闻", "强将手下",
    -- 难字开头
    "难能可贵", "难以置信", "难解难分", "难言之隐", "难兄难弟", "难乎其难", "难进易退", "难上加难",
    "难得糊涂", "难关突破", "难关重重", "难免出错", "难免失误", "难免发生", "难免遇到",
    -- 其字开头
    "其乐融融", "其貌不扬", "其事体大", "其势汹汹", "其味无穷", "其应若响",
    -- 之字开头
    "之乎者也", "之死不渝", "之死靡它",
    -- 不字开头
    "不卑不亢", "不茶不饭", "不瞅不睬", "不动声色", "不分彼此", "不丰不杀", "不费吹灰",
    "不服不忿", "不当不正", "不得不尔",
    -- 有字开头
    "有板有眼", "有本有原", "有棱有角", "有滋有味", "有色眼镜", "有气无力",
    "有钱有势", "有头有脸", "有头有尾", "有始有终", "有恃无恐", "有所作为", "有眼无珠", "有勇无谋",
    -- 无字开头
    "无独有偶", "无冬无夏", "无法无天", "无根无蒂", "无毁无誉", "无尽无休", "无偏无倚", "无奇不有",
    "无穷无尽", "无拳无勇", "无时无刻", "无事无登", "无思无虑",
    -- 来字开头
    "来日方长", "来者可追", "来去分明", "来去无踪", "来情去意", "来势汹汹", "来回来去", "来而不往",
    "来者不善", "来历不明", "来路不明",
    -- 去字开头
    "去伪存真", "去其糟粕", "去粗取精", "去邪归正", "去暗投明", "去恶务尽", "去邪务去", "去就之分",
    "去末归本", "去如黄鹤", "去逆效顺",
    -- 为字开头
    "为非作歹", "为富不仁", "为官从政", "为好成歉", "为鬼为蜮", "为国为民", "为期不远", "为人师表",
    "为仁不富", "为山九仞", "为时不晚", "为首是从", "为所欲为", "为裘为箕",
    -- 成字开头
    "成竹在胸", "成败利钝", "成败论人", "成家立业", "成己成物", "成精作怪", "成人之美", "成仁取义",
    "成日成夜", "成双成对", "成算在心", "成人之美",
    -- 功字开头
    "功成名遂", "功成不居", "功成名就", "功成身退", "功成业就", "功到自然", "功德兼隆", "功德无量",
    "功高盖世", "功高望重", "功亏一篑", "功名富贵", "功名利禄",
    -- 见字开头
    "见义勇为", "见微知著", "见多识广", "见怪不怪", "见机行事", "见景生情", "见利忘义", "见仁见智",
    "见色忘义", "见所未见", "见缝插针", "见好就收", "见财忘义",
    -- 智字开头
    "智勇双全", "智圆行方", "智勇兼备", "智穷才竭", "智昏菽麦", "智珠在握",
    -- 全字开头
    "全力以赴", "全知全能", "全受全归", "全功尽弃", "全盘托出", "全神贯注", "全始全终", "全寿富贵",
    "全心全意", "全知全晓",
    -- 力字开头
    "力所能及", "力不从心", "力不能支", "力不胜任", "力挽狂澜", "力竭声嘶", "力敌万夫",
    "力孤势寡", "力均智敌", "力屈道穷", "力排众议",
    -- 赴字开头
    "赴汤蹈火", "赴险如夷", "赴死如归", "赴炎趋势", "赴火蹈刃",
    -- 火字开头
    "火上浇油", "火上弄冰", "火尽薪传", "火灭烟消", "火眼金睛", "火然泉达", "火热水深",
    "火耕流种", "火耨刀耕", "火冒三丈", "火树银花",
    -- 油字开头
    "油然而生", "油嘴油舌", "油腔滑调", "油头滑脑", "油头粉面", "油光水滑",
    "油尽灯枯", "油浇火燎", "油煎火燎",
    -- 水字开头
    "水到渠成", "水涨船高", "水落石出", "水泄不通", "水乳交融", "水深火热", "水月观音", "水木清华",
    "水光山色", "水光潋滟", "水净鹅飞", "水可载舟", "水枯石烂", "水阔山高",
    -- 安字开头
    "安之若素", "安土重迁", "安然无恙", "安枕而卧", "安于现状", "安坐待毙", "安时处顺", "安常履险",
    "安常习故", "安车蒲轮", "安老怀少", "安良除暴", "安眉带眼", "安内攘外", "安贫乐道",
    -- 素字开头
    "素不相识", "素昧平生", "素车白马", "素丝良马", "素未谋面", "素隐行怪", "素有往来",
    "素不相能", "素餐尸禄", "素发垂领",
    -- 识字开头
    "识途老马", "识文断字", "识文谈字", "识微见远", "识才尊贤", "识多才广", "识礼习文",
    "识破机关", "识时务者", "识微知几", "识微见著", "识心见性",
    -- 马字开头
    "马到成功", "马首是瞻", "马不停蹄", "马齿徒增", "马到功成", "马翻人仰", "马放南山",
    "马工枚速", "马后课前", "马迹蛛丝", "马龙车水", "马马虎虎", "马面牛头", "马如游龙",
    -- 旗字开头
    "旗开得胜", "旗鼓相当", "旗帜鲜明", "旗鼓重开", "旗开取胜", "旗开德化",
    "旗靡辙乱", "旗牌官用", "旗抢如云"
}

-- 关卡配置
-- 定义游戏的三关配置，包括关卡名称、答对题数和难度标签
local LEVELS = {
    { id = 1, name = "第1关", needCorrect = 3, difficulty = "初出茅庐", difficulty_level = 1 },
    { id = 2, name = "第2关", needCorrect = 4, difficulty = "渐入佳境", difficulty_level = 3 },
    { id = 3, name = "第3关", needCorrect = 5, difficulty = "炉火纯青", difficulty_level = 5 }
}

-- 游戏状态
-- currentLevel: 当前关卡索引（0-based）
-- currentChain: 当前接龙成语链，包含已选择的成语
-- usedSet: 已使用成语集合，用于防止重复选择
-- currentCorrectInLevel: 当前关卡已答对数量
-- isWaiting: 是否正在等待用户操作（防止连续点击）
-- gameCompleted: 游戏是否已通关
local currentLevel = 0
local currentChain = {}
local usedSet = {}
local currentCorrectInLevel = 0
local isWaiting = false
local gameCompleted = false

-- UI元素集合，保存所有需要频繁访问的UI组件引用
-- 用于在各种函数中快速访问UI元素
local currentOptions = {}
local correctAnswer = nil

local ui_elements = {}

--[[
获取字符串的第一个汉字字符
@param str string 输入字符串
@return string 第一个汉字字符（UTF-8编码的三个字节）
]]
local function getFirstChar(str)
    local firstByte = string.byte(str, 1)
    if firstByte >= 0xE4 and firstByte <= 0xEB then
        return string.sub(str, 1, 3)
    else
        return string.sub(str, 1, 1)
    end
end

--[[
获取字符串的最后一个汉字字符
@param str string 输入字符串
@return string 最后一个汉字字符（UTF-8编码的三个字节）
]]
local function getLastChar(str)
    local len = string.len(str)
    local i = len
    while i > 0 do
        local byte = string.byte(str, i)
        if byte >= 0xE4 and byte <= 0xEB then
            return string.sub(str, i, i+2)
        end
        i = i - 1
    end
    return string.sub(str, -1)
end

--[[
检查词语是否为真正的成语
@param word string 要检查的词语
@return boolean true表示是成语，false表示不是
]]
local function isValidIdiom(word)
    for _, idiom in ipairs(REAL_IDIOM_SET) do
        if idiom == word then return true end
    end
    return false
end

--[[
检查两个成语是否可以接龙（前一个成语的尾字等于后一个成语的首字）
@param prev string 前一个成语
@param next string 后一个成语
@return boolean true表示可以接龙，false表示不能
]]
local function canChain(prev, next) return getLastChar(prev) == getFirstChar(next) end

--[[
显示消息提示
@param msg string 要显示的消息内容
@param isError boolean 是否为错误消息（true显示红色，false显示正常颜色）
]]
local function showMessage(msg, isError)
    log.info("idiom_solitaire", "showMessage:", msg, "message_text:", ui_elements.message_text)
    if not ui_elements.message_text then
        return
    end
    local text_label = ui_elements.message_text
    pcall(function()
        if text_label.set_text then
            text_label:set_text(msg)
        end
        if isError then
            if text_label.set_color then
                text_label:set_color(0xFF0000)
            end
        else
            if text_label.set_color then
                text_label:set_color(0xf7e6c4)
            end
        end
    end)
end

--[[
渲染接龙历史记录
在历史区域显示所有已接龙的成语，形成接龙链条展示效果
采用网格布局，每行显示4个成语
]]
local function renderHistory()
    if not ui_elements.history_list then return end

    for _, item in ipairs(ui_elements.history_items or {}) do
        item:destroy()
    end
    ui_elements.history_items = {}

    local x = 10
    local y = 10
    local gap = 6
    local item_width = 100
    local item_height = 30
    local row_max = 4

    for i, idiom in ipairs(currentChain) do
        local row = math.floor((i - 1) / row_max)
        local col = (i - 1) % row_max
        local pos_x = x + col * (item_width + gap)
        local pos_y = y + row * (item_height + gap)

        local badge = airui.container({
            parent = ui_elements.history_list,
            x = pos_x, y = pos_y,
            w = item_width, h = item_height,
            color = 0xfdf3e2,
            radius = 15
        })

        airui.label({
            parent = badge,
            x = 5, y = 5,
            w = item_width - 10, h = item_height - 10,
            text = idiom,
            align = airui.TEXT_ALIGN_CENTER,
            font_size = 13,
            color = 0x644829
        })

        table.insert(ui_elements.history_items, badge)
    end
end

--[[
刷新游戏主界面显示
更新当前成语、提示信息、历史记录和进度显示
在每次用户选择后调用以反映最新游戏状态
]]
local function refreshUI()
    if #currentChain == 0 then return end
    local cur = currentChain[#currentChain]

    if ui_elements.current_idiom and ui_elements.current_idiom.set_text then
        ui_elements.current_idiom:set_text(cur)
    end

    if ui_elements.last_char_hint and ui_elements.last_char_hint.set_text then
        ui_elements.last_char_hint:set_text("下一成语需以「" .. getLastChar(cur) .. "」开头")
    end

    renderHistory()

    if ui_elements.correct_count and ui_elements.correct_count.set_text then
        ui_elements.correct_count:set_text(tostring(currentCorrectInLevel))
    end

    local levelData = LEVELS[currentLevel + 1]
    if ui_elements.need_count and ui_elements.need_count.set_text and levelData then
        ui_elements.need_count:set_text(tostring(levelData.needCorrect))
    end
    if ui_elements.progress_text and ui_elements.progress_text.set_text and levelData then
        ui_elements.progress_text:set_text("进度 " .. currentCorrectInLevel .. " / " .. levelData.needCorrect)
    end
end

--[[
为当前关卡生成选项
根据当前成语的尾字生成3个选项：1个正确成语和2个干扰词
@return table|nil 返回包含options和correct字段的表，或nil（如果无法生成）
]]
local function generateOptionsForLevel()
    if #currentChain == 0 then
        log.info("idiom_solitaire", "generateOptionsForLevel: currentChain is empty")
        return nil
    end
    local lastIdiom = currentChain[#currentChain]
    local requiredFirst = getLastChar(lastIdiom)
    log.info("idiom_solitaire", "generateOptionsForLevel: lastIdiom=", lastIdiom, "requiredFirst=", requiredFirst)

    local correctCandidates = {}
    for _, idiom in ipairs(REAL_IDIOM_SET) do
        if not usedSet[idiom] and getFirstChar(idiom) == requiredFirst and isValidIdiom(idiom) then
            table.insert(correctCandidates, idiom)
        end
    end
    log.info("idiom_solitaire", "generateOptionsForLevel: found", #correctCandidates, "candidates")

    if #correctCandidates == 0 then return nil end
    local correct = correctCandidates[math.random(#correctCandidates)]
    log.info("idiom_solitaire", "generateOptionsForLevel: correct=", correct)

    local fakePool = {}
    for _, phrase in ipairs(FAKE_PHRASES) do
        if phrase ~= correct and getFirstChar(phrase) == requiredFirst then
            table.insert(fakePool, phrase)
        end
    end

    if #fakePool < 2 then
        local defaultFakes = {
            "先行一步", "先天优势", "先期准备", "先期投入", "先进集体", "先进工作", "先进个人", "先进技术",
            "先天不足", "先天缺陷", "先天性病", "先兆症状", "先锋模范", "先锋作用", "先锋队员", "先锋企业",
            "天气预报", "天空晴朗", "天空湛蓝", "天空明亮", "天蓝水清", "天马行空", "天方夜谭", "天寒地冻",
            "天高云淡", "天昏地暗", "天罗地网", "天南地北", "天涯海角", "天作之合", "天造地设", "天长日久",
            "地大物博", "地利人和", "地广人稀", "地灵人杰", "地面部队", "地质构造", "地质灾害", "地方法规",
            "地方特色", "地方政府", "地方保护", "地方经济", "地标建筑", "地地道道", "地动山摇", "地肥水美",
            "人才济济", "人多势众", "人心所向", "人心惶惶", "人言可畏", "人声嘈杂", "人山人海", "人来人往",
            "人情世故", "人情冷暖", "人迹罕至", "人财两空", "人神共愤", "人定胜天", "人中之龙", "人各有志",
            "心想事成", "心旷神怡", "心满意足", "心花怒放", "心平气和", "心有灵犀", "心不在焉", "心猿意马",
            "心神不宁", "心慌意乱", "心灰意冷", "心直口快", "心胸开阔", "心胸狭隘", "心血来潮", "心领神会",
            "意气风发", "意气相投", "意味深长", "意气用事", "意气扬扬", "意料之中", "意想不到", "意料之外",
            "意境深远", "意念集中", "意识清醒", "意识形态", "意志坚定", "意见分歧", "意见一致", "意气高昂",
            "发愤图强", "发号施令", "发人深省", "发家致富", "发财致富", "发迹变泰", "发展迅速", "发展缓慢",
            "发挥作用", "发挥特长", "发挥优势", "发挥余热", "发奋学习", "发奋工作", "发愤图强", "发愤忘食",
            "强强联合", "强势出击", "强力推进", "强化管理", "强化服务", "强化监督", "强基固本", "强筋健骨",
            "强身健体", "强项突出", "强力支持", "强力保障", "强力推进", "强力攻坚", "强力突破", "强力反弹",
            "难得糊涂", "难能可贵", "难以置信", "难解难分", "难言之隐", "难度很大", "难度不小", "难度适中",
            "难题破解", "难题攻克", "难关突破", "难关重重", "难免出错", "难免失误", "难免发生", "难免遇到"
        }
        for _, phrase in ipairs(defaultFakes) do
            if phrase ~= correct and getFirstChar(phrase) == requiredFirst then
                table.insert(fakePool, phrase)
            end
        end
    end

    if #fakePool < 2 then
        fakePool = {"" .. requiredFirst .. "声夺人", "" .. requiredFirst .. "入为主", "" .. requiredFirst .. "见之明"}
    end

    local filteredFakes = {}
    for _, phrase in ipairs(fakePool) do
        if not isValidIdiom(phrase) then
            table.insert(filteredFakes, phrase)
        end
    end
    if #filteredFakes > 0 then
        fakePool = filteredFakes
    end

    for i = #fakePool, 2, -1 do
        local j = math.random(i)
        fakePool[i], fakePool[j] = fakePool[j], fakePool[i]
    end

    local distractor1 = fakePool[1] or ("" .. requiredFirst .. "声夺人")
    local distractor2 = fakePool[2] or ("" .. requiredFirst .. "入为主")

    if distractor1 == correct then distractor1 = ("" .. requiredFirst .. "见之明") end
    if distractor2 == correct then distractor2 = ("" .. requiredFirst .. "发制人") end

    local options = {correct, distractor1, distractor2}
    for i = #options, 2, -1 do
        local j = math.random(i)
        options[i], options[j] = options[j], options[i]
    end

    return { options = options, correct = correct }
end

--[[
刷新选项按钮的显示
将生成的选项显示在按钮上，并重置按钮样式
@return boolean 生成选项是否成功
]]
local function refreshOptionsUI()
    local generated = generateOptionsForLevel()
    log.info("idiom_solitaire", "refreshOptionsUI: generated=", generated)
    if not generated then
        showMessage("本关无可接龙成语，请重置闯关", true)
        for i, btn_data in ipairs(ui_elements.option_buttons or {}) do
            if btn_data and btn_data.label and btn_data.label.set_text then
                btn_data.label:set_text("无可用")
            end
        end
        currentOptions = {}
        correctAnswer = nil
        return false
    end

    currentOptions = generated.options
    correctAnswer = generated.correct
    log.info("idiom_solitaire", "refreshOptionsUI: currentOptions=", #currentOptions, "correctAnswer=", correctAnswer)

    for i, btn_data in ipairs(ui_elements.option_buttons or {}) do
        if btn_data and btn_data.label and btn_data.label.set_text then
            btn_data.label:set_text(currentOptions[i])
        end
    end

    return true
end

--[[
设置容器的显示或隐藏状态
@param container userdata 要操作的容器对象
@param visible boolean true显示，false隐藏
]]
local function set_container_visible(container, visible)
    if container then
        if visible then
            container:open()
        else
            container:hide()
        end
    end
end

--[[
创建胜利界面
显示通关成功界面，包含统计信息和两个按钮：
1. "再玩一次"按钮 - 重置游戏从第1关重新开始
2. "退出游戏"按钮 - 关闭窗口返回应用商店
]]
local function createVictoryScreen()
    log.error("idiom_solitaire", "=== createVictoryScreen 函数开始执行 ===")
    
    -- 如果胜利界面容器不存在，创建它
    if not victory_container then
        victory_container = airui.container({
            parent = main_container,
            x = 0, y = 0,
            w = 480, h = 800,
            color = 0xf5e7d3,
            z_index = 100
        })
    end
    
    -- 确保胜利界面容器是打开状态
    victory_container:open()
    
    -- 如果内部容器不存在，创建它并包含所有元素（包括按钮）
    if not ui_elements.victory_inner then
        local victory_inner = airui.container({
            parent = victory_container,
            x = 40, y = 200,
            w = 400, h = 400,
            color = 0xfffaf0,
            radius = 30,
            border_color = 0xffe066,
            border_width = 3
        })
        ui_elements.victory_inner = victory_inner
        
        -- 添加奖杯图标（左）
        if airui.image then
            airui.image({
                parent = victory_inner,
                x = 30, y = 25,
                w = 32, h = 32,
                scale_mode = "fit",
                src = "/luadb/jb.png"
            })
        end
        
        -- 创建通关成功标签
        airui.label({
            parent = victory_inner,
            x = 58, y = 30,
            w = 280, h = 40,
            align = airui.TEXT_ALIGN_CENTER,
            text = "恭喜通关！",
            font_size = 28,
            font_weight = "bold",
            color = 0xd4a017
        })
        
        -- 添加奖杯图标（右）
        if airui.image then
            airui.image({
                parent = victory_inner,
                x = 332, y = 25,
                w = 32, h = 32,
                scale_mode = "fit",
                src = "/luadb/jb.png"
            })
        end
        
        -- 创建统计标签
        ui_elements.victory_stats = airui.label({
            parent = victory_inner,
            x = 50, y = 90,
            w = 300, h = 80,
            align = airui.TEXT_ALIGN_CENTER,
            text = "总接龙成语数: 0 个\n文曲星下凡！",
            font_size = 18,
            color = 0x5a2e18
        })
    end
    
    -- 每次显示胜利界面时都重新创建按钮（确保回调正确绑定）
    local victory_inner = ui_elements.victory_inner
    if victory_inner then
        -- 创建再玩一次按钮（内联重置逻辑避免前向引用问题）
        local retry_btn = airui.button({
            parent = victory_inner,
            x = 50, y = 200,
            w = 300, h = 50,
            text = "再玩一次",
            font_size = 18,
            text_color = 0x3d2b18,
            bg_color = 0xe9cf9b,
            radius = 25,
            on_click = function()
                log.info("idiom_solitaire", "=== 再玩一次按钮被点击 ===")
                -- 内联实现重置到第1关
                gameCompleted = false
                if victory_container then 
                    victory_container:hide() 
                end
                if ui_elements and ui_elements.game_main then
                    ui_elements.game_main:open()
                end
                -- 重置游戏状态
                currentLevel = 0
                currentChain = {}
                usedSet = {}
                currentCorrectInLevel = 0
                local startMap = {"一马当先", "人山人海", "龙飞凤舞"}
                local start = startMap[1] or "一马当先"
                table.insert(currentChain, start)
                usedSet[start] = true
                local lvl = LEVELS[1]
                if ui_elements.level_label and ui_elements.level_label.set_text then
                    ui_elements.level_label:set_text(lvl.name)
                end
                if ui_elements.difficulty_tag and ui_elements.difficulty_tag.set_text then
                    ui_elements.difficulty_tag:set_text("第" .. lvl.id .. "关")
                end
                if ui_elements.need_count and ui_elements.need_count.set_text then
                    ui_elements.need_count:set_text(tostring(lvl.needCorrect))
                end
                refreshUI()
                refreshOptionsUI()
            end
        })
        -- 额外调用 set_on_click 确保回调正确绑定
        if retry_btn and retry_btn.set_on_click then
            retry_btn:set_on_click(function()
                log.info("idiom_solitaire", "=== 再玩一次按钮被点击 (set_on_click) ===")
                -- 内联实现重置到第1关
                gameCompleted = false
                if victory_container then 
                    victory_container:hide() 
                end
                if ui_elements and ui_elements.game_main then
                    ui_elements.game_main:open()
                end
                -- 重置游戏状态
                currentLevel = 0
                currentChain = {}
                usedSet = {}
                currentCorrectInLevel = 0
                local startMap = {"一马当先", "人山人海", "龙飞凤舞"}
                local start = startMap[1] or "一马当先"
                table.insert(currentChain, start)
                usedSet[start] = true
                local lvl = LEVELS[1]
                if ui_elements.level_label and ui_elements.level_label.set_text then
                    ui_elements.level_label:set_text(lvl.name)
                end
                if ui_elements.difficulty_tag and ui_elements.difficulty_tag.set_text then
                    ui_elements.difficulty_tag:set_text("第" .. lvl.id .. "关")
                end
                if ui_elements.need_count and ui_elements.need_count.set_text then
                    ui_elements.need_count:set_text(tostring(lvl.needCorrect))
                end
                refreshUI()
                refreshOptionsUI()
            end)
        end
        
        -- 创建退出游戏按钮
        local exit_btn = airui.button({
            parent = victory_inner,
            x = 50, y = 280,
            w = 300, h = 50,
            text = "退出游戏",
            font_size = 18,
            text_color = 0x3d2b18,
            bg_color = 0xe9cf9b,
            radius = 25,
            on_click = function()
                log.info("idiom_solitaire", "=== 退出游戏按钮被点击 ===")
                if exwin and exwin.close and win_id then
                    exwin.close(win_id)
                end
            end
        })
        -- 额外调用 set_on_click 确保回调正确绑定
        if exit_btn and exit_btn.set_on_click then
            exit_btn:set_on_click(function()
                log.info("idiom_solitaire", "=== 退出游戏按钮被点击 (set_on_click) ===")
                if exwin and exwin.close and win_id then
                    exwin.close(win_id)
                end
            end)
        end
    end
end

--[[
显示胜利界面
在游戏通关后调用，显示胜利容器并隐藏游戏主界面
同时更新统计数据
]]
local function showVictoryScreen()
    log.error("idiom_solitaire", "!!! CRITICAL: showVictoryScreen called !!!")
    gameCompleted = true
    local totalIdioms = #currentChain
    log.error("idiom_solitaire", "!!! CRITICAL: totalIdioms=", totalIdioms, " !!!")
    
    createVictoryScreen()
    log.error("idiom_solitaire", "!!! CRITICAL: createVictoryScreen done, victory_container=", victory_container)
    
    if ui_elements and ui_elements.victory_stats and ui_elements.victory_stats.set_text then
        ui_elements.victory_stats:set_text("总接龙成语数: " .. totalIdioms .. " 个\n文曲星下凡！")
        log.error("idiom_solitaire", "!!! CRITICAL: victory_stats text set !!!")
    end
    
    log.error("idiom_solitaire", "!!! CRITICAL: hiding game_main, game_main=", ui_elements and ui_elements.game_main)
    if ui_elements and ui_elements.game_main then
        ui_elements.game_main:hide()
        log.error("idiom_solitaire", "!!! CRITICAL: game_main hidden successfully !!!")
    end
    
    log.error("idiom_solitaire", "!!! CRITICAL: showing victory_container, victory_container=", victory_container)
    if victory_container then
        victory_container:open()
        log.error("idiom_solitaire", "!!! CRITICAL: victory_container opened successfully !!!")
    end
    
    log.error("idiom_solitaire", "!!! CRITICAL: showVictoryScreen END !!!")
end

--[[
进入下一关
当当前关卡答对数量达到要求时调用此函数
如果还有下一关则切换到下一关，否则显示胜利界面
]]
local function advanceToNextLevel()
    if currentLevel + 1 < #LEVELS then
        currentLevel = currentLevel + 1
        currentCorrectInLevel = 0

        local lvl = LEVELS[currentLevel + 1]
        if ui_elements.level_label then
            ui_elements.level_label:set_text(lvl.name)
        end
        if ui_elements.difficulty_tag then
            ui_elements.difficulty_tag:set_text(lvl.difficulty)
        end
        if ui_elements.need_count then
            ui_elements.need_count:set_text(tostring(lvl.needCorrect))
        end

        refreshUI()
        local success = refreshOptionsUI()
        if not success then resetGameToLevel(currentLevel) end
        showMessage("晋级" .. lvl.name .. "！难度" .. lvl.difficulty .. "，需再答对" .. lvl.needCorrect .. "题", false)
    else
        showVictoryScreen()
    end
end

--[[
处理用户选择正确答案
1. 将成语添加到接龙链
2. 更新已使用成语集合
3. 增加当前关卡正确计数
4. 延迟后检查是否需要进入下一关或显示胜利
@param selectedIdiom string 用户选择的成语
@param btnElement userdata 被点击的按钮元素
]]
local function handleCorrect(selectedIdiom, btnElement)
    table.insert(currentChain, selectedIdiom)
    usedSet[selectedIdiom] = true
    currentCorrectInLevel = currentCorrectInLevel + 1

    log.info("idiom_solitaire", "handleCorrect: currentCorrectInLevel=", currentCorrectInLevel, "currentLevel=", currentLevel)

    refreshUI()
    if btnElement and btnElement.container then
        if btnElement.container.set_bg_color then btnElement.container:set_bg_color(0xbddb92) end
        if btnElement.container.set_border_color then btnElement.container:set_border_color(0x6f9e3f) end
    end
    if btnElement and btnElement.label and btnElement.label.set_color then
        btnElement.label:set_color(0x2c4d1a)
    end
    showMessage("接龙成功！" .. selectedIdiom .. "  +1分", false)

    local levelData = LEVELS[currentLevel + 1]
    log.info("idiom_solitaire", "handleCorrect: levelData.needCorrect=", levelData.needCorrect, "currentCorrectInLevel >= levelData.needCorrect:", currentCorrectInLevel >= levelData.needCorrect)

    if currentCorrectInLevel >= levelData.needCorrect then
        log.info("idiom_solitaire", "handleCorrect: level completed, advancing to next level or showing victory")
        sys.timerStart(function()
            if ui_elements.option_buttons then
                for _, btn_data in ipairs(ui_elements.option_buttons) do
                    if btn_data then
                        if btn_data.container and btn_data.container.set_bg_color then btn_data.container:set_bg_color(0xfff4e2) end
                        if btn_data.container and btn_data.container.set_border_color then btn_data.container:set_border_color(0xeed6aa) end
                        if btn_data.label and btn_data.label.set_color then btn_data.label:set_color(0x4a311d) end
                    end
                end
            end

            if currentLevel + 1 < #LEVELS then
                advanceToNextLevel()
            else
                showVictoryScreen()
            end
            isWaiting = false
        end, 600)
    else
        sys.timerStart(function()
            if ui_elements.option_buttons then
                for _, btn_data in ipairs(ui_elements.option_buttons) do
                    if btn_data then
                        if btn_data.container and btn_data.container.set_bg_color then btn_data.container:set_bg_color(0xfff4e2) end
                        if btn_data.container and btn_data.container.set_border_color then btn_data.container:set_border_color(0xeed6aa) end
                        if btn_data.label and btn_data.label.set_color then btn_data.label:set_color(0x4a311d) end
                    end
                end
            end

            local success = refreshOptionsUI()
            if not success then showMessage("本关成语库紧张，可重置闯关", true) end
            isWaiting = false
        end, 500)
    end
end

--[[
处理用户选择错误答案
显示错误提示，并将按钮样式变为红色表示错误
@param selectedWord string 用户选择的词语
@param btnElement userdata 被点击的按钮元素
]]
local function handleWrong(selectedWord, btnElement)
    if btnElement and btnElement.container then
        if btnElement.container.set_bg_color then btnElement.container:set_bg_color(0xe6bcac) end
        if btnElement.container.set_border_color then btnElement.container:set_border_color(0xc1572e) end
    end
    if btnElement and btnElement.label and btnElement.label.set_color then
        btnElement.label:set_color(0x631d00)
    end
    local lastIdiom = currentChain[#currentChain]
    showMessage(selectedWord .. " 不是正确成语 / 接龙失败，需以「" .. getLastChar(lastIdiom) .. "」开头", true)

    sys.timerStart(function()
        if btnElement and btnElement.container then
            if btnElement.container.set_bg_color then btnElement.container:set_bg_color(0xfff4e2) end
            if btnElement.container.set_border_color then btnElement.container:set_border_color(0xeed6aa) end
        end
        if btnElement and btnElement.label and btnElement.label.set_color then
            btnElement.label:set_color(0x4a311d)
        end
        isWaiting = false
    end, 900)
end

--[[
处理选项按钮点击事件
根据用户选择的选项判断是否正确，并调用相应处理函数
@param index number 被点击的选项索引（1-based）
]]
local function onOptionClick(index)
    if isWaiting or gameCompleted then return end
    if #currentOptions == 0 or not correctAnswer then
        showMessage("请点击「换一批选项」或重置", true)
        return
    end

    local selected = currentOptions[index]
    if not selected then return end
    local lastIdiom = currentChain[#currentChain]
    local isReal = isValidIdiom(selected)
    local isCorrect = false

    if isReal and not usedSet[selected] and canChain(lastIdiom, selected) and selected == correctAnswer then
        isCorrect = true
    end

    isWaiting = true
    local btn = ui_elements.option_buttons[index]
    if isCorrect then
        handleCorrect(selected, btn)
    else
        handleWrong(selected, btn)
    end
end

--[[
刷新选项（换一批）
当用户点击"换一批选项"按钮时调用，重新生成选项
]]
local function refreshOptionsOnly()
    if isWaiting or gameCompleted then
        showMessage("请等待或游戏已通关", true)
        return
    end

    local success = refreshOptionsUI()
    if success then
        showMessage("已更换选项，请选择正确成语接龙", false)
    else
        showMessage("无法生成新选项，可重置闯关", true)
    end
end

--[[
重置游戏到指定关卡
用于初始化游戏或重新开始
@param levelIdx number 目标关卡索引（0-based）
]]
local function resetGameToLevel(levelIdx)
    gameCompleted = false
    log.info("idiom_solitaire", "resetGameToLevel called with levelIdx:", levelIdx)

    -- 先隐藏胜利界面
    if victory_container then
        log.info("idiom_solitaire", "resetGameToLevel: hiding victory_container")
        victory_container:hide()
    end

    -- 再显示游戏界面
    if ui_elements and ui_elements.game_main then
        log.info("idiom_solitaire", "resetGameToLevel: showing game_main")
        ui_elements.game_main:open()
    end

    -- 重置游戏状态
    currentLevel = levelIdx
    currentChain = {}
    usedSet = {}
    currentCorrectInLevel = 0

    local startMap = {"一马当先", "人山人海", "龙飞凤舞"}
    local start = startMap[levelIdx + 1] or "一马当先"
    table.insert(currentChain, start)
    usedSet[start] = true

    local lvl = LEVELS[levelIdx + 1]
    if ui_elements.level_label and ui_elements.level_label.set_text then
        ui_elements.level_label:set_text(lvl.name)
    end
    if ui_elements.difficulty_tag and ui_elements.difficulty_tag.set_text then
        ui_elements.difficulty_tag:set_text("第" .. lvl.id .. "关")
    end
    if ui_elements.need_count and ui_elements.need_count.set_text then
        ui_elements.need_count:set_text(tostring(lvl.needCorrect))
    end

    refreshUI()
    local success = refreshOptionsUI()
    log.info("idiom_solitaire", "resetGameToLevel: refreshOptionsUI success:", success)
end

--[[
完全重置游戏
从头开始第1关
]]
local function fullReset()
    resetGameToLevel(0)
end

--[[
返回游戏（用于重新开始）
与fullReset功能相同，提供语义化的函数名
]]
local function returnToGame()
    log.info("idiom_solitaire", "returnToGame: called, restarting game")
    fullReset()
end

--[[
退出游戏
关闭当前游戏窗口，返回应用商店
]]
local function exitGame()
    log.info("idiom_solitaire", "exitGame: called, win_id=", win_id)
    if win_id then
        exwin.close(win_id)
        log.info("idiom_solitaire", "exitGame: window closed")
    else
        log.warn("idiom_solitaire", "exitGame: win_id is nil")
    end
end

--[[
创建游戏用户界面
构建游戏的完整UI结构，包括：
- 主容器和游戏主界面
- 游戏头部（标题、关卡信息）
- 当前成语显示区域
- 选项容器区域（3个选项）
- 操作按钮区域（重来闯关、换一批选项）
- 消息提示区域
- 历史记录区域
]]
local function create_ui()
    if not airui then
        log.error("idiom_solitaire", "airui not available")
        return
    end

    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = 480, h = 800,
        color = 0xf5e7d3
    })

    if not main_container then
        log.error("idiom_solitaire", "main_container creation failed")
        return
    end

    local game_main = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = 480, h = 800,
        color = 0xfef7e8
    })

    local game_header = airui.container({
        parent = game_main,
        x = 0, y = 20,
        w = 480, h = 85,
        color = 0xfef7e8
    })

   
    
    airui.label({
        parent = game_header,
        x = 110, y = 15,
        w = 260, h = 30,
        align = airui.TEXT_ALIGN_CENTER,
        text = "成语接龙  闯三关",
        font_size = 25,
        color = 0x4f3a26
    })

    local level_info = airui.container({
        parent = game_header,
        x = 20, y = 52,
        w = 440, h = 29,
        color = 0xebddbc,
        radius = 25
    })

    ui_elements.difficulty_tag = airui.label({
        parent = level_info,
        x = 10, y = 5,
        w = 80, h = 18,
        align = airui.TEXT_ALIGN_CENTER,
        text = "第一关",
        font_size = 16,
        color = 0x4a311d
    })

    ui_elements.progress_text = airui.label({
        parent = level_info,
        x = 135, y = 5,
        w = 110, h = 18,
        align = airui.TEXT_ALIGN_CENTER,
        text = "进度 0 / 3",
        font_size = 16,
        color = 0x6b4c2c
    })

    -- 添加难度图标
    if airui.image then
        airui.image({
            parent = level_info,
            x = 300, y = 2,
            w = 30, h = 25,
            scale_mode = "fit",
            src = "/luadb/xxx.png"
        })
    end
    
    ui_elements.level_name_tag = airui.label({
        parent = level_info,
        x = 320, y = 5,
        w = 110, h = 18,
        align = airui.TEXT_ALIGN_CENTER,
        text = "初出茅庐",
        font_size = 16,
        color = 0x2d2418
    })
-- 当前成语显示区域
    local current_card = airui.container({
        parent = game_main,
        x = 20, y = 120,
        w = 440, h = 130,
        color = 0xfffaf0,
        radius = 28,
        border_color = 0xfff0db,
        border_width = 2
    })

    -- 添加龙图标
    if airui.image then
        airui.image({
            parent = current_card,
            x = 160, y = 6,
            w = 25, h = 29,
            scale_mode = "fit",
            src = "/luadb/long.png"
        })
    end
    
    airui.label({
        parent = current_card,
        x = 200, y = 10,
        w = 100, h = 20,
        align = airui.TEXT_ALIGN_CENTER,
        text = "当前龙首",
        font_size = 12,
        color = 0xbf8746
    })

    ui_elements.current_idiom = airui.label({
        parent = current_card,
        x = 80, y = 35,
        w = 280, h = 50,
        align = airui.TEXT_ALIGN_CENTER,
        text = "一马当先",
        font_size = 35,
        color = 0x5a2e18
    })

    -- 创建提示容器（与关卡信息容器颜色一致）
    local hint_container = airui.container({
        parent = current_card,
        x = 100, y = 80,
        w = 240, h = 35,
        color = 0xebddbc,
        radius = 16
    })
    
    -- 添加链接图标（放在容器上）
    if airui.image then
        airui.image({
            parent = hint_container,
            x = 10, y = 4,
            w = 24, h = 24,
            scale_mode = "fit",
            src = "/luadb/lj.png"
        })
    end
    
    ui_elements.last_char_hint = airui.label({
        parent = hint_container,
        x = 45, y = 9,
        w = 185, h = 23,
        align = airui.TEXT_ALIGN_CENTER,
        text = "下一成语需以「先」字开头",
        font_size = 14,
        color = 0x4e301c
    })

    local options_row = airui.container({
        parent = game_main,
        x = 20, y = 260,
        w = 440, h = 70,
        color = 0xfef7e8
    })

    ui_elements.option_buttons = {}
    for i = 1, 3 do
        -- 创建容器作为选项按钮
        local option_container = airui.container({
            parent = options_row,
            x = (i - 1) * 145 + 7, y = 4,
            w = 135, h = 62,
            color = 0xfff4e2,
            radius = 12,
            border_color = 0xeed6aa,
            border_width = 2
        })
        
        -- 创建标签显示文字
        local option_label = airui.label({
            parent = option_container,
            x = 0, y = 20,
            w = 120, h = 30,
            align = airui.TEXT_ALIGN_CENTER,
            text = "——",
            font_size = 20,
            color = 0x4a311d
        })
        
        -- 添加点击事件
        option_container:set_on_click(function() onOptionClick(i) end)
        
        -- 保存引用（保存容器和标签）
        table.insert(ui_elements.option_buttons, {container = option_container, label = option_label})
    end

    local action_row = airui.container({
        parent = game_main,
        x = 20, y = 350,
        w = 440, h = 50,
        color = 0xfef7e8
    })

    airui.button({
        parent = action_row,
        x = 5, y = 5,
        w = 215, h = 40,
        text = "重来闯关",
        font_size = 15,
        color = 0x3d2b18,
        bg_color = 0xe9cf9b,
        radius = 20,
        on_click = fullReset
    })

    airui.button({
        parent = action_row,
        x = 225, y = 5,
        w = 210, h = 40,
        text = "换一批选项",
        font_size = 15,
        color = 0x3d2b18,
        bg_color = 0xe9cf9b,
        radius = 20,
        on_click = refreshOptionsOnly
    })

    ui_elements.message_box = airui.container({
        parent = game_main,
        x = 20, y = 420,
        w = 440, h = 55,
        color = 0x2e281f,
        radius = 20
    })

    -- 添加星星图标（前）
    if airui.image then
        airui.image({
            parent = ui_elements.message_box,
            x = 50, y = 18,
            w = 24, h = 24,
            scale_mode = "fit",
            src = "/luadb/xx.png"
        })
    end
    
    ui_elements.message_text = airui.label({
        parent = ui_elements.message_box,
        x = 100, y = 20,
        w = 250, h = 35,
        align = airui.TEXT_ALIGN_CENTER,
        text = "选择正确成语接龙，累计答对3题晋级！",
        font_size = 14,
        color = 0xf7e6c4
    })
    
    -- 添加星星图标（后）
    if airui.image then
        airui.image({
            parent = ui_elements.message_box,
            x = 380, y = 18,
            w = 24, h = 24,
            scale_mode = "fit",
            src = "/luadb/xx.png"
        })
    end
    log.info("idiom_solitaire", "message_text:", ui_elements.message_text, "type:", type(ui_elements.message_text))

    local history_area = airui.container({
        parent = game_main,
        x = 20, y = 500,
        w = 440, h = 240,
        color = 0xebddbc,
        radius = 16
    })

    local history_header = airui.container({
        parent = history_area,
        x = 10, y = 4,
        w = 420, h = 26,
        color = 0xebddbc
    })

    airui.label({
        parent = history_header,
        x = 10, y = 5,
        w = 80, h = 18,
        align = airui.TEXT_ALIGN_LEFT,
        text = "接龙长卷",
        font_size = 12,
        color = 0x7b5a36
    })

    local correct_info = airui.container({
        parent = history_header,
        x = 260, y = 5,
        w = 150, h = 18,
        color = 0xebddbc
    })

    airui.label({
        parent = correct_info,
        x = 0, y = 0,
        w = 55, h = 18,
        align = airui.TEXT_ALIGN_RIGHT,
        text = "本关答对",
        font_size = 12,
        color = 0x7b5a36
    })

    ui_elements.correct_count = airui.label({
        parent = correct_info,
        x = 60, y = 0,
        w = 22, h = 18,
        align = airui.TEXT_ALIGN_CENTER,
        text = "0",
        font_size = 12,
        color = 0x2d7d2d
    })

    airui.label({
        parent = correct_info,
        x = 84, y = 0,
        w = 12, h = 18,
        align = airui.TEXT_ALIGN_CENTER,
        text = "/",
        font_size = 12,
        color = 0x7b5a36
    })

    ui_elements.need_count = airui.label({
        parent = correct_info,
        x = 96, y = 0,
        w = 22, h = 18,
        align = airui.TEXT_ALIGN_CENTER,
        text = "3",
        font_size = 12,
        color = 0x7b5a36
    })

    ui_elements.history_list = airui.container({
        parent = history_area,
        x = 10, y = 32,
        w = 420, h = 198,
        color = 0xfef7e8,
        radius = 12
    })

    ui_elements.history_area = history_area
    ui_elements.option_area = options_row
    ui_elements.top_area = game_header
    ui_elements.bottom_area = action_row
    ui_elements.game_main = game_main
    
end

--[[
窗口事件处理：打开成语接龙游戏窗口
当接收到 OPEN_IDIOM_SOLITAIRE_WIN 事件时调用
负责创建新窗口或关闭已存在的窗口
]]
sys.subscribe("OPEN_IDIOM_SOLITAIRE_WIN", function()
    if win_id then
        exwin.close(win_id)
    end

    win_id = exwin.open({
        name = "IdiomSolitaire",
        res_path = "/app_store/IdiomSolitaire/res/",
        auto_align = false,
        on_create = function()
            -- 窗口创建时初始化UI并开始第1关
            create_ui()
            resetGameToLevel(0)
        end,
        on_destroy = function()
            -- 窗口销毁时清理资源
            if main_container then
                main_container:destroy()
                main_container = nil
            end
            if victory_container then
                victory_container:destroy()
                victory_container = nil
            end
            ui_elements = {}
        end
    })
end)