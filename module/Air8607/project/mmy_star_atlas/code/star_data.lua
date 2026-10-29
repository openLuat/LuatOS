--[[
@module  star_data
@summary 星表数据：亮星、星座连线、深空天体、银河带
@version 1.0
@date    2026.10.28

星表列序（紧凑数组，省 flash）：
  [1] id  [2] 中文名  [3] 拜耳名  [4] 星座  [5] ra(小时)  [6] dec(度)  [7] 星等  [8] B-V
数据取 J2000 近似值，用于演示足够（误差 < 0.1°）。
]]

local M = {}

local ROWS = {
    -- ===== 全天最亮的一批 =====
    {"sirius",    "天狼星",   "α CMa", "CMa", 6.752, -16.72, -1.46, 0.00},
    {"canopus",   "老人星",   "α Car", "Car", 6.399, -52.70, -0.74, 0.15},
    {"rigil",     "南门二",   "α Cen", "Cen", 14.660, -60.83, -0.27, 0.71},
    {"arcturus",  "大角星",   "α Boo", "Boo", 14.261, 19.18, -0.05, 1.23},
    {"vega",      "织女星",   "α Lyr", "Lyr", 18.615, 38.78, 0.03, 0.00},
    {"capella",   "五车二",   "α Aur", "Aur", 5.278, 45.99, 0.08, 0.80},
    {"rigel",     "参宿七",   "β Ori", "Ori", 5.242, -8.20, 0.13, -0.03},
    {"procyon",   "南河三",   "α CMi", "CMi", 7.655, 5.22, 0.34, 0.42},
    {"achernar",  "水委一",   "α Eri", "Eri", 1.629, -57.24, 0.46, -0.16},
    {"betelgeuse","参宿四",   "α Ori", "Ori", 5.919, 7.41, 0.50, 1.85},
    {"hadar",     "马腹一",   "β Cen", "Cen", 14.064, -60.37, 0.61, -0.23},
    {"altair",    "牛郎星",   "α Aql", "Aql", 19.846, 8.87, 0.77, 0.22},
    {"acrux",     "十字架二", "α Cru", "Cru", 12.443, -63.10, 0.77, -0.24},
    {"aldebaran", "毕宿五",   "α Tau", "Tau", 4.599, 16.51, 0.85, 1.54},
    {"antares",   "心宿二",   "α Sco", "Sco", 16.490, -26.43, 0.96, 1.83},
    {"spica",     "角宿一",   "α Vir", "Vir", 13.420, -11.16, 0.98, -0.23},
    {"pollux",    "北河三",   "β Gem", "Gem", 7.755, 28.03, 1.14, 1.00},
    {"fomalhaut", "北落师门", "α PsA", "PsA", 22.961, -29.62, 1.16, 0.09},
    {"deneb",     "天津四",   "α Cyg", "Cyg", 20.690, 45.28, 1.25, 0.09},
    {"mimosa",    "十字架三", "β Cru", "Cru", 12.795, -59.69, 1.25, -0.23},
    {"regulus",   "轩辕十四", "α Leo", "Leo", 10.139, 11.97, 1.40, -0.11},
    {"adhara",    "弧矢七",   "ε CMa", "CMa", 6.977, -28.97, 1.50, -0.21},
    {"castor",    "北河二",   "α Gem", "Gem", 7.577, 31.89, 1.58, 0.03},
    {"gacrux",    "十字架一", "γ Cru", "Cru", 12.519, -57.11, 1.63, 1.59},
    {"shaula",    "尾宿八",   "λ Sco", "Sco", 17.560, -37.10, 1.62, -0.22},
    {"bellatrix", "参宿五",   "γ Ori", "Ori", 5.418, 6.35, 1.64, -0.22},
    {"elnath",    "五车五",   "β Tau", "Tau", 5.438, 28.61, 1.65, -0.13},
    {"miaplac",   "南船五",   "β Car", "Car", 9.220, -69.72, 1.69, 0.00},
    {"alnilam",   "参宿二",   "ε Ori", "Ori", 5.604, -1.20, 1.69, -0.18},
    {"alnair",    "鹤一",     "α Gru", "Gru", 22.137, -46.96, 1.73, -0.13},
    {"alioth",    "北斗五",   "ε UMa", "UMa", 12.900, 55.96, 1.76, 0.00},
    {"dubhe",     "北斗一",   "α UMa", "UMa", 11.062, 61.75, 1.79, 1.07},
    {"mirfak",    "天船三",   "α Per", "Per", 3.405, 49.86, 1.79, 0.48},
    {"wezen",     "弧矢一",   "δ CMa", "CMa", 7.140, -26.39, 1.83, 0.68},
    {"sargas",    "尾宿五",   "θ Sco", "Sco", 17.622, -42.99, 1.86, 0.40},
    {"kaus_aust", "箕宿三",   "ε Sgr", "Sgr", 18.403, -34.38, 1.85, -0.03},
    {"avior",     "海石一",   "ε Car", "Car", 8.375, -59.51, 1.86, 1.28},
    {"alkaid",    "北斗七",   "η UMa", "UMa", 13.792, 49.31, 1.86, -0.19},
    {"menkalin",  "五车三",   "β Aur", "Aur", 5.992, 44.95, 1.90, 0.08},
    {"atria",     "三角形三", "α TrA", "TrA", 16.811, -69.03, 1.91, 1.44},
    {"alhena",    "井宿三",   "γ Gem", "Gem", 6.628, 16.40, 1.93, 0.00},
    {"peacock",   "孔雀十一", "α Pav", "Pav", 20.427, -56.74, 1.94, -0.20},
    {"alsephina", "天狗五",   "δ Vel", "Vel", 8.745, -54.71, 1.96, 0.04},
    {"mirzam",    "军市一",   "β CMa", "CMa", 6.378, -17.96, 1.98, -0.23},
    {"polaris",   "北极星",   "α UMi", "UMi", 2.530, 89.26, 1.98, 0.60},
    {"alphard",   "星宿一",   "α Hya", "Hya", 9.460, -8.66, 1.98, 1.44},
}

