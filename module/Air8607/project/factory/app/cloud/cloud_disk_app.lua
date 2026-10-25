--[[
@module  cloud_disk_app
@summary 合宙网盘业务层（IoT 账号登录 → space_key → 空间文件列表 → 下载到最高优先级存储）
@version 1.7
@date    2026.09.18
@author  江访

=== 链路 ===

  1. 登录 IoT 账号：POST https://api.luatos.com/iot/appstore/login
     （RSA 公钥加密账号/密码，与 exapp.iot_login 同一套）
     成功返回的 value 中携带：
        value.nickname   string  用户昵称
        value.space_key  string  网盘空间 key（下称 A）—— 作为 app-key 明文里的**第二段**
     账号/密码/昵称由 exapp 的登录流程写入 iot_account / iot_password / iot_nickname；
     A 由 exapp.iot_login 与本模块共同落到 fskv("iot_space_key")，两者共用同一份登录态。

  2. 拉取网盘文件列表：POST https://api.luatos.com/iot/device_space/list_files
     Header  : app-key = Base64(RSA("<时间戳>,<第二段>,<设备ID>"))
               —— 与「应用市场 9.1.3 鉴权 Headers 规范」同构（factory_rec.make_auth_headers
                  与 exapp.iot_get_auth_headers(appid) 就是这套）。

     §服务端校验链（2026-09-18 用本工程 public.pem 直接探测服务端得到，非推测）

     明文必须是**恰好三段**（逗号分隔）。各校验点与返回：

       行58  访问拒绝（没有携带app-key）   ← 缺 app-key
       行61  app-key格式有误               ← 不是 base64 / 不是 RSA 密文
       行63  app-key格式有误               ← 能解密，但明文不是三段
       行71  时间戳不能为空                 ← 第一段空
       行73  参数错误（key）                ← **第二段非空白，但服务端库里查不到**
       行75  deviceId不能为空              ← 第三段空
       成功   第二段为**空白**时通过，但**必然返回空列表** —— 详见下方 §留空不可用

     §⚠️「第二段留空」**不是**可用路径（v1.7 更正 v1.6 的结论）

     v1.6 曾把「留空能返回 code=0」当成「服务端按 deviceId 定位到了空间」，据此做了静默降级。
     2026-09-18 用本工程 public.pem 再探一轮后推翻（--matrix 复现，见本模块 §九 说明）：

         第二段留空 + devid="860000000000000"（伪造 15 位） → code=0 + {'total':'0','records':[]}
         第二段留空 + devid="abc123"（伪造）               → code=0 + 同样空列表
         第二段留空 + devid="AA:BB:CC:DD:EE:FF"           → code=0 + 同样空列表
         第二段留空 + devid=""（空）                       → 行75 deviceId不能为空

     即：**留空时服务端不做任何空间定位**，对任意 devid 都回「空列表」这种"成功"。
     它只证明「格式链没问题、问题只在第二段的值」，**拿不到真数据**。
     → 所以留空回查自 v1.7 起**不再作为业务路径**：结果不发布给 UI，只写诊断日志。
     否则会把「凭证无效」伪装成「网盘是空的」，用户看到空列表还以为账号里没有文件。

     §同族旁证：/iot/device_space/list 是个"哑接口"（实测）

     它**完全不校验 app-key**（不带也返回 code=0），body 里的 space_key / deviceId /
     path / filter 等一律被忽略，永远返回空列表；唯一有反应的是分页字段：

         body {"size":1,"page":10} → 响应 current=10, size=1

     又一次印证「size=第几页、page=每页条数」的交叉命名。**取列表只能用 list_files。**

     由此得到几条反直觉的实测结论：
       · **ts 没有时间窗校验**：1 天前、2000 年、甚至 "0" 都能通过，只要非空。
         所以「设备未校时」不是本接口的失败原因（早期版本为此加的 NTP 等待已移除）。
       · **devid 只要求非空**：任意非空字符串都通过。
       · 额外 header（appid / space-key / spaceKey）**不能替代第二段去传 A**；
         第二段留空时加不加它们看不出差别，因为留空本来就返回空列表。

     所以线上若看到行73，含义非常明确：**A 的值服务端不认识**（段数、ts、devid 全都没问题）。
     后续只剩两条路：
       ① 核对 A 与登录响应里的 space_key 是否**逐字**一致 —— 本模块会把 A 的完整取值
          与服务端 trace 的行号一并打进日志（trace_line）；
       ② 确认该账号在平台上**是否真的已有网盘空间**：若空间记录是「首次上传/开通」时才建的，
          新账号第一次查询报行73 反而属于预期，去网页端网盘页上传一个文件即可。
     Body    : 不携带任何参数 → 查询该账号下全部文件
               {"filter":"茶性"}                    → 按文件名过滤
               {"filter":"茶性","size":1,"page":10} → 追加分页（见下方「分页参数」
                                                      §，服务端字段命名与常规相反）
     响应    : { code=0, value={ total, current, pages, size, records=[ {...} ] } }
               total   总记录数      current 当前页数     pages 总页数
               size    每页显示条数
               records[] = { size 文件字节数, name 文件名, time 上传时间, url 下载链接 }
               ⚠️ value 里所有数值字段都是**字符串**（"3" / "10" / "16958"）。
               ⚠️ records[].url 是 OSS 直链（如 appstoreoss.luatos.com），下载不再需要 app-key。

     §分页参数：平台文档给的示例是 {"filter":"茶性","size":1,"page":10}，注释为
       size = 查询第几页、page = 每页多少条 —— 与响应里 size=每页条数 的语义正好交叉。
       本模块按**文档注释**理解（size=页码、page=每页条数），因为不传参数即返回全部文件，
       默认路径不依赖分页；只有 UI 显式点「下一页」时才会带上这两个字段，
       并且每页都会把原始响应打印出来，语义若有出入一眼可见。

     本模块仍会先把**原始响应体**按块打印到 LuatTools 日志（cloud_disk / list_files RAW），
     再解析，便于服务端结构变动时对照排查。

  3. 下载：点击文件后按与 exapp 相同的策略选「最高优先级的**且空间足够**的存储」，
     落地目录固定为 <挂载点>cloud/，不存在则自动创建。

     §下载前先做空间预检（对齐 exapp）

     exapp 装应用前的判据是 free_kb >= app_size_kb + MIN_FREE_SPACE_KB（100KB 余量），
     本模块同构，只是把「app_size_kb」换成**这次真正还要写的字节**：

         free_kb >= (文件总长 - 本地已有半成品) + 块文件峰值(CHUNK_KB) + MIN_FREE_SPACE_KB

     三处都得算进来，少一处就会下到一半才失败：
       · 扣掉半成品 —— 续传时本地可能已有 800KB，按全量判会把「只差 100KB」的位置判成放不下；
       · 块文件峰值 —— 每块先落成 <目标>.part 再追加，峰值时目标 + 块同时在盘上；
       · 100KB 余量   —— 照 exapp 留的余量，FAT 簇开销不至于把文件系统撑满。

     所有已挂载位置都放不下时**直接拒绝并说明各处剩余空间**，不会下到一半才失败。
     fsstat 不报数的文件系统按「空间未知」信任处理（与 exapp 对最高优先级位置的策略一致）；
     ⚠️ NAND 上 fsstat 可能要 2~8 秒，所以只在点下载时调一次，列表/账号路径完全不碰。

     下载方式 = **按 Range 分块续传**（每块 CHUNK_KB）：
        a. 本地已有「小于目标大小」的半成品 → 直接从断点处继续，不重头下；
        b. 每块请求 Range: bytes=<pos>-<pos+want-1>，httpplus 以 dst 流式落到目标文件旁的
           <目标名>.part 块文件，再把块文件写到目标文件的 pos 处（4KB 缓冲，不分块进 RAM）；
        c. 任意一块超时/断流都**不丢已下字节** —— httpplus 在返回前会 close 写句柄，
           块文件里的内容就是从 pos 开始的**有效前缀**，照常落盘后从新断点重试；
        d. 100% 只在**校验通过后**才上报，传输过程中最多 99%。

     §落盘方式必须先自检（v1.2 新增，血的教训）

     2026-09-18 现场日志：
         I/cloud_disk 续传块 rc: 206 落盘: 130577 追加: 130577 进度: 261159 / 900520
         W/cloud_disk 本块无进展 rc: 206 已下载: 130582 / 900520 连续失败: 4

     「追加了 130577 字节」，目标文件却**纹丝不动**（大小正好还是追加前的 pos），
     而且每轮的三个数字完全一样 —— 说明 `io.open(path, "ab")` 在本机固件上
     **没有把写指针定位到文件末尾**：字节被写回了文件开头。第一块因为 pos == 0
     恰好正确，于是表现为「第一块能下、之后永远卡在同一个断点」。

     这也是「进度条只会动一次、第二次起全失败」的全部原因：
         · 进度条动的那一次 = 第一块（0 → 14%），pos 从 0 变成 130582；
         · 第二块起文件大小恒为 130582（== pos），`now > pos` 永远不成立 → 判「本块无进展」；
         · 百分比恒为 14%，而 report() 有「pct 没变化就不发布」的去重 →
           UI 连一次更新都收不到，看起来就是彻底僵住；
         · 连续 MAX_STALLED 块后报「网络异常」—— 连报错方向都被带偏了，根因在落盘不在网络。

     另外，旧实现的 append_file **不检查 df:write() 的返回值**，无条件累加 added，
     所以日志里的「追加: 130577」其实是「尝试写入量」而不是「真正落盘量」。
     这正是本次补上三重校验的原因：任何一处对不上都不算成功。

     所以本模块**不再假设 "ab" 的语义**，下载前先用 8 字节小文件实测四种落盘方式，
     只有「写完后大小与内容都对」的那一种才被采用：
         append_ab  io.open(path, "ab")               文档上的追加模式
         append_a   io.open(path, "a")                同上（有些固件只认不带 b 的写法）
         seek_set   io.open(path, "r+b") + seek(pos)  显式定位，语义最明确
         writefile  io.writeFile(path, data, "a+b")   文档明确「从文件末尾追加」
     四种都不可用时退化为**整文件单请求**下载（不续传，但内容一定干净）。

     每次落盘都做三重校验：写入量 + 文件大小 + 文件头是否被改写。
     其中「文件大小」若与预期不符，会再用**逐块读计数**复核一次 —— 因为
     io.fileSize 在某些文件系统上会返回旧值，而读出来的字节数不会骗人。

     取消：CLOUD_DISK_CANCEL_DOWNLOAD 会在**当前块结束后**停止（一块最多 CHUNK_TIMEOUT_S 秒），
     已下载部分**保留**，再次点击该文件即从中断处继续。

=== 消息协议 ===

订阅: CLOUD_DISK_OPEN                     → 打开网盘（读登录态，缺 A 时自动补取）
订阅: CLOUD_DISK_LOAD(filter, page, size) → 拉取列表；不带参数 = 查全部
订阅: CLOUD_DISK_DOWNLOAD(item)           → 下载指定文件（item 为 CLOUD_DISK_FILES 里的元素）
订阅: CLOUD_DISK_CANCEL_DOWNLOAD          → 取消进行中的下载（保留已下载部分）
订阅: IOT_LOGIN_RESULT                    → IoT 登录成功后补取 A（兼容设置页登录入口）
订阅: IOT_LOGOUT_RESULT                   → 登出后清空网盘登录态

发布: CLOUD_DISK_ACCOUNT(info) → 账号状态 { logged_in, account, nickname, storage_label }
发布: CLOUD_DISK_STATUS(msg)   → 状态文本（"正在获取文件列表..." 等），空串 = 空闲
发布: CLOUD_DISK_FILES(list, storage_label, meta) → 列表就绪
                               meta = { total, current, pages, size, page_size, filter, has_more }
发布: CLOUD_DISK_ERROR(msg)    → 错误提示
发布: CLOUD_DISK_PROGRESS(pct, text) → 下载进度（pct: 0~100，传输中最高 99）
发布: CLOUD_DISK_DONE(ok, msg, path, reason) → 下载结束
                               reason = "ok" | "cancel" | "error"

fskv 键: iot_space_key（A，与 exapp.iot_login 共写）
         iot_account / iot_password / iot_nickname（exapp 登录流程写，本模块只读）
         storage_priority（存储优先级，设置页写，本模块只读）
]]

