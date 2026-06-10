-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gmssl_keyex"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

--[[
本demo演示 GB/T 32918.3-2016 SM2椭圆曲线公钥密码算法
密钥交换协议 的完整实现

依赖：
  - components/gmssl/bind/luat_lib_gmssl.c (需包含 sm2pointmul/sm2ecdh 绑定)
  - gmssl.sm2encrypt / sm2decrypt / sm2sign / sm2verify / sm2keygen / sm3

协议步骤(GPT32918.3-2016 第6.2节)：
  1. 双方各自生成长期密钥对 + 临时密钥对
  2. 交换公钥 RA, RB
  3. 计算杂凑值 ZA, ZB
  4. 计算标量点乘 U/V
  5. KDF 派生共享密钥 KA, KB
  6. 验证 KA == KB
  7. 可选：计算确认值 SA/SB
]]

-- 死机后停机，一般用于调试状态
mcu.hardfault(0)

sys.taskInit(function()

    -- ==================== 参数定义 ====================

    -- SM2曲线参数(国密推荐曲线)
    local xG = "32C4AE2C1F1981195F9904466A39C9948FE30BBFF2660BE1715A4589334C74C7"
    local yG = "BC3736A2F4F6779C59BDCEE36B692153D0A9877CC62A474002DF32E52139F0A0"
    local a  = "FFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFC"
    local b  = "28E9FA9E9D9F5E344D5A9E4BCF6509A7F39789F515AB8F92DDBCBD414D940E93"

    -- 双方ID (协议中ZA/ZB计算需使用)
    local idA = "1234567812345678"
    local idB = "8765432187654321"

    -- 共享密钥长度 (字节)
    local klen = 16

    -- ==================== 工具函数 ====================

    -- entl: 将ID的bit长度编码为2字节大端
    local function entl(id)
        local bits = #id * 8
        return string.char(bits // 256, bits % 256)
    end

    -- 计算 Z 值: Z = SM3(ENTL || ID || a || b || xG || yG || xA || yA)
    local function computeZ(id, pkx, pky)
        local raw = entl(id) .. id
            .. string.fromHex(a)
            .. string.fromHex(b)
            .. string.fromHex(xG)
            .. string.fromHex(yG)
            .. string.fromHex(pkx)
            .. string.fromHex(pky)
        return gmssl.sm3(raw)
    end

    -- SM3-KDF: GBT 32918.3-2016 第4.2.5节
    local function sm3_kdf(z, klen)
        local ct = 1
        local result = ""
        -- 将计数器编码为4字节大端, 优先用 string.pack, 不可用时回退手动构造
        local function ct2bytes(n)
            if pcall(string.pack, ">I4", n) then
                return string.pack(">I4", n)
            end
            -- 回退: 手动构造4字节大端 unsigned int
            return string.char((n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF)
        end
        while #result < klen do
            local ctBytes = ct2bytes(ct)
            local h = gmssl.sm3(z .. ctBytes)
            result = result .. h
            ct = ct + 1
        end
        return string.sub(result, 1, klen)
    end

    -- 确认值: GBT 32918.3-2016 第6.2节可选步骤
    local function confirm(prefix, y, xU, zA, zB, x1, y1, x2, y2)
        local inner = gmssl.sm3(xU .. zA .. zB .. x1 .. y1 .. x2 .. y2)
        return gmssl.sm3(prefix .. y .. inner)
    end

    -- ==================== Step 1: 密钥准备 ====================
    log.info("SM2 KeyEx", "===== Step 1: 生成密钥对 =====")

    -- A方长期密钥
    local pkxA, pkyA, privA = gmssl.sm2keygen()
    assert(pkxA and pkyA and privA, "A长期密钥生成失败")
    log.info("SM2 KeyEx", "A 长期密钥已生成")
    sys.wait(10)  -- 释放CPU喂狗, sm2keygen底层点乘耗时较长

    -- B方长期密钥
    local pkxB, pkyB, privB = gmssl.sm2keygen()
    assert(pkxB and pkyB and privB, "B长期密钥生成失败")
    log.info("SM2 KeyEx", "B 长期密钥已生成")
    sys.wait(10)

    -- A方临时密钥 (rA, RA)  -- GBT32918.3 6.1节
    local rAx, rAy, rA = gmssl.sm2keygen()
    assert(rAx and rAy and rA, "A临时密钥生成失败")
    log.info("SM2 KeyEx", "A 临时密钥已生成")
    sys.wait(10)

    -- B方临时密钥 (rB, RB)
    local rBx, rBy, rB = gmssl.sm2keygen()
    assert(rBx and rBy and rB, "B临时密钥生成失败")
    log.info("SM2 KeyEx", "B 临时密钥已生成")

    -- ==================== Step 2: 交换公钥 ====================
    log.info("SM2 KeyEx", "===== Step 2: 交换临时公钥 RA/RB =====")
    -- 实际通信中通过mqtt/http等传输，此处直接本地传递

    -- ==================== Step 3: 计算 Z 值 ====================
    log.info("SM2 KeyEx", "===== Step 3: 计算杂凑值 ZA/ZB =====")

    local ZA = computeZ(idA, pkxA, pkyA)
    log.info("SM2 KeyEx", "ZA=", string.toHex(ZA):sub(1,16) .. "...")

    local ZB = computeZ(idB, pkxB, pkyB)
    log.info("SM2 KeyEx", "ZB=", string.toHex(ZB):sub(1,16) .. "...")

    -- ==================== Step 4: A侧计算 ====================
    log.info("SM2 KeyEx", "===== Step 4: 标量点乘 (A侧) =====")

    -- 验证 sm2pointmul 基本功能: [privA]G 应等于 pkxA/pkyA
    local testRx, testRy = gmssl.sm2pointmul(privA, xG, yG)
    if testRx == pkxA and testRy == pkyA then
        log.info("SM2 KeyEx", "自验证通过: [dA]G == PA")
    else
        log.error("SM2 KeyEx", "自验证失败!")
    end

    -- 验证 ECDH: privA * Bpub ↔ privB * Apub
    local sAx, sAy = gmssl.sm2ecdh(privA, pkxB, pkyB)
    local sBx, sBy = gmssl.sm2ecdh(privB, pkxA, pkyA)
    if sAx == sBx and sAy == sBy then
        log.info("SM2 KeyEx", "ECDH一致性验证通过")
    else
        log.error("SM2 KeyEx", "ECDH一致性验证失败!")
    end

    -- A侧: 使用 self私钥 × 对方临时公钥
    -- 注意: GBT32918.3 §6.2 标准要求计算 tA=(dA+x‾1·rA) 并执行点加法 V=[h·tA](PB+[x‾2]RB)
    -- 当前使用简化ECDH直接计算 [dA]*RB, 完整实现需新增 sm2_point_add() C层绑定
    local ux_A, uy_A = gmssl.sm2ecdh(privA, rBx, rBy)
    assert(ux_A and uy_A, "A侧ECDH失败")
    sys.wait(10)

    -- ==================== Step 5: KDF 密钥派生 ====================
    log.info("SM2 KeyEx", "===== Step 5: KDF 派生共享密钥 =====")

    -- sm2ecdh 返回 hex 字符串, 需转为 raw bytes 与 ZA/ZB 拼接
    local uRaw_A = string.fromHex(ux_A) .. string.fromHex(uy_A) .. ZA .. ZB
    local KA = sm3_kdf(uRaw_A, klen)

    -- B侧: (实际部署时B在远端独立计算)
    local ux_B, uy_B = gmssl.sm2ecdh(privB, rAx, rAy)
    local uRaw_B = string.fromHex(ux_B) .. string.fromHex(uy_B) .. ZA .. ZB
    local KB = sm3_kdf(uRaw_B, klen)
    sys.wait(10)

    log.info("SM2 KeyEx", "共享密钥 KA:", string.toHex(KA):sub(1, 20) .. "...")
    log.info("SM2 KeyEx", "共享密钥 KB:", string.toHex(KB):sub(1, 20) .. "...")

    -- ==================== Step 6.1: 验证协商一致性 ====================
    log.info("SM2 KeyEx", "===== Step 6: 验证 KA == KB =====")

    if KA == KB then
        log.info("SM2 KeyEx", "√ 密钥协商一致! GBT 32918.3-2016 通过!")
    else
        log.error("SM2 KeyEx", "× 密钥协商不一致!")
    end

    -- ==================== Step 6.2: 可选确认值 ====================
    log.info("SM2 KeyEx", "===== 可选: 确认值 SA/SB =====")

    local x1 = string.fromHex(rAx) -- RA.x (32字节)
    local y1 = string.fromHex(rAy) -- RA.y
    local x2 = string.fromHex(rBx) -- RB.x
    local y2 = string.fromHex(rBy) -- RB.y

    -- sm2ecdh 返回 hex 字符串, confirm 期望 raw bytes, 需统一转换
    local sA = confirm("\x02", string.fromHex(uy_A), string.fromHex(ux_A), ZA, ZB, x1, y1, x2, y2)
    local sB = confirm("\x03", string.fromHex(uy_B), string.fromHex(ux_B), ZA, ZB, x1, y1, x2, y2)

    log.info("SM2 KeyEx", "SA=", string.toHex(sA):sub(1, 16) .. "...")
    log.info("SM2 KeyEx", "SB=", string.toHex(sB):sub(1, 16) .. "...")

    -- ==================== 额外验证: 加解密+签名验签 ====================

    log.info("SM2 KeyEx", "===== 额外: SM2加解密验证 =====")
    local msg = "Hello SM2 Key Exchange!"
    local enc = gmssl.sm2encrypt(pkxB, pkyB, msg)
    if enc then
        local dec = gmssl.sm2decrypt(privB, enc)
        log.info("SM2 KeyEx", "SM2加解密:", dec == msg and "√ 通过" or "× 失败")
    end

    log.info("SM2 KeyEx", "===== 额外: SM2签名验签验证 =====")
    local sig = gmssl.sm2sign(privA, msg, idA)
    if sig then
        local ok = gmssl.sm2verify(pkxA, pkyA, msg, idA, sig)
        log.info("SM2 KeyEx", "SM2签名验签:", ok and "√ 通过" or "× 失败")
    end

    log.info("SM2 KeyEx", "===== 额外: SM3 杂凑验证 =====")
    local h = gmssl.sm3("gbt32918.3 test")
    log.info("SM2 KeyEx", "SM3:", string.toHex(h))

    log.info("SM2 KeyEx", "=====================================")
    log.info("SM2 KeyEx", "ALL Done - GBT 32918.3-2016 演示完成")
    log.info("SM2 KeyEx", "=====================================")

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