local function add(list)
    for i = 1, #list do ROWS[#ROWS + 1] = list[i] end
end

add({
    {"hamal",     "娄宿三",   "α Ari", "Ari", 2.119, 23.46, 2.00, 1.15},
    {"diphda",    "土司空",   "β Cet", "Cet", 0.726, -17.99, 2.04, 1.02},
    {"nunki",     "斗宿四",   "σ Sgr", "Sgr", 18.921, -26.30, 2.05, -0.13},
    {"menkent",   "库楼三",   "θ Cen", "Cen", 14.111, -36.37, 2.06, 1.01},
    {"mirach",    "奎宿九",   "β And", "And", 1.162, 35.62, 2.06, 1.58},
    {"alpheratz", "壁宿二",   "α And", "And", 0.140, 29.09, 2.06, -0.11},
    {"rasalhague","候",       "α Oph", "Oph", 17.582, 12.56, 2.08, 0.15},
    {"kochab",    "帝星",     "β UMi", "UMi", 14.845, 74.16, 2.08, 1.47},
    {"saiph",     "参宿六",   "κ Ori", "Ori", 5.796, -9.67, 2.09, -0.17},
    {"almak",     "天大将军", "γ And", "And", 2.065, 42.33, 2.10, 1.37},
    {"algol",     "大陵五",   "β Per", "Per", 3.136, 40.96, 2.12, 0.05},
    {"denebola",  "五帝座一", "β Leo", "Leo", 11.818, 14.57, 2.14, 0.09},
    {"aspidiske", "海石二",   "ι Car", "Car", 9.284, -59.28, 2.21, 0.18},
    {"naos",      "弧矢增二", "ζ Pup", "Pup", 8.060, -39.99, 2.21, -0.27},
    {"alphecca",  "贯索四",   "α CrB", "CrB", 15.578, 26.71, 2.22, -0.02},
    {"mintaka",   "参宿三",   "δ Ori", "Ori", 5.533, -0.30, 2.23, -0.22},
    {"sadr",      "天津一",   "γ Cyg", "Cyg", 20.371, 40.26, 2.23, 0.68},
    {"eltanin",   "天棓四",   "γ Dra", "Dra", 17.943, 51.49, 2.23, 1.52},
    {"mizar",     "开阳",     "ζ UMa", "UMa", 13.399, 54.93, 2.23, 0.02},
    {"schedar",   "王良四",   "α Cas", "Cas", 0.675, 56.54, 2.24, 1.17},
    {"caph",      "王良一",   "β Cas", "Cas", 0.153, 59.15, 2.28, 0.34},
    {"dschubba",  "房宿三",   "δ Sco", "Sco", 16.005, -22.62, 2.29, -0.12},
    {"eps_sco",   "尾宿二",   "ε Sco", "Sco", 16.836, -34.29, 2.29, 1.14},
    {"izar",      "梗河一",   "ε Boo", "Boo", 14.750, 27.07, 2.37, 0.97},
    {"merak",     "北斗二",   "β UMa", "UMa", 11.031, 56.38, 2.37, 0.03},
    {"enif",      "危宿三",   "ε Peg", "Peg", 21.736, 9.88, 2.38, 1.53},
    {"sabik",     "天市右垣", "η Oph", "Oph", 17.173, -15.72, 2.43, 0.06},
    {"phecda",    "北斗三",   "γ UMa", "UMa", 11.897, 53.69, 2.44, 0.04},
    {"scheat",    "室宿二",   "β Peg", "Peg", 23.063, 28.08, 2.44, 1.67},
    {"aludra",    "弧矢二",   "η CMa", "CMa", 7.402, -29.30, 2.45, -0.08},
    {"alderamin", "天钩五",   "α Cep", "Cep", 21.310, 62.59, 2.45, 0.22},
    {"markab",    "室宿一",   "α Peg", "Peg", 23.079, 15.21, 2.48, -0.04},
    {"gienah",    "天津九",   "ε Cyg", "Cyg", 20.770, 33.97, 2.48, 1.03},
    {"ascella",   "斗宿六",   "ζ Sgr", "Sgr", 19.044, -29.88, 2.60, 0.05},
    {"zubenesch", "氐宿四",   "β Lib", "Lib", 15.283, -9.38, 2.61, -0.11},
    {"graffias",  "房宿四",   "β Sco", "Sco", 16.090, -19.81, 2.62, -0.07},
    {"unukalhai", "天市右垣", "α Ser", "Ser", 15.738, 6.43, 2.63, 1.17},
    {"phact",     "丈人二",   "α Col", "Col", 5.661, -34.07, 2.65, -0.12},
    {"muphrid",   "右摄提一", "η Boo", "Boo", 13.911, 18.40, 2.68, 0.58},
    {"lesath",    "尾宿九",   "υ Sco", "Sco", 17.513, -37.30, 2.70, -0.22},
    {"tarazed",   "河鼓三",   "γ Aql", "Aql", 19.771, 10.61, 2.72, 1.52},
    {"yed_prior", "韩",       "δ Oph", "Oph", 16.239, -3.69, 2.73, 1.58},
    {"porrima",   "东上相",   "γ Vir", "Vir", 12.694, -1.45, 2.74, 0.36},
    {"zubenelg",  "氐宿一",   "α Lib", "Lib", 14.848, -16.04, 2.75, 0.15},
    {"cebalrai",  "宗正一",   "β Oph", "Oph", 17.724, 4.57, 2.76, 1.16},
    {"korneph",   "河中",     "β Her", "Her", 16.503, 31.60, 2.78, 0.94},
    {"cursa",     "玉井三",   "β Eri", "Eri", 5.131, -5.09, 2.78, 0.13},
    {"deltacru",  "十字架四", "δ Cru", "Cru", 12.253, -58.75, 2.79, -0.20},
    {"rastaban",  "天棓三",   "β Dra", "Dra", 17.507, 52.30, 2.79, 0.98},
    {"kaus_bor",  "斗宿五",   "λ Sgr", "Sgr", 18.466, -25.42, 2.81, 0.10},
    {"algenib",   "壁宿一",   "γ Peg", "Peg", 0.221, 15.18, 2.83, -0.23},
    {"vindemi",   "东次将",   "ε Vir", "Vir", 13.036, 10.96, 2.85, 0.94},
    {"zeta_per",  "卷舌四",   "ζ Per", "Per", 3.902, 31.88, 2.85, -0.05},
    {"tejat",     "井宿二",   "μ Gem", "Gem", 6.383, 22.51, 2.87, 1.64},
    {"delta_cyg", "天津二",   "δ Cyg", "Cyg", 19.749, 45.13, 2.87, -0.03},
    {"eps_per",   "卷舌二",   "ε Per", "Per", 3.964, 40.01, 2.89, -0.18},
    {"acamar",    "天园六",   "θ Eri", "Eri", 2.971, -40.30, 2.88, 0.13},
    {"albaldah",  "建三",     "π Sgr", "Sgr", 19.162, -21.02, 2.89, 0.35},
    {"gomeisa",   "南河二",   "β CMi", "CMi", 7.453, 8.29, 2.89, -0.09},
    {"alniyat",   "心宿一",   "σ Sco", "Sco", 16.353, -25.59, 2.89, -0.04},
    {"sadalsuud", "虚宿一",   "β Aqr", "Aqr", 21.526, -5.57, 2.90, 0.83},
    {"gamma_per", "天船二",   "γ Per", "Per", 3.080, 53.51, 2.93, 0.70},
    {"delta_crv", "轸宿三",   "δ Crv", "Crv", 12.497, -16.52, 2.95, 0.33},
    {"zaurak",    "天园四",   "γ Eri", "Eri", 3.967, -13.51, 2.95, 1.59},
    {"sadalmelik","危宿一",   "α Aqr", "Aqr", 22.096, -0.32, 2.95, 0.98},
    {"alnasl",    "箕宿一",   "γ Sgr", "Sgr", 18.097, -30.42, 2.98, 1.00},
    {"mebsuta",   "井宿四",   "ε Gem", "Gem", 6.732, 25.13, 2.98, 0.94},
    {"pherkad",   "太子",     "γ UMi", "UMi", 15.345, 71.83, 3.00, 0.05},
    {"beta_tri",  "娄宿九",   "β Tri", "Tri", 2.159, 34.99, 3.00, 0.14},
    {"zeta_tau",  "天关",     "ζ Tau", "Tau", 5.627, 21.14, 3.00, -0.15},
    {"eps_crv",   "轸宿二",   "ε Crv", "Crv", 12.169, -22.62, 3.02, 1.33},
    {"gamma_crv", "轸宿一",   "γ Crv", "Crv", 12.263, -17.54, 2.58, -0.11},
    {"seginus",   "右垣一",   "γ Boo", "Boo", 14.535, 38.31, 3.03, 1.06},
    {"almaaz",    "五车四",   "ε Aur", "Aur", 5.033, 43.82, 3.03, 0.54},
    {"albireo",   "辇道增七", "β Cyg", "Cyg", 19.512, 27.96, 3.05, 1.13},
    {"gamma_umi", "天玑",     "γ UMi", "UMi", 15.734, 71.83, 3.05, 0.05},
    {"wazn",      "子二",     "β Col", "Col", 5.849, -35.77, 3.12, 1.16},
    {"errai",     "少卫增八", "γ Cep", "Cep", 23.656, 77.63, 3.21, 1.03},
    {"sulafat",   "渐台二",   "γ Lyr", "Lyr", 18.982, 32.69, 3.25, -0.05},
    {"edasich",   "左枢",     "ι Dra", "Dra", 15.416, 58.97, 3.29, 1.16},
    {"theta_leo", "西次相",   "θ Leo", "Leo", 11.237, 15.43, 3.32, -0.01},
    {"alfirk",    "上卫增一", "β Cep", "Cep", 21.478, 70.56, 3.23, -0.22},
    {"hassaleh",  "五车一",   "ι Aur", "Aur", 4.950, 33.17, 2.69, 1.53},
    {"kaus_med",  "箕宿二",   "δ Sgr", "Sgr", 18.350, -29.83, 2.70, 1.38},
    {"kappavel",  "天社五",   "κ Vel", "Vel", 9.368, -55.01, 2.50, -0.14},
    {"muvel",     "天社三",   "μ Vel", "Vel", 10.778, -49.42, 2.69, 1.04},
    {"sheliak",   "渐台三",   "β Lyr", "Lyr", 18.834, 33.36, 3.45, 0.00},
    {"megrez",    "北斗四",   "δ UMa", "UMa", 12.257, 57.03, 3.31, 0.08},
    {"grumium",   "天棓二",   "ξ Dra", "Dra", 17.892, 56.87, 3.75, 1.16},
    {"thuban",    "右枢",     "α Dra", "Dra", 14.073, 64.38, 3.65, -0.05},
    {"yildun",    "勾陈增九", "δ UMi", "UMi", 17.537, 86.59, 4.35, 0.02},
    {"nekkar",    "七公增五", "β Boo", "Boo", 15.032, 40.39, 3.49, 0.97},
    {"del_leo",   "西上相",   "δ Leo", "Leo", 11.235, 20.52, 2.56, 0.13},
    {"gamma_cas", "策",       "γ Cas", "Cas", 0.945, 60.72, 2.15, -0.15},
    {"delta_cas", "阁道三",   "δ Cas", "Cas", 1.430, 60.24, 2.68, 0.13},
    {"eps_cas",   "阁道二",   "ε Cas", "Cas", 1.907, 63.67, 3.38, -0.15},
    {"zavijava",  "右执法",   "β Vir", "Vir", 11.845, 1.76, 3.61, 0.55},
    {"alshain",   "河鼓一",   "β Aql", "Aql", 19.922, 6.41, 3.71, 0.86},
    {"sham",      "左旗一",   "α Sge", "Sge", 19.668, 18.01, 4.39, 0.78},
    {"sualocin",  "瓠瓜一",   "α Del", "Del", 20.660, 15.91, 3.77, -0.06},
    {"rotanev",   "瓠瓜四",   "β Del", "Del", 20.626, 14.60, 3.63, 0.44},
})

