--[[
@module mock
@summary AIR KTV 点歌系统 · 数据层（docs/index.html 1:1）
         只放数据与纯函数；可变状态集中在 mock.S。
]]

local mock = {}

mock.GRADIENTS = {
    {0x477BFF,0x7B61FF},{0x19D5D0,0x3B82F6},{0xF857A6,0xFF5858},
    {0xF7B733,0xFC4A1A},{0x11998E,0x38EF7D},{0x8E2DE2,0x4A00E0},
    {0x00C6FF,0x0072FF},{0xEE0979,0xFF6A00},{0x4568DC,0xB06AB3},
    {0x0F2027,0x2C5364},{0xFF512F,0xDD2476},{0x3A1C71,0xD76D77},
    {0x1D976C,0x93F9B9},{0xC33764,0x1D2671},{0xF2994A,0xF2C94C},
    {0x5F2584,0xC06C84},{0x2B5876,0x4E4376},{0xEB3349,0xF45C43},
}

-- 首页快捷入口配色：按设计稿取色（左亮右深），g[1]=亮 g[2]=深
mock.TILE_GRADS = {
    {0x5A85F8,0x3C63E8},{0x9A86F8,0x7B5CF0},{0x25D0D8,0x11A9BE},
    {0xFF9548,0xF26B34},{0xFF3D8B,0xF41E63},{0x22C893,0x0E9E72},
    {0x5A85F8,0x5457F0},{0x9AA3B8,0x7C869C},
}
-- 快捷功能图标配色：{上亮, 下深}，按设计稿取色
mock.FUNC_GRADS = {
    {0x7C7CF9,0x4F46E5},{0x9F7BFF,0x6D4BF6},{0x3EE0CE,0x14A69B},
    {0xF87CB8,0xE0447F},{0xFFAB5E,0xF2782B},{0x3FE0A6,0x16A06E},
    {0x5B9BFF,0x2F6BE8},{0xFFCE5C,0xF79A1E},
}

