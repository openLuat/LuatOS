--[[
@module mock
@summary 3D 打印机 - 演示数据（模型列表 / 打印参数 / 温度）
         与 preview.html 的 FILES 数组完全一致（3 页 × 5 个模型）
]]

local mock = {}

-- 每页 5 个模型：name 名称, date 日期, kind 预览图形种类（page_3d 里绘制）
mock.FILES = {
    {   -- 第 1 页
        { name = "牛奶盒",     date = "2022/09/12", kind = "milk"  },
        { name = "方块兔",     date = "2022/11/14", kind = "bunny" },
        { name = "马克杯",     date = "2022/10/05", kind = "mug"   },
        { name = "微笑太阳",   date = "2022/07/03", kind = "sun"   },
        { name = "粉红小屋",   date = "2022/08/21", kind = "house" },
    },
    {   -- 第 2 页
        { name = "巧克力小蛋糕", date = "2022/10/21", kind = "cake"   },
        { name = "齿轮",         date = "2022/11/02", kind = "gear"   },
        { name = "花瓶",         date = "2022/09/28", kind = "vase"   },
        { name = "小黄鸭",       date = "2022/06/15", kind = "duck"   },
        { name = "小熊",         date = "2022/12/01", kind = "bear"   },
    },
    {   -- 第 3 页
        { name = "火箭",     date = "2022/05/09", kind = "rocket" },
        { name = "六角笔筒", date = "2022/07/18", kind = "pen"    },
        { name = "龙猫",     date = "2022/11/25", kind = "cat"    },
        { name = "星球",     date = "2022/04/02", kind = "planet" },
        { name = "饼干模具", date = "2022/08/30", kind = "cookie" },
    },
}

mock.PAGE_N = 3          -- 总页数
mock.PAGE_SIZE = 5       -- 每页条数

-- 打印参数（视频里的固定读数）
mock.PARAM = {
    nozzle    = 170,     -- 喷头温度
    nozzle_max= 200,
    fan       = 60,      -- 风扇 %
    bed       = 60,      -- 热床温度
    bed_max   = 60,
    layer     = 0.1,     -- 层高 mm
}

-- 稳定伪随机（同城市/同文件读数不跳变）
local seed = 12345
function mock.rand(key, lo, hi, step)
    local h = 0
    for i = 1, #key do h = (h * 31 + string.byte(key, i)) % 100000 end
    local v = lo + (h % math.floor((hi - lo) / (step or 1) + 1)) * (step or 1)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return v
end

function mock.get(page, idx)
    local p = mock.FILES[page or 1]
    if not p then return mock.FILES[1][1] end
    return p[idx or 1] or p[1]
end

return mock