-- ===== 星座连线（星表 id 两两相连，用来勾出星座骨架）=====
M.lines = {
    -- 大熊座 · 北斗七星
    {"dubhe", "merak"}, {"merak", "phecda"}, {"phecda", "megrez"},
    {"megrez", "alioth"}, {"alioth", "mizar"}, {"mizar", "alkaid"},
    {"megrez", "dubhe"},
    -- 猎户座
    {"betelgeuse", "bellatrix"}, {"bellatrix", "mintaka"},
    {"mintaka", "alnilam"}, {"alnilam", "alnitak"},
    {"alnitak", "betelgeuse"}, {"mintaka", "rigel"},
    {"alnitak", "saiph"}, {"rigel", "saiph"},
    -- 仙后座 W
    {"caph", "schedar"}, {"schedar", "gamma_cas"},
    {"gamma_cas", "delta_cas"}, {"delta_cas", "eps_cas"},
    -- 天鹅座 · 北十字
    {"deneb", "sadr"}, {"sadr", "albireo"}, {"sadr", "gienah"},
    {"sadr", "delta_cyg"},
    -- 天琴座
    {"vega", "sheliak"}, {"sheliak", "sulafat"}, {"sulafat", "vega"},
    -- 天鹰座
    {"altair", "tarazed"}, {"altair", "alshain"},
    -- 天蝎座
    {"dschubba", "graffias"}, {"dschubba", "alniyat"},
    {"alniyat", "antares"}, {"antares", "eps_sco"},
    {"eps_sco", "sargas"}, {"sargas", "shaula"}, {"shaula", "lesath"},
    -- 狮子座
    {"regulus", "del_leo"}, {"del_leo", "algieba"},
    {"algieba", "denebola"}, {"theta_leo", "denebola"},
    {"theta_leo", "regulus"},
    -- 金牛座
    {"aldebaran", "elnath"}, {"aldebaran", "zeta_tau"}, {"zeta_tau", "elnath"},
    -- 双子座
    {"castor", "pollux"}, {"pollux", "alhena"},
    {"alhena", "mebsuta"}, {"mebsuta", "tejat"}, {"tejat", "elnath"},
    -- 南十字
    {"acrux", "gacrux"}, {"mimosa", "deltacru"},
    -- 大犬座
    {"sirius", "mirzam"}, {"mirzam", "wezen"},
    {"wezen", "adhara"}, {"adhara", "aludra"}, {"wezen", "aludra"},
    -- 牧夫座
    {"arcturus", "izar"}, {"izar", "seginus"},
    {"arcturus", "muphrid"}, {"arcturus", "nekkar"},
    -- 飞马座 · 秋季四边形
    {"markab", "scheat"}, {"scheat", "alpheratz"},
    {"alpheratz", "algenib"}, {"algenib", "markab"},
    -- 仙女座
    {"alpheratz", "mirach"}, {"mirach", "almak"},
    -- 英仙座
    {"mirfak", "gamma_per"}, {"gamma_per", "delta_per"},
    {"delta_per", "eps_per"}, {"mirfak", "algol"},
    -- 御夫座五边形
    {"capella", "menkalin"}, {"menkalin", "almaaz"},
    {"almaaz", "hassaleh"}, {"hassaleh", "elnath"}, {"elnath", "capella"},
    -- 人马座 · 茶壶
    {"alnasl", "kaus_aust"}, {"kaus_aust", "kaus_med"},
    {"kaus_med", "kaus_bor"}, {"kaus_bor", "alnasl"},
    {"kaus_med", "ascella"}, {"ascella", "nunki"}, {"nunki", "albaldah"},
    -- 小熊座
    {"polaris", "yildun"}, {"yildun", "kochab"},
    {"kochab", "pherkad"}, {"pherkad", "gamma_umi"},
    -- 天龙座
    {"eltanin", "rastaban"}, {"rastaban", "grumium"},
    {"grumium", "edasich"}, {"edasich", "thuban"},
    -- 室女座
    {"spica", "porrima"}, {"porrima", "vindemi"},
    {"vindemi", "zavijava"},
    -- 仙王座
    {"alderamin", "alfirk"}, {"alfirk", "errai"},
    -- 宝瓶座
    {"sadalsuud", "sadalmelik"},
    -- 天秤座
    {"zubenesch", "zubenelg"},
    -- 蛇夫座
    {"rasalhague", "cebalrai"}, {"cebalrai", "sabik"},
    {"rasalhague", "yed_prior"}, {"yed_prior", "sabik"},
    -- 武仙座
    {"rasalgethi", "korneph"},
    -- 小犬座
    {"procyon", "gomeisa"},
    -- 波江座
    {"achernar", "acamar"}, {"acamar", "zaurak"}, {"zaurak", "cursa"},
    -- 船底座
    {"canopus", "avior"}, {"avior", "aspidiske"}, {"aspidiske", "miaplac"},
    -- 半人马座
    {"rigil", "hadar"}, {"hadar", "menkent"},
    -- 乌鸦座
    {"gamma_crv", "delta_crv"}, {"delta_crv", "eps_crv"},
    -- 船帆座
    {"alsephina", "kappavel"}, {"kappavel", "muvel"},
}