mock.SONGS = {
    {n="孤勇者",a="陈奕迅",d="4:16",c={"流行歌曲","影视金曲","网络热歌"},l="G"},
    {n="晴天",a="周杰伦",d="4:29",c={"华语歌曲","经典老歌","流行歌曲"},l="Q"},
    {n="海阔天空",a="BEYOND",d="5:26",c={"粤语歌曲","经典老歌"},l="H"},
    {n="Shape of You",a="Ed Sheeran",d="3:53",c={"欧美歌曲","流行歌曲"},l="S"},
    {n="起风了",a="买辣椒也用券",d="5:23",c={"网络热歌","流行歌曲"},l="Q"},
    {n="富士山下",a="陈奕迅",d="4:18",c={"粤语歌曲","经典老歌"},l="F"},
    {n="夜曲",a="周杰伦",d="3:48",c={"华语歌曲","经典老歌"},l="Y"},
    {n="Dynamite",a="BTS",d="3:19",c={"日韩歌曲","流行歌曲"},l="D"},
    {n="月亮代表我的心",a="邓丽君",d="3:29",c={"经典老歌","华语歌曲"},l="Y"},
    {n="可能",a="程响",d="4:12",c={"网络热歌","流行歌曲"},l="K"},
    {n="红日",a="李克勤",d="4:40",c={"粤语歌曲","经典老歌"},l="H"},
    {n="Perfect",a="Ed Sheeran",d="4:21",c={"欧美歌曲","影视金曲"},l="P"},
    {n="稻香",a="周杰伦",d="3:43",c={"华语歌曲","流行歌曲"},l="D"},
    {n="天花乱坠",a="郑秀文",d="3:35",c={"粤语歌曲"},l="T"},
    {n="First Love",a="宇多田光",d="4:18",c={"日韩歌曲","经典老歌"},l="F"},
    {n="演员",a="薛之谦",d="4:21",c={"华语歌曲","流行歌曲"},l="Y"},
    {n="My Heart Will Go On",a="Celine Dion",d="4:39",c={"欧美歌曲","影视金曲"},l="M"},
    {n="光辉岁月",a="BEYOND",d="4:58",c={"粤语歌曲","经典老歌"},l="G"},
    {n="芒种",a="音阙诗听",d="3:32",c={"网络热歌"},l="M"},
    {n="Love Story",a="Taylor Swift",d="3:55",c={"欧美歌曲","流行歌曲"},l="L"},
    {n="青花瓷",a="周杰伦",d="3:58",c={"华语歌曲","经典老歌"},l="Q"},
    {n="K歌之王",a="陈奕迅",d="5:22",c={"粤语歌曲","经典老歌"},l="K"},
    {n="大鱼",a="周深",d="4:36",c={"影视金曲","华语歌曲"},l="D"},
    {n="Bad Guy",a="Billie Eilish",d="3:14",c={"欧美歌曲","流行歌曲"},l="B"},
    {n="朋友",a="周华健",d="4:13",c={"经典老歌","华语歌曲"},l="P"},
    {n="向云端",a="小霞 / 海洋Bo",d="4:25",c={"网络热歌"},l="X"},
    {n="童话",a="光良",d="4:02",c={"华语歌曲","经典老歌"},l="T"},
    {n="See You Again",a="Wiz Khalifa",d="3:49",c={"欧美歌曲","影视金曲"},l="S"},
    {n="听海",a="张惠妹",d="4:56",c={"华语歌曲","经典老歌"},l="T"},
    {n="奢香夫人",a="凤凰传奇",d="4:35",c={"网络热歌","流行歌曲"},l="S"},
    {n="Lemon",a="米津玄师",d="4:17",c={"日韩歌曲"},l="L"},
    {n="吻别",a="张学友",d="5:12",c={"华语歌曲","经典老歌"},l="W"},
    {n="小幸运",a="田馥甄",d="4:22",c={"影视金曲","流行歌曲"},l="X"},
    {n="摇太阳",a="凤凰传奇",d="3:58",c={"网络热歌"},l="Y"},
    {n="Yesterday",a="The Beatles",d="2:05",c={"欧美歌曲","经典老歌"},l="Y"},
    {n="静夜思",a="李荣浩",d="4:08",c={"华语歌曲","流行歌曲"},l="J"},
}

mock.ARTISTS = {
    {n="周杰伦",t="男",c=42,l="Z"},{n="陈奕迅",t="男",c=38,l="C"},
    {n="邓丽君",t="女",c=31,l="D"},{n="BEYOND",t="组合",c=26,l="B"},
    {n="张学友",t="男",c=35,l="Z"},{n="Ed Sheeran",t="男",c=19,l="E"},
    {n="Taylor Swift",t="女",c=24,l="T"},{n="BTS",t="组合",c=22,l="B"},
    {n="薛之谦",t="男",c=28,l="X"},{n="张惠妹",t="女",c=20,l="Z"},
    {n="凤凰传奇",t="组合",c=18,l="F"},{n="光良",t="男",c=15,l="G"},
    {n="宇多田光",t="女",c=12,l="Y"},{n="米津玄师",t="男",c=11,l="M"},
    {n="周深",t="男",c=23,l="Z"},{n="田馥甄",t="女",c=16,l="T"},
    {n="Billie Eilish",t="女",c=14,l="B"},{n="李荣浩",t="男",c=21,l="L"},
}

mock.CATS = {"华语歌曲","粤语歌曲","欧美歌曲","日韩歌曲","经典老歌","流行歌曲","网络热歌","影视金曲"}

mock.PLAYLISTS = {
    {n="经典怀旧",d="那些年，我们一起听过的旋律",c=88},
    {n="流行热歌",d="当下最火的流行金曲",c=126},
    {n="情歌对唱",d="适合双人合唱的浪漫曲目",c=64},
    {n="派对嗨歌",d="点燃全场的动感节奏",c=97},
    {n="欧美金曲",d="经典英文歌精选",c=75},
    {n="粤语经典",d="港乐黄金年代代表作",c=58},
}

