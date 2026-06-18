-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gmssl_keyex"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

--[[
本demo演示 GB/T 32918.3-2016 SM2椭圆曲线公钥密码算法
密钥交换协议 的完整实现

依赖:
  - gmssl.sm2pointmul / sm2pointadd / sm2pointisoncurve (椭圆曲线点运算)
  - gmssl.sm2bnadd / sm2bnmul (模n大数运算)
  - gmssl.sm2keygen / sm3 / sm2sign / sm2verify (原有的国密原语)

协议步骤(GBT32918.3-2016 第6.2节):
  1. 双方各自生成长期密钥对 + 临时密钥对
  2. 交换公钥 RA, RB
  3. 计算杂凑值 ZA, ZB
  4. 计算 keXHat + 模n组合因子 tA, tB
  5. 计算点乘/点加得到 V = [h*t](P + [x̄]*R)
  6. KDF 派生共享密钥 K (32字节)
  7. 验证 KA == KB
  8. S1/S2 交叉校验
  9. SM4 会话密钥自验证 (key=K[1:16], iv=K[17:32])

实际部署说明:
  - 长期密钥由客户预置 (服务器/设备各持一对静态SM2密钥)
  - 临时密钥每次会话动态生成
  - 设备端作为发起方(A), 服务端作为响应方(B)
  - 通过通信协议交换RA/RB和S1/S2
]]

mcu.hardfault(0)