-- ===== 深空天体（梅西耶 / NGC 精选）=====
-- id, 中文名, 类型, 赤经h, 赤纬°, 总星等, 视直径(角分), 简介
M.dso = {
    {"m45", "昴星团",     "疏散星团", 3.791, 24.12, 1.6, 110, "肉眼可见的七姐妹，双筒最佳目标"},
    {"m42", "猎户座大星云","发射星云", 5.588, -5.39, 4.0, 85,  "全天最壮观的恒星摇篮，拱心石正下方"},
    {"m31", "仙女座星系",  "旋涡星系", 0.712, 41.27, 3.4, 178, "本星系群最大成员，220万光年外的邻居"},
    {"m13", "武仙座球团",  "球状星团",16.695, 36.46, 5.8, 20,  "30万颗恒星组成的古老球团"},
    {"m8",  "礁湖星云",    "发射星云",18.063, -24.38, 6.0, 90, "人马座方向的氢云与暗尘带"},
    {"m7",  "托勒密星团",  "疏散星团",17.898, -34.79, 3.3, 80, "天蝎尾部的明亮星团，肉眼可辨"},
    {"m27", "哑铃星云",    "行星状星云",19.993, 22.72, 7.4, 8, "垂死恒星吹出的双瓣气壳"},
    {"m57", "环状星云",    "行星状星云",18.893, 33.03, 8.8, 1.4,"天琴座中的烟圈，高倍率见环"},
    {"m33", "三角座星系",  "旋涡星系", 1.564, 30.66, 5.7, 73,  "本星系群第三大，需暗夜低倍率"},
    {"m51", "涡状星系",    "旋涡星系",13.498, 47.20, 8.4, 11,  "第一个被辨认出旋臂的星系"},
    {"m81", "波德星系",    "旋涡星系", 9.926, 69.07, 6.9, 27,  "北天最亮旋涡星系之一"},
    {"m104", "草帽星系",   "旋涡星系",12.667, -11.62, 8.0, 9,  "侧向星系与显著尘埃带"},
    {"m44", "蜂巢星团",    "疏散星团", 8.673, 19.98, 3.1, 95,  "巨蟹座中心的鬼宿星团"},
    {"m17", "天鹅星云",    "发射星云",18.346, -16.18, 6.0, 11, "Omega 星云，人马座的红色发光带"},
}