local FSKV_SPACE_KEY   = "iot_space_key"
local FSKV_NICK        = "iot_nickname"

local IOT_AUTH_URL     = "https://api.luatos.com/iot/appstore/login"
local LIST_FILES_URL   = "https://api.luatos.com/iot/device_space/list_files"

local LIST_TIMEOUT     = 20000
local LOGIN_TIMEOUT    = 15000
local NET_WAIT_MS      = 15000
local NTP_WAIT_MS      = 3000      -- os.time() 无效时等 NTP 的上限（实测 ts 无时间窗，只需非空）

local MIN_FREE_SPACE_KB = 100     -- 下载后至少保留的空闲空间
local DOWNLOAD_DIR     = "cloud"  -- <挂载点>cloud/，不存在则创建
local MAX_PRINT        = 4000     -- 原始响应最多打印多少字符（超出截断，避免刷屏）
local LOG_CHUNK        = 200      -- 单行日志分块长度（LuatOS 日志单行有上限）

-- 下载（分块 Range 续传）
local CHUNK_KB         = 128      -- 单个 Range 请求的字节数：越小越抗断、取消越灵敏，越大开销越小
local CHUNK_TIMEOUT_S  = 30       -- 单块请求超时（⚠️ httpplus 的 timeout 单位是**秒**）
local PROBE_TIMEOUT_S  = 15       -- 探测总长（Range: bytes=0-0）的超时
local MAX_STALLED      = 6        -- 连续多少块毫无进展即判定网络不可用
local PLAIN_TIMEOUT_MS = 120000   -- 降级路径（无 httpplus）整文件下载超时（http.request 单位是**毫秒**）
local CANCEL_MSG       = "已取消下载"

-- 落盘方式候选（下载前自检，按顺序试；详见模块头部 §落盘方式必须先自检）
local SINK_METHODS     = { "append_ab", "append_a", "seek_set", "writefile" }
local SINK_PROBE       = ".cd_sink_probe"   -- 自检用的临时文件名（落在目标目录下）

-- 与 exapp.lua 的 STORAGE_DEFS 保持一致（同一套 type_key → 挂载点）
local STORAGE_DEFS = {
    sd_tf        = { mount_point = "/sd/",           label = "外挂TF卡" },
    little_flash = { mount_point = "/little_flash/", label = "外挂NAND Flash" },
    nand_flash   = { mount_point = "/little_flash/", label = "外挂NAND Flash" },
    internal     = { mount_point = "/",              label = "内置文件系统" },
}

local DEFAULT_PRIORITY = { "sd_tf", "little_flash", "nand_flash", "internal" }

-- ==================== 依赖 ====================

-- httpplus 用于分块续传（每次新建连接，断线恢复后不受内部状态影响）
local httpplus = nil
do
    local ok, mod = pcall(require, "httpplus")
    if ok then httpplus = mod end
    if not httpplus then log.warn("cloud_disk", "httpplus 不可用，下载将退化为整文件下载（不支持续传）") end
end

-- ==================== 状态 ====================

local rsa_ok = false        -- rsa 核心库是否可用（缺失时不能调用，会崩 VM）
local space_key = nil
local downloading = false
local cancel_flag = false   -- 下载取消标志（由 CLOUD_DISK_CANCEL_DOWNLOAD 置位）
local sink_cache = {}       -- 目标目录 → 自检选出的落盘方式（false = 四种都不可用）

-- ==================== 小工具 ====================