sys.taskInit(function()

    -- ==================== SM2曲线参数 (国密推荐曲线, 固定值) ====================
    local xG = "32C4AE2C1F1981195F9904466A39C9948FE30BBFF2660BE1715A4589334C74C7"
    local yG = "BC3736A2F4F6779C59BDCEE36B692153D0A9877CC62A474002DF32E52139F0A0"
    local a  = "FFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFC"
    local b  = "28E9FA9E9D9F5E344D5A9E4BCF6509A7F39789F515AB8F92DDBCBD414D940E93"

    -- 双方ID (协议中ZA/ZB计算需使用, 实际部署时由客户传入)
    local idA = "1234567812345678"
    local idB = "8765432187654321"

    -- 共享密钥长度: 32字节, 前16字节做SM4 key, 后16字节做SM4 iv
    local klen = 32

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

    -- keXHat: x̄ = 2^127 + (x & (2^127-1))  GBT32918.3 §6.2
    local function keXHat(xHex)
        local low128 = xHex:sub(33, 64)                    -- 取低128位
        local hi = tonumber(low128:sub(1, 2), 16)
        hi = (hi & 0x7F) | 0x80                             -- 清bit127再置位
        return string.format("%02X", hi) .. low128:sub(3)   -- 32字符HEX (128位)
    end

    -- 扩展HEX到64字符(高位补零)
    local function pad64(s)
        while #s < 64 do s = "0" .. s end
        return s
    end

    -- SM3-KDF: GBT 32918.3-2016 第4.2.5节
    local function sm3_kdf(z, klen)
        local ct = 1
        local result = ""
        while #result < klen do
            local ctBytes = string.pack(">I4", ct)
            local h = gmssl.sm3(z .. ctBytes)
            result = result .. h
            ct = ct + 1
        end
        return string.sub(result, 1, klen)
    end

    local function bytes(...) return table.concat({...}) end

    -- ==================== Step 1: 密钥准备 ====================
    -- 实际部署: 长期密钥由客户预置, 此处用sm2keygen()演示
    log.info("SM2 KeyEx", "===== Step 1: 生成密钥对 =====")

    -- A方 (设备端/发起方)
    local pkxA, pkyA, privA = gmssl.sm2keygen()
    assert(pkxA and pkyA and privA, "A长期密钥生成失败")
    log.info("SM2 KeyEx", "A 长期密钥已生成")
    sys.wait(10)

    -- B方 (服务端/响应方)
    local pkxB, pkyB, privB = gmssl.sm2keygen()
    assert(pkxB and pkyB and privB, "B长期密钥生成失败")
    log.info("SM2 KeyEx", "B 长期密钥已生成")
    sys.wait(10)

    -- 临时密钥 (每次会话动态生成)
    local rAx, rAy, rA = gmssl.sm2keygen()
    local rBx, rBy, rB = gmssl.sm2keygen()
    log.info("SM2 KeyEx", "A/B 临时密钥已生成")
    sys.wait(10)

    -- ==================== Step 2: 校验临时公钥 ====================
    log.info("SM2 KeyEx", "===== Step 2: 校验临时公钥在曲线上 =====")
    assert(gmssl.sm2pointisoncurve(rAx, rAy) == true, "RA不在曲线上!")
    assert(gmssl.sm2pointisoncurve(rBx, rBy) == true, "RB不在曲线上!")
    log.info("SM2 KeyEx", "RA/RB均在曲线上 √")

    -- ==================== Step 3: 计算 Z 值 ====================
    log.info("SM2 KeyEx", "===== Step 3: 计算杂凑值 ZA/ZB =====")

    local ZA = computeZ(idA, pkxA, pkyA)
    local ZB = computeZ(idB, pkxB, pkyB)
    log.info("SM2 KeyEx", "ZA=", string.toHex(ZA):sub(1,16) .. "...")
    log.info("SM2 KeyEx", "ZB=", string.toHex(ZB):sub(1,16) .. "...")

    -- ==================== Step 4: 协议核心计算 ====================
    log.info("SM2 KeyEx", "===== Step 4: GBT32918.3 §6.2 核心计算 =====")

    -- ---- A侧 (发起方) ----
    local x2hat = pad64(keXHat(rAx))              -- x̄2 = keXHat(RA.x)
    local x1hat = pad64(keXHat(rBx))              -- x̄1 = keXHat(RB.x)
    local tA = gmssl.sm2bnadd(privA,              -- tA = (dA + x̄2*rA) mod n
                gmssl.sm2bnmul(x2hat, rA))

    local ux, uy = gmssl.sm2pointmul(x1hat, rBx, rBy)        -- U = [x̄1]*RB
    local vx, vy = gmssl.sm2pointadd(pkxB, pkyB, ux, uy)     -- V = PB + U  (点加)
    local Vx_A, Vy_A = gmssl.sm2pointmul(tA, vx, vy)         -- V = [tA]*V
    sys.wait(10)

    -- ---- B侧 (响应方) ----
    local x1hat_B = pad64(keXHat(rAx))            -- x̄1 = keXHat(RA.x)
    local x2hat_B = pad64(keXHat(rBx))            -- x̄2 = keXHat(RB.x)
    local tB = gmssl.sm2bnadd(privB,              -- tB = (dB + x̄2*rB) mod n
                gmssl.sm2bnmul(x2hat_B, rB))

    local ux_B, uy_B = gmssl.sm2pointmul(x1hat_B, rAx, rAy)
    local vx_B, vy_B = gmssl.sm2pointadd(pkxA, pkyA, ux_B, uy_B)
    local Vx_B, Vy_B = gmssl.sm2pointmul(tB, vx_B, vy_B)
    sys.wait(10)

    -- 校验V不是无穷远点
    local zero = "0000000000000000000000000000000000000000000000000000000000000000"
    assert(Vx_A ~= zero and Vx_B ~= zero, "V是无穷远点!")

    -- ==================== Step 5: KDF 派生共享密钥 ====================
    log.info("SM2 KeyEx", "===== Step 5: KDF 派生共享密钥 =====")

    local vRaw = string.fromHex(Vx_A) .. string.fromHex(Vy_A) .. ZA .. ZB
    local K = sm3_kdf(vRaw, klen)  -- 32字节共享密钥
    log.info("SM2 KeyEx", "共享密钥 K(32B):", string.toHex(K))

    -- ==================== Step 6: 验证协商一致性 ====================
    log.info("SM2 KeyEx", "===== Step 6: 验证 KA == KB =====")

    local vRaw_B = string.fromHex(Vx_B) .. string.fromHex(Vy_B) .. ZA .. ZB
    local KB = sm3_kdf(vRaw_B, klen)
    assert(K == KB, "× 密钥协商不一致!")
    log.info("SM2 KeyEx", "√ 密钥协商一致! GB/T 32918.3-2016 KeyExchange 通过!")

    -- ==================== Step 7: S1/S2 交叉校验 ====================
    log.info("SM2 KeyEx", "===== Step 7: S1/S2 交叉校验 =====")

    -- h1 = Vx || ZA || ZB || RB.x || RB.y || RA.x || RA.y   (双方计算相同)
    local h1 = bytes(
        string.fromHex(Vx_A), ZA, ZB,
        string.fromHex(rBx), string.fromHex(rBy),
        string.fromHex(rAx), string.fromHex(rAy)
    )
    local hash = gmssl.sm3(h1)

    -- A侧生成 S1 (用0x02前缀) 发送给 B 校验
    local S1 = gmssl.sm3(bytes("\x02", string.fromHex(Vy_A), hash))
    -- B侧也能独立算出S1, 校验收到的S1是否一致
    local S1_check = gmssl.sm3(bytes("\x02", string.fromHex(Vy_B), hash))
    assert(S1 == S1_check, "× S1交叉校验失败!")

    -- B侧生成 S2 (用0x03前缀) 发送给 A 校验
    local S2 = gmssl.sm3(bytes("\x03", string.fromHex(Vy_B), hash))
    -- A侧也能独立算出S2, 校验收到的S2是否一致
    local S2_check = gmssl.sm3(bytes("\x03", string.fromHex(Vy_A), hash))
    assert(S2 == S2_check, "× S2交叉校验失败!")

    log.info("SM2 KeyEx", "√ S1/S2 交叉校验通过!")
    log.info("SM2 KeyEx", "S1=", string.toHex(S1):sub(1,16) .. "...")
    log.info("SM2 KeyEx", "S2=", string.toHex(S2):sub(1,16) .. "...")

    -- ==================== Step 8: SM4 会话密钥自验证 ====================
    -- K前16字节=SM4 key, K后16字节=SM4 iv (CBC模式)
    log.info("SM2 KeyEx", "===== Step 8: SM4 会话密钥自验证 =====")

    local sm4Key = string.sub(K, 1, 16)    -- 前16字节
    local sm4Iv  = string.sub(K, 17, 32)   -- 后16字节
    local testMsg = "hello_from_sm2_keyex"

    local enc = gmssl.sm4encrypt("CBC", "PKCS7", testMsg, sm4Key, sm4Iv)
    assert(enc, "SM4 CBC加密失败")
    local dec = gmssl.sm4decrypt("CBC", "PKCS7", enc, sm4Key, sm4Iv)
    assert(dec == testMsg, "SM4 CBC解密结果不一致!")
    log.info("SM2 KeyEx", "√ SM4会话密钥自验证通过")

    -- ==================== 验证客户已知向量 (SM3基础验证) ====================
    -- SM3("abc") 是国密标准向量, 验证底层SM3正确性
    local sm3_abc = string.toHex(gmssl.sm3("abc"))
    assert(sm3_abc == "66C7F0F462EEEDD9D1F2D46BDC10E4E24167C4875CF2F7A2297DA02B8F4BA8E0",
        "SM3(abc) 标准向量不匹配!")
    log.info("SM2 KeyEx", "√ SM3(abc) 标准向量验证通过")

    log.info("SM2 KeyEx", "=====================================")
    log.info("SM2 KeyEx", "ALL Done - GBT 32918.3-2016 完整测试通过!")
    log.info("SM2 KeyEx", "=====================================")

end)

-- 用户代码已结束---------------------------------------------
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