-- ===== 银河带（近似大圆采样点，用于绘制朦胧光带）=====
-- ra(h), dec(°)
M.milkyway = {
    {0.00, 60.0}, {0.90, 62.0}, {1.80, 58.0}, {2.60, 50.0},
    {3.50, 43.0}, {4.50, 38.0}, {5.40, 25.0}, {5.80, 5.0},
    {6.30, -8.0}, {6.90, -20.0}, {7.80, -32.0}, {8.80, -44.0},
    {9.90, -56.0}, {11.00, -62.0}, {12.20, -62.0}, {13.30, -58.0},
    {14.40, -50.0}, {15.50, -40.0}, {16.60, -32.0}, {17.60, -26.0},
    {18.50, -20.0}, {19.00, -8.0}, {19.60, 5.0}, {20.10, 20.0},
    {20.70, 34.0}, {21.10, 46.0}, {21.80, 56.0}, {22.80, 60.0},
    {23.80, 61.0}, {24.00, 60.0},
}

-- ===== 星座中文名 =====
M.con_names = {
    UMa = "大熊座", Ori = "猎户座", Cas = "仙后座", Cyg = "天鹅座",
    Lyr = "天琴座", Aql = "天鹰座", Sco = "天蝎座", Leo = "狮子座",
    Tau = "金牛座", Gem = "双子座", Cru = "南十字", CMa = "大犬座",
    Boo = "牧夫座", Peg = "飞马座", And = "仙女座", Per = "英仙座",
    Aur = "御夫座", Sgr = "人马座", UMi = "小熊座", Dra = "天龙座",
    Vir = "室女座", Cep = "仙王座", Aqr = "宝瓶座", Lib = "天秤座",
    Oph = "蛇夫座", Her = "武仙座", CMi = "小犬座", Eri = "波江座",
    Car = "船底座", Cen = "半人马座", Crv = "乌鸦座", Vel = "船帆座",
    Ari = "白羊座", Cet = "鲸鱼座", PsA = "南鱼座", Pav = "孔雀座",
    TrA = "南三角", Gru = "天鹤座", Pup = "船尾座", Hya = "长蛇座",
    Col = "天鸽座", CrB = "北冕座", Ser = "巨蛇座", Del = "海豚座",
    Sge = "天箭座", Tri = "三角座",
}

-- 展开为结构体数组
local stars = {}
local byid = {}
for i = 1, #ROWS do
    local r = ROWS[i]
    local s = {
        id = r[1], cn = r[2], bayer = r[3], con = r[4],
        ra = r[5], dec = r[6], mag = r[7], bv = r[8],
        con_cn = M.con_names[r[4]] or r[4],
    }
    stars[i] = s
    byid[s.id] = s
end

M.stars_list = stars
M.byid = byid
M.count = #stars

function M.get(id)
    return byid[id]
end

-- 深空天体转结构体（统一 ra/dec/mag 字段，方便和星共用绘制逻辑）
function M.dso_list()
    local out = {}
    for i = 1, #M.dso do
        local d = M.dso[i]
        out[i] = {
            id = d[1], cn = d[2], kind = d[3], ra = d[4], dec = d[5],
            mag = d[6], size = d[7], desc = d[8], con_cn = "深空天体",
        }
    end
    return out
end

return M