--[[按块打印长文本

LuatOS 的 log 单行有长度上限，直接 log.info 一整段 JSON 会被截断，
用户就看不到真实的响应结构了。按 LOG_CHUNK 切段并带上序号打印。]]
local function log_chunks(tag, text)
    if type(text) ~= "string" then text = tostring(text or "") end
    local shown, cut = text, false
    if #text > MAX_PRINT then
        shown, cut = text:sub(1, MAX_PRINT), true
    end
    local n = math.ceil(#shown / LOG_CHUNK)
    log.info("cloud_disk", tag, "len=" .. #text, "chunks=" .. n, cut and "TRUNCATED" or "")
    for i = 1, n do
        log.info("cloud_disk", string.format("%s[%d/%d]", tag, i, n),
            shown:sub((i - 1) * LOG_CHUNK + 1, i * LOG_CHUNK))
    end
end

local function mask(s)
    if type(s) ~= "string" or s == "" then return tostring(s or "") end
    if #s <= 8 then return s end
    return s:sub(1, 4) .. "..." .. s:sub(-4)
end

local function human_size(n)
    if not n or n <= 0 then return "" end
    if n < 1024 then return n .. " B" end
    if n < 1024 * 1024 then return string.format("%.1f KB", n / 1024) end
    return string.format("%.1f MB", n / 1024 / 1024)
end

-- 服务端字段可能是字符串形式的数字，统一转成 number（失败返回 nil）
local function to_num(v)
    if v == nil then return nil end
    return tonumber(tostring(v))
end

--[[设备唯一标识：与 exapp.iot_gen_device_uid / factory_rec.make_device_id 同规则

app-key 明文的第三段（设备ID）。各取一个字段即可，任一不可用时回退，绝不向上抛错。]]
local device_uid_cache = nil
local function device_uid()
    if device_uid_cache then return device_uid_cache end
    local ok, model = pcall(rtos.bsp)
    model = ok and tostring(model) or ""
    local function pick(fn)
        local o, v = pcall(fn)
        if o and v ~= nil and v ~= "" then return tostring(v) end
        return nil
    end
    local id
    if model:find("Air1601") or model:find("Air1602") or model:find("PC") then
        id = pick(mcu.unique_id)
    elseif model:find("Air8101") or model:find("Air6205") then
        id = pick(wlan.getMac)
    elseif model:find("Air780E") or model:find("Air8000") then
        id = pick(mobile.imei)
    else
        id = pick(mcu.unique_id)
    end
    device_uid_cache = id or "unknown"
    return device_uid_cache
end

--[[RSA + Base64：登录（加密账号/密码）与网盘鉴权（app-key 明文）都用这一套。

⚠️ 本工程 /luadb/public.pem 是 **1024 位**密钥（PEM 首段 "MIGf" 对应 128 字节模数），
PKCS#1 v1.5 填充下**明文上限 117 字节**（128 - 11）。超长时 rsa.encrypt 返回 nil，
若不在调用前自查，只会含糊成「RSA 加密失败」，看不出是长度问题。]]
local RSA_PLAIN_MAX = 117

local function rsa_encrypt_b64(plain)
    if not rsa_ok then return nil, "固件缺少 rsa 核心库" end
    local pub = io.readFile("/luadb/public.pem")
    if not pub then return nil, "缺少公钥 /luadb/public.pem" end
    if #plain > RSA_PLAIN_MAX then
        return nil, "RSA 明文超长(" .. #plain .. ">" .. RSA_PLAIN_MAX .. ")"
    end
    local ok, cipher = pcall(rsa.encrypt, pub, plain)
    if not ok or not cipher or cipher == "" then
        return nil, "RSA 加密失败(明文 " .. #plain .. " 字节)"
    end
    local b64 = string.toBase64(cipher)
    if not b64 or b64 == "" then return nil, "Base64 编码失败" end
    return b64
end

-- ==================== space_key（A）读写 ====================

local function get_space_key()
    if space_key and space_key ~= "" then return space_key end
    local ok, v = pcall(fskv.get, FSKV_SPACE_KEY)
    if ok and type(v) == "string" and v ~= "" then
        space_key = v
        return space_key
    end
    return nil
end

local function save_space_key(v, nickname)
    space_key = v
    pcall(fskv.set, FSKV_SPACE_KEY, v)
    if nickname and nickname ~= "" then pcall(fskv.set, FSKV_NICK, nickname) end
end

local function clear_space_key()
    space_key = nil
    -- 与 exapp.iot_clear_state 用同一种清法（del 而不是 set("")），语义一致且真正释放键位
    pcall(fskv.del, FSKV_SPACE_KEY)
end

-- ==================== 存储选择（与 exapp 同策略） ====================

local function load_priority()
    local ok, raw = pcall(fskv.get, "storage_priority")
    if ok and type(raw) == "string" and raw ~= "" then
        local okd, parsed = pcall(json.decode, raw)
        if okd and type(parsed) == "table" and #parsed > 0 then
            local has = false
            for _, tk in ipairs(parsed) do
                if STORAGE_DEFS[tk] then has = true; break end
            end
            if has then return parsed end
        end
        log.warn("cloud_disk", "storage_priority 配置无效，用默认顺序")
    end
    return DEFAULT_PRIORITY
end

--[[取挂载点的可用空间（KB）

io.fsstat 是多返回值（success, total_blocks, used_blocks, block_size, fs_type）。
⚠️ NAND 的 fsstat 可能要 2~8 秒（见 readme「存储页面卡顿」），所以只在**下载前**调，
列表/账号状态这类高频路径不碰它（storage_label 传 need_kb = nil 就完全不会调用）。
返回 nil = 该文件系统不报空间，调用方按「未知」处理。]]
local function free_kb(mount_point)
    if not mount_point then return nil end
    local r, success, total_blocks, used_blocks, block_size = pcall(io.fsstat, mount_point)
    if r and success and total_blocks and block_size and total_blocks > 0 then
        -- 先除再乘，避免 total_blocks * block_size 溢出 32 位整数
        local total_kb = total_blocks * (block_size / 1024)
        local used_kb = (used_blocks or 0) * (block_size / 1024)
        return total_kb - used_kb
    end
    return nil
end

-- cur_size 定义在下方「落盘」一节，这里先声明出来：空间预检要用它扣掉本地已有的半成品
local cur_size

--[[挑选最高优先级的可用存储

与 exapp 同语义：按用户在「存储优先级」页配置的顺序，取第一个「已挂载」的位置；
并**照 exapp 一样在下载前做空间预检**（exapp 的判据是 free_kb >= app_size_kb + MIN_FREE_SPACE_KB），
本模块的门槛是：

    free_kb >= 还需下载的净字节 + 块文件峰值(CHUNK_KB) + MIN_FREE_SPACE_KB

  · 「还需下载的净字节」= 文件总长 - 该位置上已有的半成品（给了 fname 才扣）。
    续传时本地可能已经有 800KB，若仍按文件全量判定，会把「其实只差 100KB」的位置
    误判成放不下 —— 断点续传越到后面越容易撞上这个问题。
  · 「块文件峰值」：每块先落成 <目标>.part 再追加进目标文件，峰值时两者同时在盘上。
  · MIN_FREE_SPACE_KB = 100KB：照 exapp 留的余量，FAT 簇开销不至于把文件系统撑满。

空间不可知的文件系统（fsstat 不报数）按可用处理，避免把功能卡死
（与 exapp「对最高优先级位置的空间未知选择信任」一致）。

@param need_kb number|nil 整个文件大小的 KB；nil = 只看挂载、不做空间判断（给文案用）
@param fname   string|nil 文件名；给出时按该位置上已有的半成品扣减需求
@return mount_point|nil, label, type_key, free_kb|nil, detail
        mount_point = nil 表示所有已挂载位置都放不下（detail 是各处空间说明，用于报错）
]]
local function pick_storage(need_kb, fname)
    local priority = load_priority()
    local detail = {}
    for _, tk in ipairs(priority) do
        local def = STORAGE_DEFS[tk]
        if def and io.dexist(def.mount_point) then
            if not need_kb then
                return def.mount_point, def.label, tk
            end
            local fk = free_kb(def.mount_point)
            if fk == nil then
                log.warn("cloud_disk", "空间未知，按可用处理:", def.label)
                return def.mount_point, def.label, tk, nil
            end

            -- 该位置上已有的半成品（断点续传）不再重复预留
            local have_kb = 0
            if fname then
                have_kb = math.ceil(cur_size(def.mount_point .. DOWNLOAD_DIR .. "/" .. fname) / 1024)
            end
            local remain_kb = need_kb - have_kb
            if remain_kb < 0 then remain_kb = 0 end
            local needed_kb = remain_kb + CHUNK_KB + MIN_FREE_SPACE_KB

            detail[#detail + 1] = string.format("%s 剩 %s / 需 %s",
                def.label, human_size(fk * 1024), human_size(needed_kb * 1024))
            if fk >= needed_kb then
                if have_kb > 0 then
                    log.info("cloud_disk", "空间预检:", def.label, "已有半成品", have_kb .. "KB",
                        "还需", remain_kb .. "KB", "可用", math.floor(fk) .. "KB",
                        "门槛", needed_kb .. "KB")
                end
                return def.mount_point, def.label, tk, fk
            end
            log.warn("cloud_disk", "空间不足跳过:", def.label, "可用KB:", math.floor(fk),
                "需要KB:", needed_kb, "(还需", remain_kb, "+ 块峰值", CHUNK_KB,
                "+ 保留", MIN_FREE_SPACE_KB .. ")")
        end
    end
    return nil, nil, nil, nil, (#detail > 0) and table.concat(detail, "；") or "无已挂载存储"
end

-- 供 UI 展示的「当前下载目标」文案（取最高优先级的可用位置 + 固定落地目录）
local function storage_label()
    local mp, label = pick_storage(nil)
    if not mp then return "无可用存储" end
    return label .. " (" .. mp .. DOWNLOAD_DIR .. "/)"
end

-- ==================== 账号状态 ====================

local function account_info()
    local ok_a, acct = pcall(fskv.get, "iot_account")
    local ok_n, nick = pcall(fskv.get, FSKV_NICK)
    local has_sk = (get_space_key() ~= nil)
    return {
        logged_in     = has_sk,
        has_space_key = has_sk,
        account       = (ok_a and type(acct) == "string") and acct or "",
        nickname      = (ok_n and type(nick) == "string") and nick or "",
        storage_label = storage_label(),
    }
end

local function publish_account()
    sys.publish("CLOUD_DISK_ACCOUNT", account_info())
end

-- ==================== 网络等待 ====================

-- 需要时等 IP_READY；返回 true=已就绪
local function ensure_network()
    if socket.localIP() then return true end
    local _, ip = sys.waitUntil("IP_READY", NET_WAIT_MS)
    return ip ~= nil
end

-- ==================== app-key ====================

--[[时间戳：app-key 明文的第一段

⚠️ 2026-09-18 服务端实测：**ts 没有时间窗校验** —— 1 天前、2000 年、甚至 "0"
   统统能通过，唯一要求是「不能为空」（空 → 行71「时间戳不能为空」）。
   所以这里**不等 NTP**（早先按「未校时会失败」的猜测加了 8 秒等待，实测后移除）。

只在 os.time() 明显无效（nil / ≤0）时才短暂等一次校时，服务端要的只是「非空」。]]
local function ensure_time_synced()
    local t = tonumber(os.time())
    if t and t > 0 then return tostring(t) end
    log.warn("cloud_disk", "os.time() 无效(" .. tostring(os.time()) .. ")，短暂等待校时...")
    sys.waitUntil("NTP_UPDATE", NTP_WAIT_MS)
    t = tonumber(os.time())
    if not t or t <= 0 then t = 1 end     -- 服务端只要求非空，兜一个值保证能发出去
    log.warn("cloud_disk", "使用时间戳:", tostring(t))
    return tostring(t)
end

--[[生成网盘接口的 app-key 请求头

    app-key = Base64(RSA("<时间戳>,<第二段>,<设备ID>"))

第二段传 nil → 填 A（space_key）；传 "" → 留空（此时服务端按 deviceId 定位空间）。

规则与 factory_rec.make_auth_headers / exapp.iot_get_auth_headers(appid) 同构。
⚠️ 早期版本曾照 exapp 那样额外带一个 appid header —— 实测服务端**完全不读**它，已去掉。

诊断三件套（定位线上 54 用）：
  · 三段原文 + 明文总长 / 上限（1024 位公钥 → 117 字节，A 过长会直接超限）
  · A 的**完整取值**（当前阶段必须能看到，方便与登录响应逐字比对）
  · 与 exapp.iot_get_auth_headers(第二段) 的结果对照：一致即证明本模块复刻无误]]
local function build_appkey_headers(second)
    local sk = get_space_key()
    if not sk then return nil, "尚未获取网盘空间，请先登录 IoT 账号" end

    local ts = ensure_time_synced()
    local devid = tostring(device_uid())
    local seg2 = second
    if seg2 == nil then seg2 = sk end
    local plain = ts .. "," .. seg2 .. "," .. devid

    log.info("cloud_disk", "app-key 三段: ts=[" .. ts .. "] 第二段=[" .. seg2 ..
        "] devid=[" .. devid .. "] 明文长度=" .. #plain .. "/" .. RSA_PLAIN_MAX)
    log.info("cloud_disk", "A(space_key) 实际取值=[" .. sk .. "] 长度=" .. #sk)

    if #plain > RSA_PLAIN_MAX then
        return nil, "app-key 明文超长(" .. #plain .. ">" .. RSA_PLAIN_MAX ..
            ")，A 长 " .. #sk .. " 字节，请确认 space_key 形态"
    end

    local b64, err = rsa_encrypt_b64(plain)
    if not b64 then return nil, err end
    log.info("cloud_disk", "app-key base64 长度:", tostring(#b64))

    local g = rawget(_G, "exapp")
    if g and type(g.iot_get_auth_headers) == "function" then
        local okx, hdr = pcall(g.iot_get_auth_headers, seg2)
        local ref = (okx and type(hdr) == "table") and hdr["app-key"] or nil
        log.info("cloud_disk", "app-key 对照 exapp: 一致=" .. tostring(ref == b64) ..
            (ref and (" 本模块=" .. #b64 .. " exapp=" .. #ref) or " (exapp 无值)"))
    end

    return { ["app-key"] = b64 }
end

-- ==================== 登录（取 A） ====================

--[[向 /appstore/login 请求一次，把 space_key 取回来

账号/密码与 exapp.iot_login 同一套加解密；这里不写 iot_account/iot_password
（那是 exapp 登录流程的职责），只落 A 与昵称。]]
local function fetch_space_key(account, password)
    if not ensure_network() then return false, "网络未就绪" end
    local u, e1 = rsa_encrypt_b64(account)
    if not u then return false, e1 end
    local p, e2 = rsa_encrypt_b64(password)
    if not p then return false, e2 end

    local body = json.encode({ user = u, password = p })
    log.info("cloud_disk", "login 请求 账号:", mask(account))
    local code, _, rb = http.request("POST", IOT_AUTH_URL,
        { ["Content-Type"] = "application/json" }, body, { timeout = LOGIN_TIMEOUT }).wait()
    if code ~= 200 then
        log.warn("cloud_disk", "login HTTP 失败:", tostring(code))
        return false, "服务器连接失败(" .. tostring(code) .. ")"
    end
    log_chunks("login RAW", rb)
    local ok, resp = pcall(json.decode, rb)
    if not ok or type(resp) ~= "table" then return false, "响应解析失败" end
    if to_num(resp.code) ~= 0 or type(resp.value) ~= "table" then
        return false, tostring(resp.value or "登录失败")
    end
    local sk = resp.value.space_key
    if type(sk) ~= "string" or sk == "" then
        log.warn("cloud_disk", "登录成功但未返回 space_key")
        return false, "该账号没有网盘空间（无 space_key）"
    end
    save_space_key(sk, resp.value.nickname)
    log.info("cloud_disk", "space_key 获取成功:", mask(sk),
        "昵称:", tostring(resp.value.nickname or ""))
    return true
end

--[[确保 A 可用：内存 → fskv → 用已保存的账号密码现取一次]]
local function ensure_space_key()
    if get_space_key() then return true end
    local ok_a, acct = pcall(fskv.get, "iot_account")
    local ok_p, pwd  = pcall(fskv.get, "iot_password")
    if not (ok_a and ok_p and type(acct) == "string" and acct ~= ""
            and type(pwd) == "string" and pwd ~= "") then
        return false, "请先登录 IoT 账号"
    end
    sys.publish("CLOUD_DISK_STATUS", "正在获取网盘空间凭证...")
    return fetch_space_key(acct, pwd)
end

-- ==================== 列表解析 ====================

local function sanitize_name(name)
    if type(name) ~= "string" or name == "" then return nil end
    name = name:gsub("\\", "/")
    name = name:match("([^/]+)$") or name
    -- AirUI/文件系统对控制字符与路径分隔符敏感，统一替换为下划线
    name = name:gsub('[%c<>:"|?*]', "_")
    if name == "" or name == "." or name == ".." then return nil end
    if #name > 96 then
        local ext = name:match("(%.[%w]+)$") or ""
        name = name:sub(1, 96 - #ext) .. ext
    end
    return name
end

local function normalize_url(u)
    if type(u) ~= "string" or u == "" then return nil end
    if u:find("^https?://") then return u end
    if u:sub(1, 2) == "//" then return "https:" .. u end
    return "https://api.luatos.com" .. (u:sub(1, 1) == "/" and "" or "/") .. u
end

--[[取第一个「非 nil 且非空字符串」的候选值

服务端这批数值字段都是字符串，空串在 Lua 里是**真值** —— 直接写
`r.url or r.download_url` 时，若 r.url 恰好是 ""，`or` 会把它当成有效值选出来，
后面的兜底字段永远轮不到（表现为「有文件但 url 解析成 nil，列表空白」）。
所以先过滤空串再回退。]]
local function first_str(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and v ~= "" then return v end
    end
    return nil
end

--[[把服务端 value.records 归一化成 UI 用的数组

服务端现已定稿（2026-09-18 实测）：
    records = { { size="16958", name="星河64.ico", time="2026-09-18 14:09:41", url="https://..." }, ... }
仍保留对「value 直接是数组」「value 里换名容器」的兜底，服务端结构变动时不至于白屏。]]
local function normalize_records(value)
    if type(value) ~= "table" then return {} end
    local recs = value.records
    if type(recs) ~= "table" then
        for _, k in ipairs({ "list", "files", "items", "rows", "data", "result" }) do
            if type(value[k]) == "table" then recs = value[k]; break end
        end
    end
    if type(recs) ~= "table" and type(value[1]) == "table" then recs = value end
    if type(recs) ~= "table" then return {} end

    local out, seen = {}, {}
    for i, r in ipairs(recs) do
        if type(r) == "table" then
            local url = normalize_url(first_str(r.url, r.download_url, r.file_url, r.fileUrl))
            local nm  = sanitize_name(first_str(r.name, r.file_name, r.filename, r.fileName))
            -- 服务端没给文件名时，从直链末段兜底推导
            if (not nm) and url then
                nm = sanitize_name(url:match("([^/?]+)[^/]*$"))
            end
            if nm and url and not seen[url] then
                seen[url] = true
                out[#out + 1] = {
                    name  = nm,
                    url   = url,
                    size  = to_num(first_str(r.size, r.file_size, r.fileSize)),
                    mtime = first_str(r.time, r.mtime, r.upload_time) or "",
                    index = i,
                }
            end
        end
    end
    return out
end

--[[生成 UI 用的 meta（分页信息 + 是否有下一页）

服务端数值字段全是字符串，统一 to_num；缺失时按已解析条数兜底。]]
local function build_meta(value, list, filter, page_size)
    local meta = {
        total     = to_num(value and value.total) or #list,
        current   = to_num(value and value.current) or 1,
        pages     = to_num(value and value.pages) or 1,
        size      = to_num(value and value.size) or page_size,
        page_size = page_size,
        filter    = filter,
    }
    meta.has_more = (meta.pages > 1) and (meta.current < meta.pages) or false
    return meta
end

-- 按上传时间倒序（"YYYY-MM-DD HH:MM:SS" 字符串可直接比大小）；时间相同再按名字
local function sort_by_time_desc(list)
    table.sort(list, function(a, b)
        local ta, tb = a.mtime or "", b.mtime or ""
        if ta == tb then return a.name < b.name end
        return ta > tb
    end)
end

--[[从服务端 trace 里抽出失败点：DeviceSpaceController.java/deviceListFiles(73) → "deviceListFiles(73)"

行号是排障时最有价值的信息：本轮「参数错误（key）」正是靠它（73 > 61）才区分开
「格式不对」与「格式对但 key 不认识」。单独打一行，免得淹没在一整段堆栈里。]]
local function trace_line(trc)
    if type(trc) ~= "string" then return "?" end
    local _, method, lineno = trc:match("([%w_]+)%.java/(%a+)%((%d+)%)")
    if not lineno then return "-" end
    return method .. "(" .. lineno .. ")"
end

-- ==================== 拉取文件列表 ====================

--[[拉取网盘文件列表并发布 CLOUD_DISK_FILES

@table[opt] opts
  filter    string|nil  文件名过滤（服务端 filter 参数）
  page      number|nil  页码（配合 page_size 使用，见模块头部 §分页参数）
  page_size number|nil  每页条数
  append    boolean     把结果追加到 UI 已有列表（「下一页」用）
  keep      table|nil   追加时的基准列表
]]
local function fetch_list(opts)
    opts = opts or {}
    local filter = opts.filter
    if filter == "" then filter = nil end

    -- 注意：ensure_space_key 内部可能真的发起一次登录请求，返回值必须一次取全，
    -- 否则为了拼错误文案再调一次就会白发一个请求。
    local ok_sk, sk_err = ensure_space_key()
    if not ok_sk then
        sys.publish("CLOUD_DISK_STATUS", "")
        sys.publish("CLOUD_DISK_ERROR", sk_err or "请先登录 IoT 账号")
        publish_account()
        return
    end

    if not ensure_network() then
        sys.publish("CLOUD_DISK_STATUS", "")
        sys.publish("CLOUD_DISK_ERROR", "网络未就绪")
        return
    end

    -- 不携带任何参数 = 查询该账号下全部文件
    local payload = {}
    if filter then payload.filter = filter end
    if opts.page and opts.page_size then
        payload.size = opts.page          -- 平台文档：size = 查询第几页
        payload.page = opts.page_size     -- 平台文档：page = 每页显示多少条
    end
    local body = json.encode(payload)

    --[[发一次请求并解码

    @param second nil = 第二段填 A；"" = 第二段留空
    @return http_code|nil, resp_table|nil, raw_body|nil, err]] 
    local function post_once(second)
        local headers, herr = build_appkey_headers(second)
        if not headers then return nil, nil, nil, herr end
        headers["Content-Type"] = "application/json"
        local c, _, r = http.request("POST", LIST_FILES_URL, headers, body,
            { timeout = LIST_TIMEOUT }).wait()
        log.info("cloud_disk", "list_files HTTP:", tostring(c))
        if c ~= 200 then return c, nil, r end
        -- ⚠️ 原始响应整体按块打印，便于确认服务端真实结构与错误阶段
        log_chunks("list_files RAW", r)
        local okd, resp = pcall(json.decode, r)
        if not okd or type(resp) ~= "table" then return c, nil, r end
        return c, resp, r
    end

    sys.publish("CLOUD_DISK_STATUS", "正在获取文件列表...")
    log.info("cloud_disk", "list_files REQ", LIST_FILES_URL, "body:", body)

    local code, resp, rb, herr = post_once(nil)
    if not code then
        sys.publish("CLOUD_DISK_STATUS", "")
        sys.publish("CLOUD_DISK_ERROR", herr or "鉴权失败")
        return
    end
    if code ~= 200 then
        sys.publish("CLOUD_DISK_STATUS", "")
        sys.publish("CLOUD_DISK_ERROR", "服务器连接失败(" .. tostring(code) .. ")")
        return
    end
    if not resp then
        sys.publish("CLOUD_DISK_STATUS", "")
        sys.publish("CLOUD_DISK_ERROR", "响应解析失败")
        return
    end

    --[[A 被服务端拒绝时（行73「参数错误（key）」）做一次**诊断性**回查

    ⚠️ v1.7 更正：留空**不是**可用路径 —— 实测对任意（含伪造）devid 都返回
    code=0 + 空列表，说明留空时服务端根本没做空间定位。
    所以这里的结果**只进日志、绝不发布给 UI**：否则会把「凭证无效」伪装成
    「网盘是空的」，用户看到空列表还以为账号里没文件。]]
    if to_num(resp.code) ~= 0 and tostring(resp.value or ""):find("参数错误", 1, true) then
        log.warn("cloud_disk", "A 被服务端拒绝(" .. tostring(resp.value) ..
            ") 服务端行号=" .. trace_line(resp.trace) .. "，执行诊断性留空回查")
        local c2, resp2 = post_once("")
        if c2 == 200 and resp2 and to_num(resp2.code) == 0 then
            local v2 = type(resp2.value) == "table" and resp2.value or {}
            log.warn("cloud_disk", "留空回查 code=0 但 total=" .. tostring(v2.total or 0) ..
                " → 留空只能证明「格式链正常」，**不代表定位到了空间**，A 仍未被接受")
        else
            log.warn("cloud_disk", "留空回查仍未通过 http=" .. tostring(c2) ..
                " value=" .. (resp2 and tostring(resp2.value) or "(无响应)"))
        end
    end

    if to_num(resp.code) ~= 0 then
        local v = tostring(resp.value or ("错误码 " .. tostring(resp.code)))
        log.warn("cloud_disk", "list_files code=", tostring(resp.code), "value=", v,
            "服务端行号=", trace_line(resp.trace))
        -- 服务端原文案对用户没有可操作性，这里翻成人话（原文已在上一行入日志）
        if v:find("参数错误", 1, true) then
            v = "网盘空间凭证未被识别：请确认该账号已在平台开通网盘空间，" ..
                "并在设置中退出后重新登录 IoT 账号"
        elseif v:find("格式有误", 1, true) or v:find("没有携带", 1, true) then
            v = "鉴权失败：请确认固件已包含 /luadb/public.pem"
        end
        sys.publish("CLOUD_DISK_STATUS", "")
        sys.publish("CLOUD_DISK_ERROR", v)
        return
    end

    local value = type(resp.value) == "table" and resp.value or {}
    local page = normalize_records(value)
    local meta = build_meta(value, page, filter, opts.page_size)

    log.info("cloud_disk", "list_files 本页:", #page, "total:", meta.total,
        "current/pages:", meta.current .. "/" .. meta.pages, "size:", meta.size)
    if #page > 0 then
        log.info("cloud_disk", "第 1 条:", json.encode({
            name = page[1].name, size = page[1].size,
            time = page[1].mtime, url = page[1].url,
        }))
    else
        log_chunks("list_files value", json.encode(value))
    end

    -- 第一页（非追加）按上传时间倒序；追加时保持已有顺序，把新页接在后面
    local files
    if opts.append and type(opts.keep) == "table" and #opts.keep > 0 then
        files = opts.keep
        local have = {}
        for _, it in ipairs(files) do have[it.url] = true end
        for _, it in ipairs(page) do
            if not have[it.url] then have[it.url] = true; files[#files + 1] = it end
        end
    else
        files = page
        sort_by_time_desc(files)
    end

    --[[发布顺序：先 FILES 再 STATUS 清空。

    UI 收到 FILES 时会把 busy 置为 false 并重建列表，此时列表里已经是新数据；
    若反过来先发 STATUS ""，UI 会先按「旧列表 + busy=false」重建一帧（短瞬间的空列表），
    再被 FILES 重建一次 —— 白白多刷一帧，且用户可能看到闪烁。]]
    sys.publish("CLOUD_DISK_FILES", files, storage_label(), meta)
    sys.publish("CLOUD_DISK_STATUS", "")
end

-- ==================== 下载（分块 Range + 断点续传） ====================

local function ensure_dir(dir)
    if io.dexist(dir) then return true end
    local ok = io.mkdir(dir)
    if not ok then log.warn("cloud_disk", "mkdir 失败:", dir) end
    return ok
end

-- 赋值给开头声明过的 local（pick_storage 的空间预检要用它）
cur_size = function(path)
    if not io.exists(path) then return 0 end
    return io.fileSize(path) or 0
end

-- 读文件开头 n 字节：用来识别「本该追加、却写到文件开头」这种错位
local function head_bytes(path, n)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read(n or 16)
    f:close()
    return s or ""
end

--[[逐块读完统计字节数

最慢（要整读一遍），但完全不依赖 io.fileSize / seek 的实现细节，
所以只在「探针说没进展」这种要判生死的时刻用。]]
local function count_size(path)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local n = 0
    while true do
        local buf = f:read(4096)
        if not buf or #buf == 0 then break end
        n = n + #buf
    end
    f:close()
    return n
end

-- 按指定方式把 data 写到 path 的 pos 处（只给自检用，数据很小）
local function write_bytes_via(method, path, pos, data)
    if method == "writefile" then
        local ok = io.writeFile(path, data, "a+b")
        if ok == nil or ok == false then return false, "writeFile 返回失败" end
        return true
    end
    local mode = "r+b"
    if method == "append_a" then mode = "a"
    elseif method == "append_ab" then mode = "ab" end
    local f, err = io.open(path, mode)
    if not f then return false, "open(" .. mode .. ") 失败:" .. tostring(err) end
    if method == "seek_set" then
        local sok = pcall(f.seek, f, pos, io.SEEK_SET)
        if not sok then f:close(); return false, "seek 不支持" end
    end
    local wok = f:write(data)
    f:close()
    if wok == nil or wok == false then return false, "write 返回失败" end
    return true
end

--[[落盘方式自检（每个目标目录只测一次）

用 8 字节基线 + 追加 2 字节实测：只有「大小变成 10 且内容正好是 AAAABBBBCC」的方式才算可用。
写成 "CC" 却读回 "CCAABBBB" 的，正是「追加写到了文件开头」—— 本机固件的 "ab" 就是这样，
必须淘汰（详见模块头部 §落盘方式必须先自检）。]]
local function sink_selftest(dir)
    local t = dir .. SINK_PROBE
    local base = "AAAABBBB"
    for _, m in ipairs(SINK_METHODS) do
        io.writeFile(t, base, "wb")
        local wok, why = write_bytes_via(m, t, #base, "CC")
        local got = io.readFile(t) or ""
        local sz  = io.fileSize(t) or -1
        if wok and got == (base .. "CC") and sz == (#base + 2) then
            os.remove(t)
            log.info("cloud_disk", "落盘方式自检通过:", m)
            return m
        end
        log.warn("cloud_disk", "落盘自检:", m, "不可用",
            (wok and ("读回 " .. sz .. " 字节")) or tostring(why))
    end
    os.remove(t)
    log.error("cloud_disk", "四种落盘方式都不可用，本次下载退化为整文件下载")
    return false
end

--[[把块文件 src 的内容落到目标文件 dst 的 pos 处，并验证是否真的落上了

「write 没报错」≠「写到了文件末尾」。现场日志（模块头部）就是这个坑：
io.open(dst,"ab") 之后字节被写回文件开头，文件大小不变，于是断点永远推不动。
所以这里做三重校验：写入量 + 文件大小 + 文件头是否被改写。

@return added 通过校验的落盘字节数（0 = 失败）
@return err   失败原因（added > 0 时为 nil）
]]
local function commit_chunk(src, dst, pos, method)
    local sf = io.open(src, "rb")
    if not sf then return 0, "打开块文件失败" end

    local head_before = (pos > 0) and head_bytes(dst, 16) or nil

    local df = nil
    if method ~= "writefile" then
        local mode = "r+b"
        if method == "append_a" then mode = "a"
        elseif method == "append_ab" then mode = "ab" end
        local derr
        df, derr = io.open(dst, mode)
        if not df and method == "seek_set" and pos == 0 then
            -- 目标文件还不存在（首次下载，或服务端没按 Range 返回需要从 0 重建）：
            -- "r+b" 要求文件已存在，pos == 0 时换成 "w+b" 新建是安全的 ——
            -- 反正接下来就是从文件头开始写。
            mode = "w+b"
            df, derr = io.open(dst, mode)
        end
        if not df then sf:close(); return 0, "open(" .. mode .. ") 失败:" .. tostring(derr) end
        if method == "seek_set" then
            local sok = pcall(df.seek, df, pos, io.SEEK_SET)
            if not sok then sf:close(); df:close(); return 0, "seek 不支持" end
        end
    end

    local added, werr = 0, nil
    while true do
        local buf = sf:read(4096)
        if not buf or #buf == 0 then break end
        local wok
        if method == "writefile" then wok = io.writeFile(dst, buf, "a+b")
        else wok = df:write(buf) end
        if wok == nil or wok == false then
            werr = "写入被拒(通常是空间不足)"
            break
        end
        added = added + #buf
    end
    sf:close()
    if df then df:close() end

    if werr then return 0, werr end
    if added <= 0 then return 0, "写入 0 字节" end

    local expect = pos + added
    local after = cur_size(dst)
    if after ~= expect then
        -- 探针可能失真（某些文件系统上 io.fileSize 会返回旧值），用逐块读计数复核
        local real = count_size(dst)
        if real == expect then
            log.warn("cloud_disk", "io.fileSize 返回旧值(", after, ")，实际已落盘", real,
                "，本次以下载字节数记账")
            return added
        end
        return 0, string.format("落盘未生效(实际 %d，期望 %d)", real, expect)
    end
    if head_before and head_bytes(dst, 16) ~= head_before then
        return 0, "写入位置错误(文件头被改写)"
    end
    return added
end

--[[降级路径：没有 httpplus 时的一次性整文件下载

不支持断点续传、不支持中途取消（请求是阻塞的），仅保证「能下」。
http.request 的 timeout 单位是**毫秒**；其 callback 签名是 (total, received)。]]
local function plain_download(url, dest, total)
    sys.publish("CLOUD_DISK_PROGRESS", 0, "下载中 0%")
    local code = http.request("GET", url, nil, nil, {
        dst = dest,
        timeout = PLAIN_TIMEOUT_MS,
        callback = function(t, recv)
            if t and t > 0 then
                local pct = math.floor(recv * 100 / t)
                if pct > 99 then pct = 99 end
                sys.publish("CLOUD_DISK_PROGRESS", pct, string.format("下载中 %d%%", pct))
            end
        end,
    }).wait()
    local fsz = cur_size(dest)
    log.info("cloud_disk", "整文件下载 code:", tostring(code), "actual:", fsz,
        "expect:", total or "N/A")
    if code == 200 and fsz > 0 and (not total or fsz == total) then
        sys.publish("CLOUD_DISK_PROGRESS", 100, "下载完成")
        return true, "下载完成", dest
    end
    return false, "下载失败（无续传能力，可重试）", dest
end

--[[整文件单请求下载（httpplus 版，不续传）

只在「四种落盘方式都不可用」时兜底：httpplus 用 "wb" 打开目标文件（截断），从 0 开始写，
不需要任何追加能力；断了就从头再来，但内容一定是干净的。
⚠️ httpplus 可能在正文收完后仍因连接尾部等待而报超时（返回 -1），此时文件其实已经完整
—— 所以成败以**实际字节数**为准，不看返回码。]]
local function whole_file_download(url, dest, total)
    for i = 1, 3 do
        if cancel_flag then return false, CANCEL_MSG, dest end
        local last, pub = 0, -1
        sys.publish("CLOUD_DISK_PROGRESS", 0, "下载中 0%")
        local rc = httpplus.request({
            url = url, method = "GET", dst = dest,
            timeout = CHUNK_TIMEOUT_S * 4,      -- 整文件，给足时间；单位是**秒**
            callback = function(t, recv)
                last = last + (recv or 0)
                local tt = (t and t > 0) and t or total
                if tt and tt > 0 then
                    local pct = math.floor(last * 100 / tt)
                    if pct > 99 then pct = 99 end
                    if pct > pub then
                        pub = pct
                        sys.publish("CLOUD_DISK_PROGRESS", pct, string.format("下载中 %d%%", pct))
                    end
                end
            end,
        })
        local real = count_size(dest)
        log.info("cloud_disk", "整文件下载 rc:", tostring(rc), "落盘:", real, "/",
            tostring(total), "第", i, "次")
        if total and real == total then
            sys.publish("CLOUD_DISK_PROGRESS", 100, "下载完成")
            return true, "下载完成", dest
        end
        if type(rc) == "number" and rc < 0 then sys.waitUntil("IP_READY", 3000) end
    end
    return false, "下载失败（本机不支持分块续传，已重试 3 次）", dest
end

--[[请求一段 Range，落到临时的块文件

关键点：**请求超时（rc = -1）不等于这块白干**。
httpplus 在返回前一定会 close 写句柄（见 httpplus.request 尾部的资源清理），
所以块文件里已经落盘的字节就是从 pos 开始的**有效前缀**，可以直接落盘。

@return rc        httpplus 返回码：200/206 正常；-1 超时；-198 未收到完整头部；-199 发送失败
@return csz       块文件实际落盘字节数
@return total     Content-Range 里的服务端总长（nil = 拿不到分片信息）
@return is_range  true = 带 Content-Range 的分片响应
]]
local function fetch_range(url, chunk_path, pos, want)
    if io.exists(chunk_path) then os.remove(chunk_path) end
    local rc, resp = httpplus.request({
        url = url, method = "GET",
        headers = { ["Range"] = string.format("bytes=%d-%d", pos, pos + want - 1) },
        dst = chunk_path,
        timeout = CHUNK_TIMEOUT_S,
    })
    local total = nil
    if resp and resp.headers then
        local cr = resp.headers["Content-Range"] or resp.headers["content-range"]
        if cr then total = to_num(cr:match("/(%d+)")) end
    end
    return rc, cur_size(chunk_path), total, (total ~= nil)
end

--[[探测服务端文件总长：Range: bytes=0-0 → 206 + Content-Range: bytes 0-0/总长

列表接口已带 size，正常不会走到这里；只有服务端没给 size 时才用它兜底。]]
local function probe_total(url)
    for i = 1, 3 do
        if cancel_flag then return nil end
        local rc, resp = httpplus.request({
            url = url, method = "GET",
            headers = { ["Range"] = "bytes=0-0" },
            timeout = PROBE_TIMEOUT_S, no_cache_body = true,
        })
        if rc == 206 and resp and resp.headers then
            local cr = resp.headers["Content-Range"] or resp.headers["content-range"]
            local t = cr and to_num(cr:match("/(%d+)")) or nil
            if t and t > 0 then return t end
        end
        log.warn("cloud_disk", "探测文件大小失败 rc:", tostring(rc), "第", i, "次")
        sys.waitUntil("IP_READY", 3000)
    end
    return nil
end

--[[下载主流程

  1. 先自检落盘方式（每目录一次）：确认「写出去的字节会落在文件末尾」
  2. 本地已有「小于目标大小」的半成品 → 直接从中断处继续，不重头下
  3. 每块 Range: bytes=<pos>-<pos+want-1> → 块文件 → 落盘 + 三重校验
     · 206 + Content-Range      → 正常分片，落盘
     · 非分片且 pos>0（服务端忽略 Range，body 从 0 开始）→ 老断点作废，用本块内容从 0 重建
     · 块请求超时               → 已落盘字节仍有效，照常落盘，从新断点重试
     · 落盘校验不过（写不进去） → 立即停，报「存储写入失败」，并清掉半成品释放空间
  4. 100% 只在**校验通过后**上报，传输过程中最多 99%（避免「进度 100% 却报错」）
  5. 取消：循环边界检查 cancel_flag，已下载部分保留（下次点击即续传）

@return ok, msg, dest_path]]
local function do_download(item, dest, mount_point)
    local url = item.url
    local total = (item.size and item.size > 0) and item.size or nil

    if not httpplus then
        return plain_download(url, dest, total)
    end

    -- ---- 落盘方式自检（每目录一次） ----
    local dir = dest:match("^(.*/)[^/]*$") or "/"
    local method = sink_cache[dir]
    if method == nil then
        method = sink_selftest(dir)
        sink_cache[dir] = method
    end
    if method == false then
        -- 连 2 字节都写不进去：多半是空间不够，而不是「没有落盘能力」
        local fk = free_kb(mount_point)
        if fk and fk < 300 then
            log.error("cloud_disk", "落盘自检全失败且可用空间仅", math.floor(fk), "KB")
            return false, "存储空间不足（可用 " .. math.floor(fk) .. "KB），请清理后再试", dest
        end
    end

    -- ---- 断点判定 ----
    local have = cur_size(dest)
    if total and have == total then return true, "文件已存在", dest end
    if have > 0 and total and have > total then
        log.warn("cloud_disk", "本地残留大于服务端记录，丢弃重下:", have, ">", total)
        os.remove(dest)
        have = 0
    end

    if not total then
        sys.publish("CLOUD_DISK_PROGRESS", 0, "探测文件大小...")
        total = probe_total(url)
        if not total then return false, "无法获取文件大小，请检查网络", dest end
        if have > total then os.remove(dest); have = 0 end
        if have == total then return true, "文件已存在", dest end
    end

    if method == false then
        -- 无落盘能力 → 整文件单请求（不续传，内容一定干净）
        if have > 0 then os.remove(dest); have = 0 end
        if cur_size(dest) == total then return true, "文件已存在", dest end
        log.info("cloud_disk", "无可用落盘方式，改用整文件下载:", item.name, total)
        return whole_file_download(url, dest, total)
    end

    if have > 0 then
        log.info("cloud_disk", "断点续传:", item.name, have, "/", total, "落盘方式:", method)
    end

    -- ---- 分块循环 ----
    local chunk_path = dest .. ".part"
    local pos, stalled, last_pct = have, 0, -1

    local function report(bytes)
        if total <= 0 then return end
        local pct = math.floor(bytes * 100 / total)
        if pct > 99 then pct = 99 end
        if pct ~= last_pct then
            last_pct = pct
            sys.publish("CLOUD_DISK_PROGRESS", pct, string.format("下载中 %d%%", pct))
        end
    end
    report(pos)

    while pos < total do
        if cancel_flag then
            if io.exists(chunk_path) then os.remove(chunk_path) end
            log.info("cloud_disk", "下载已取消，保留断点:", pos, "/", total)
            return false, CANCEL_MSG, dest
        end

        local want = math.min(CHUNK_KB * 1024, total - pos)
        local rc, csz, svr_total, is_range = fetch_range(url, chunk_path, pos, want)

        -- 块大小探针为 0 时复核一次：把「下到了但 io.fileSize 报 0」与
        -- 「真的什么都没下到」区分开，否则会被误判成网络故障
        if csz == 0 and io.exists(chunk_path) then
            local real = count_size(chunk_path)
            if real > 0 then
                log.warn("cloud_disk", "块大小探针失真(0)，逐块计数实际:", real)
                csz = real
            end
        end

        if svr_total and svr_total ~= total then
            log.warn("cloud_disk", "服务端总长与列表不一致，以服务端为准:",
                svr_total, "列表:", total)
            total = svr_total
        end

        if csz > 0 then
            if (not is_range) and pos > 0 then
                log.warn("cloud_disk", "服务端未按 Range 返回，重置断点:", pos)
                os.remove(dest)
                pos = 0
            end

            local added, cerr = commit_chunk(chunk_path, dest, pos, method)
            if io.exists(chunk_path) then os.remove(chunk_path) end

            if added <= 0 then
                -- 落盘失败：把现场信息一次打全，并清掉半成品（半成品会把存储一直占着）
                local fk = free_kb(mount_point)
                log.error("cloud_disk", "落盘失败:", tostring(cerr),
                    "方式:", method, "块:", csz, "已下:", pos, "/", total,
                    "fileSize:", tostring(cur_size(dest)), "count:", tostring(count_size(dest)),
                    "可用KB:", tostring(fk and math.floor(fk) or "?"))
                if io.exists(dest) then os.remove(dest) end
                return false, "存储写入失败，已清理未完成文件（可用 "
                    .. (fk and (math.floor(fk) .. "KB") or "未知") .. "）", dest
            end

            log.info("cloud_disk", "续传块 rc:", tostring(rc), "块:", csz, "落盘:", added,
                "方式:", method, "进度:", pos + added, "/", total)
            pos = pos + added
            stalled = 0
            report(pos)
        else
            if io.exists(chunk_path) then os.remove(chunk_path) end
            stalled = stalled + 1
            log.warn("cloud_disk", "本块无数据 rc:", tostring(rc), "已下:", pos, "/", total,
                "连续失败:", stalled)
            -- 网络层失败（rc<0）先等一次 IP_READY，给 WiFi 重连/4G 切换留时间
            if type(rc) == "number" and rc < 0 then sys.waitUntil("IP_READY", 3000) end
            if stalled >= MAX_STALLED then
                return false, "网络异常，下载中断（已下载 " .. human_size(pos) .. "，可重试继续）", dest
            end
        end
    end

    -- ---- 校验 ----
    local fsz = cur_size(dest)
    if fsz ~= total then
        local real = count_size(dest)
        if real ~= total then
            log.warn("cloud_disk", "下载结束但大小不符 fileSize:", fsz, "count:", real,
                "expect:", total)
            return false, string.format("文件不完整(%d/%d字节)，可重试继续", real, total), dest
        end
        log.warn("cloud_disk", "io.fileSize 失真（返回", fsz, "，实际", real, "），以实际为准")
    end
    sys.publish("CLOUD_DISK_PROGRESS", 100, "下载完成")
    return true, "下载完成", dest
end

local function start_download(item)
    if downloading then
        sys.publish("CLOUD_DISK_ERROR", "已有下载任务进行中")
        return
    end
    if type(item) ~= "table" or not item.url then
        sys.publish("CLOUD_DISK_ERROR", "文件信息无效")
        return
    end
    downloading = true
    cancel_flag = false
    sys.taskInit(function()
        local need_kb = item.size and math.ceil(item.size / 1024) or nil

        --[[下载前的空间预检（对齐 exapp：free >= need + MIN_FREE_SPACE_KB，详见 pick_storage）

        传 fname 是为了扣掉本地已有的半成品：断点续传时「还需要写」的只是剩余部分，
        按整文件大小判定会把本来够用的位置误判成放不下。]]
        sys.publish("CLOUD_DISK_STATUS", "正在检查存储空间...")
        local mp, label, _tk, fk, detail = pick_storage(need_kb, item.name)
        sys.publish("CLOUD_DISK_STATUS", "")

        local ok, msg, path
        if not mp then
            -- 空间不够就在这里说清楚，别下到一半才失败
            local size_txt = human_size(item.size)
            if size_txt == "" then size_txt = "大小未知" end
            log.warn("cloud_disk", "空间预检不过，取消下载:", item.name, "本文件", size_txt,
                "详情:", tostring(detail))
            ok = false
            msg = "存储空间不足：本文件 " .. size_txt .. "，另需保留 "
                .. MIN_FREE_SPACE_KB .. "KB；" .. tostring(detail)
        else
            local dir = mp .. DOWNLOAD_DIR .. "/"
            log.info("cloud_disk", "下载落地:", dir, "存储:", label,
                "可用KB:", tostring(fk and math.floor(fk) or "?"))
            if not ensure_dir(dir) then
                ok, msg = false, "无法创建目录 " .. dir
            else
                ok, msg, path = do_download(item, dir .. item.name, mp)
            end
        end

        downloading = false
        cancel_flag = false
        if ok then
            log.info("cloud_disk", "下载完成:", path, human_size(cur_size(path)))
            sys.publish("CLOUD_DISK_DONE", true,
                "已保存到 " .. label .. " " .. DOWNLOAD_DIR .. "/：" .. item.name, path, "ok")
        else
            log.warn("cloud_disk", "下载结束(未完成):", item.name, tostring(msg))
            sys.publish("CLOUD_DISK_DONE", false, tostring(msg or "下载失败"), nil,
                (msg == CANCEL_MSG) and "cancel" or "error")
        end
    end)
end

-- ==================== 初始化 ====================

pcall(fskv.init)

-- rsa 是核心库（rotable，缺失时直接调用会崩 VM），必须先用 pcall 探一次
-- （与 factory_rec 踩过的坑一致）
do
    local ok = pcall(function() return rsa.encrypt ~= nil end)
    rsa_ok = ok and (rsa ~= nil) and (rsa.encrypt ~= nil)
    if not rsa_ok then
        log.warn("cloud_disk", "固件缺少 rsa 核心库，IoT 登录与网盘鉴权均不可用")
    end
end

-- 打开网盘：读登录态 → 缺 A 就现取

--[[这里**不发列表请求**，只把账号状态播给 UI。

列表加载由 UI 在「登录态由未登录翻转为已登录」的那个边沿上发 CLOUD_DISK_LOAD 触发，
这样「打开时已登录」与「在页内刚登录成功」走的是同一条路径，不会出现两次请求；
业务层若在这里自己再 fetch 一次，就会和 UI 的边沿触发撞成双请求。]]
sys.subscribe("CLOUD_DISK_OPEN", function()
    sys.taskInit(function()
        publish_account()
        if not get_space_key() then
            local ok, err = ensure_space_key()
            if not ok then
                sys.publish("CLOUD_DISK_STATUS", "")
                sys.publish("CLOUD_DISK_ERROR", err or "请先登录 IoT 账号")
            end
        end
        publish_account()
    end)
end)

sys.subscribe("CLOUD_DISK_LOAD", function(...) sys.taskInit(fetch_list, ...) end)

sys.subscribe("CLOUD_DISK_DOWNLOAD", function(item) start_download(item) end)

--[[取消进行中的下载

只置标志，真正的收尾在下载循环的块边界（一块最多 CHUNK_TIMEOUT_S 秒）——
http 请求本身是阻塞的，没有中断接口，这也是把块切成 128KB 的原因之一：
块越小，取消越灵敏。已下载的部分**保留**，再次点击该文件即可续传。]]
sys.subscribe("CLOUD_DISK_CANCEL_DOWNLOAD", function()
    if not downloading then return end
    cancel_flag = true
    log.info("cloud_disk", "收到取消下载请求")
end)

-- 在网盘页/设置页发起登录并成功后，补取 A
sys.subscribe("IOT_LOGIN_RESULT", function(result)
    if not (result and result.success) then return end
    sys.taskInit(function()
        local ok_a, acct = pcall(fskv.get, "iot_account")
        local ok_p, pwd  = pcall(fskv.get, "iot_password")
        if ok_a and ok_p and type(acct) == "string" and type(pwd) == "string"
            and acct ~= "" and pwd ~= "" and not get_space_key() then
            local ok, err = fetch_space_key(acct, pwd)
            if not ok then log.warn("cloud_disk", "补取 space_key 失败:", tostring(err)) end
        end
        publish_account()
    end)
end)

sys.subscribe("IOT_LOGOUT_RESULT", function()
    clear_space_key()
    publish_account()
end)