mock.RANKS = {
    {name="热门点唱榜",ids={0,1,4,2,15,8,12,22}},
    {name="新歌榜",ids={25,9,18,31,33,30,20,5}},
    {name="飙升榜",ids={26,4,9,0,35,14,29,19}},
    {name="经典金曲榜",ids={8,2,6,24,32,1,34,16}},
}

mock.AC_MODES = {
    {key="cool",name="制冷",sym="snow",desc="快速降温"},
    {key="heat",name="制热",sym="fire",desc="温暖空间"},
    {key="fan",name="送风",sym="wind",desc="通风换气"},
    {key="dry",name="除湿",sym="drop",desc="干爽舒适"},
}
mock.AC_FANS = {
    {key="auto",name="自动",desc="智能调速"},
    {key="low",name="低速",desc="轻柔送风"},
    {key="mid",name="中速",desc="均衡送风"},
    {key="high",name="高速",desc="强劲送风"},
}

mock.S = {
    page="home", selected=-1, cat=1,
    artistFilter="全部", artistLetter="全部",
    ordered={{i=0,playing=true},{i=2,playing=false},{i=12,playing=false},
             {i=8,playing=false},{i=5,playing=false},{i=6,playing=false},
             {i=24,playing=false},{i=14,playing=false},{i=19,playing=false}},
    playIndex=0, playing=true, progress=34, play_sec=87,
    volume=64, brightness=100,
    mute=false, origin=false, atmos=false,
    pitch=50, micVol=70,
    acTemp=24, acOn=true, acMode="cool", acFan="auto",
    theme="blue", mode="dark",
    rank="热门点唱榜", plDetail=-1,
    query="", eqOpen=false, acOpen=false, funcPop=false,
}

function mock.song(i) return mock.SONGS[(i or 0)+1] end
function mock.durSec(d)
    local p = {}
    for x in tostring(d):gmatch("%d+") do p[#p+1]=tonumber(x) end
    return (p[1] or 0)*60 + (p[2] or 0)
end
function mock.fmt(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    return string.format("%02d:%02d", math.floor(sec/60), sec%60)
end
function mock.gradient(i) return mock.GRADIENTS[((i or 0) % #mock.GRADIENTS)+1] end

function mock.search(q)
    q = tostring(q or ""):upper()
    if q == "" then return {} end
    local r = {}
    for i=1,#mock.SONGS do
        local s = mock.SONGS[i]
        if s.n:upper():find(q,1,true) or s.a:upper():find(q,1,true) or s.l == q then
            r[#r+1] = i-1
        end
    end
    return r
end

function mock.rankList()
    for i=1,#mock.RANKS do
        if mock.RANKS[i].name == mock.S.rank then return mock.RANKS[i].ids end
    end
    return mock.RANKS[1].ids
end

function mock.acStatus()
    if not mock.S.acOn then return "空调已关闭" end
    local mn,fn = "制冷","自动风"
    for _,v in ipairs(mock.AC_MODES) do if v.key==mock.S.acMode then mn=v.name end end
    for _,v in ipairs(mock.AC_FANS) do if v.key==mock.S.acFan then fn=v.name.."风" end end
    return "运行中 - "..mn.." - "..fn.." - "..mock.S.acTemp.."C"
end

function mock.nextOrder(step)
    local S = mock.S
    if #S.ordered == 0 then return nil end
    local cur = 1
    for i=1,#S.ordered do if S.ordered[i].i==S.playIndex then cur=i break end end
    local nxt = ((cur-1+(step or 1)) % #S.ordered)+1
    return nxt, S.ordered[nxt]
end

function mock.reset()
    local S = mock.S
    S.volume, S.brightness, S.theme, S.mode = 64, 100, "blue", "dark"
end

return mock
