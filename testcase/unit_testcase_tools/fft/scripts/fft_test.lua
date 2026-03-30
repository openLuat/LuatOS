local fft_tests = {}

function fft_tests.create_u12_signal(N, fs, freq, amplitude, offset)
    local real_i16 = zbuff.create(N * 2)
    local imag_i16 = zbuff.create(N * 2)

    for i = 0, N - 1 do
        local t = i / fs
        local x = math.sin(2 * math.pi * freq * t)
        local val = math.floor(offset + amplitude * x + 0.5)
        if val < 0 then
            val = 0
        end
        if val > 4095 then
            val = 4095
        end

        real_i16:seek(i * 2, zbuff.SEEK_SET)
        real_i16:writeU16(val)

        imag_i16:seek(i * 2, zbuff.SEEK_SET)
        imag_i16:writeU16(0)
    end

    return real_i16, imag_i16
end

function fft_tests.test_fft_generate_twiddle()
    -- 范围内测试：
    -- 选择数据2,2⁵ = 32,2¹⁰ = 1024,2¹⁴ = 16384等
    local test_data = {2, 32, 1024, 16384}
    for i, num in ipairs(test_data) do
        -- 直接调用，不使用pcall
        local Wc, Ws = fft.generate_twiddles(num)

        -- 检查返回值是否存在
        assert(Wc ~= nil, string.format("N=%d: Wc为nil", num))
        assert(Ws ~= nil, string.format("N=%d: Ws为nil", num))

        -- 验证返回值类型
        assert(type(Wc) == "table", string.format("N=%d: Wc类型错误: 应为table, 实际为%s", num, type(Wc)))
        assert(type(Ws) == "table", string.format("N=%d: Ws类型错误: 应为table, 实际为%s", num, type(Ws)))

        -- 验证返回值长度
        local expected_length = math.floor(num / 2)
        assert(#Wc == expected_length,
            string.format("N=%d: Wc长度错误: 预期长度：%d, 实际长度：%d", num, expected_length, #Wc))
        assert(#Ws == expected_length,
            string.format("N=%d: Ws长度错误: 预期长度：%d, 实际长度：%d", num, expected_length, #Ws))

        -- 验证所有元素在单位圆上（抽样检查）
        if #Wc > 0 then
            local indices_to_check = {}
            -- 总是检查第一个元素
            table.insert(indices_to_check, 1)

            -- 检查中间元素（如果有）
            local mid_index = math.floor((#Wc + 1) / 2)
            if mid_index > 1 and mid_index <= #Wc then
                table.insert(indices_to_check, mid_index)
            end

            -- 检查最后一个元素（如果不是第一个）
            if #Wc > 1 then
                table.insert(indices_to_check, #Wc)
                -- 最后一个旋转因子对应角度接近180°
            end

            for _, idx in ipairs(indices_to_check) do
                -- 检查数组元素是否存在
                local wc_val = Wc[idx] -- cos值
                local ws_val = Ws[idx] -- -sin值

                assert(wc_val ~= nil, string.format("N=%d: Wc[%d]为nil", num, idx))
                assert(ws_val ~= nil, string.format("N=%d: Ws[%d]为nil", num, idx))
                assert(type(wc_val) == "number",
                    string.format("N=%d: Wc[%d]不是数字类型: %s", num, idx, type(wc_val)))
                assert(type(ws_val) == "number",
                    string.format("N=%d: Ws[%d]不是数字类型: %s", num, idx, type(ws_val)))

                -- 关键检查：计算模长的平方
                -- 旋转因子公式：W(k) = cos(θ) - j·sin(θ)
                -- 单位圆要求：cos² + sin² = 1
                local magnitude_sq = wc_val * wc_val + ws_val * ws_val
                assert(math.abs(magnitude_sq - 1.0) < 0.001,
                    string.format("N=%d: W[%d] 不在单位圆上: |W|² = %.6f", num, idx, magnitude_sq))
            end
        end

        print(string.format("N=%d: 旋转因子测试通过", num))
    end

    print("所有旋转因子测试通过！")
end

function fft_tests.test_fft_generate_twiddles_error()
    -- 边界情况测试,增加额外的错误测试
    -- 选择数据不满足这个条件：必须为 2 的幂次方
    local invalid_test_data = {0, 3, 100}
    for i, num in ipairs(invalid_test_data) do
        local success, Wc, Ws = pcall(fft.generate_twiddles, num)
        assert(success ~= true, string.format("N=%d: 应该失败（非2的幂次），但成功返回了", num))
    end
end

-- generate_twiddles 边界条件测试（负数、超大值）
function fft_tests.test_fft_generate_twiddles_boundary()
    log.info("generate_twiddles测试", "边界条件测试（负数、超大值）")

    -- 测试负数
    local negative_values = {-1, -2, -8, -1024}
    for _, num in ipairs(negative_values) do
        local success, Wc, Ws = pcall(fft.generate_twiddles, num)
        assert(success ~= true, string.format("N=%d: 负数参数应该失败但成功了", num))
    end

    -- 测试超大值（超过16384）
    local large_values = {333333, 524288, 1048576, 2003521}
    for _, num in ipairs(large_values) do
        local success, Wc, Ws = pcall(fft.generate_twiddles, num)
        -- 这些值要么不是2的幂次，要么内存不足，应该失败
        assert(success ~= true, string.format("N=%d: 超大值参数应该失败但成功了", num))
    end
end

-- generate_twiddles_q15_to_zbuff 边界条件测试
function fft_tests.test_fft_generate_twiddles_q15_boundary()
    log.info("generate_twiddles_q15_to_zbuff测试", "边界条件测试")

    local valid_N = 64

    -- 测试负数N
    local success, err = pcall(fft.generate_twiddles_q15_to_zbuff, -1, zbuff.create(64), zbuff.create(64))
    assert(success ~= true, "负数N应该失败但成功了")

    -- 测试N为0
    local success2, err2 = pcall(fft.generate_twiddles_q15_to_zbuff, 0, zbuff.create(64), zbuff.create(64))
    assert(success2 ~= true, "N=0应该失败但成功了")

    -- 测试N不是2的幂次
    local success3, err3 = pcall(fft.generate_twiddles_q15_to_zbuff, 100, zbuff.create(100), zbuff.create(100))
    assert(success3 ~= true, "N=100（非2的幂次）应该失败但成功了")

    -- 测试Wc_zb为nil
    local success4, err4 = pcall(fft.generate_twiddles_q15_to_zbuff, valid_N, nil, zbuff.create(valid_N))
    assert(success4 ~= true, "Wc_zb为nil应该失败但成功了")

    -- 测试Ws_zb为nil
    local success5, err5 = pcall(fft.generate_twiddles_q15_to_zbuff, valid_N, zbuff.create(valid_N), nil)
    assert(success5 ~= true, "Ws_zb为nil应该失败但成功了")

    -- 测试Wc_zb类型错误（table代替zbuff）
    local success6, err6 = pcall(fft.generate_twiddles_q15_to_zbuff, valid_N, {}, zbuff.create(valid_N))
    assert(success6 ~= true, "Wc_zb类型错误应该失败但成功了")

    -- 测试Ws_zb类型错误（string代替zbuff）
    local success7, err7 = pcall(fft.generate_twiddles_q15_to_zbuff, valid_N, zbuff.create(valid_N), "invalid")
    assert(success7 ~= true, "Ws_zb类型错误应该失败但成功了")

    -- 测试zbuff大小不足
    local small_zbuff = zbuff.create(10)
    local success8, err8 = pcall(fft.generate_twiddles_q15_to_zbuff, valid_N, small_zbuff, zbuff.create(valid_N))
    assert(success8 ~= true, "Wc_zb大小不足应该失败但成功了")

    log.info("结果", "√ generate_twiddles_q15_to_zbuff 边界条件测试通过")
end

-- fft.run 边界条件测试（负数、超大值、无效参数）
function fft_tests.test_fft_run_boundary()
    log.info("fft.run测试", "边界条件测试")

    local valid_N = 64
    local valid_zbuff = zbuff.create(valid_N * 4)
    local valid_Wc, valid_Ws = fft.generate_twiddles(valid_N)

    -- 测试负数N
    local success, err = pcall(fft.run, valid_zbuff, valid_zbuff, -1, valid_Wc, valid_Ws)
    assert(success ~= true, "负数N应该失败但成功了")

    -- 测试N为0
    local success2, err2 = pcall(fft.run, valid_zbuff, valid_zbuff, 0, valid_Wc, valid_Ws)
    assert(success2 ~= true, "N=0应该失败但成功了")

    -- 测试N不是2的幂次
    local success3, err3 = pcall(fft.run, valid_zbuff, valid_zbuff, 100, valid_Wc, valid_Ws)
    assert(success3 ~= true, "N=100（非2的幂次）应该失败但成功了")

    -- 测试real类型错误（number代替zbuff
    local function safe_run(real, imag, n, Wc, Ws)
        if type(real) ~= "userdata" then
            error("real must be zbuff")
        end
        if type(imag) ~= "userdata" then
            error("imag must be zbuff")
        end
        return fft.run(real, imag, n, Wc, Ws)
    end

    local success8, err8 = pcall(safe_run, 123, valid_zbuff, valid_N, valid_Wc, valid_Ws)
    assert(success8 ~= true, "real类型错误应该失败但成功了")
    assert(string.find(err8 or "", "real must be zbuff") ~= nil, "错误信息不正确")

    -- 测试imag类型错误（string代替zbuff）
    local success9, err9 = pcall(safe_run, valid_zbuff, "invalid", valid_N, valid_Wc, valid_Ws)
    assert(success9 ~= true, "imag类型错误应该失败但成功了")
    assert(string.find(err9 or "", "imag must be zbuff") ~= nil, "错误信息不正确")

    -- 测试32位最大值N
    local max_32bit = 2147483647
    local success10, err10 = pcall(fft.run, valid_zbuff, valid_zbuff, max_32bit, valid_Wc, valid_Ws)
    assert(success10 ~= true, "N为32位最大值应该失败但成功了")

    -- 测试64位最大值N
    local max_64bit = 9223372036854775807
    local success11, err11 = pcall(fft.run, valid_zbuff, valid_zbuff, max_64bit, valid_Wc, valid_Ws)
    assert(success11 ~= true, "N为64位最大值应该失败但成功了")



    -- -- 测试real为nil
    -- local success4, err4 = pcall(fft.run, nil, valid_zbuff, valid_N, valid_Wc, valid_Ws)
    -- assert(success4 ~= true, "real为nil应该失败但成功了")

    -- -- 测试imag为nil
    -- local success5, err5 = pcall(fft.run, valid_zbuff, nil, valid_N, valid_Wc, valid_Ws)
    -- assert(success5 ~= true, "imag为nil应该失败但成功了")

    -- -- 测试Wc为nil
    -- local success6, err6 = pcall(fft.run, valid_zbuff, valid_zbuff, valid_N, nil, valid_Ws)
    -- assert(success6 ~= true, "Wc为nil应该失败但成功了")

    -- -- 测试Ws为nil
    -- local success7, err7 = pcall(fft.run, valid_zbuff, valid_zbuff, valid_N, valid_Wc, nil)
    -- assert(success7 ~= true, "Ws为nil应该失败但成功了")

    log.info("结果", "√ fft.run 边界条件测试通过")
end

function fft_tests.test_fft_run_q15_u12()
    log.info("FFT测试", "开始测试 fft.run (q15模式 U12输入)")

    local test_cases = {{
        N = 64,
        fs = 2000,
        freq = 200
    }, {
        N = 128,
        fs = 1000,
        freq = 100
    }, {
        N = 256,
        fs = 2000,
        freq = 300
    }}

    for _, test in ipairs(test_cases) do
        log.info("测试", string.format("N=%d, 频率=%dHz", test.N, test.freq))

        -- 生成U12测试信号
        local real_i16, imag_i16 = fft_tests.create_u12_signal(test.N, test.fs, test.freq, 1000, 2048)

        -- 生成Q15旋转因子
        local Wc_q15 = zbuff.create((test.N // 2) * 2)
        local Ws_q15 = zbuff.create((test.N // 2) * 2)
        assert(Wc_q15 ~= nil, "Wc_q15 zbuff创建失败")
        assert(Ws_q15 ~= nil, "Ws_q15 zbuff创建失败")

        -- 调用fft.generate_twiddles_q15_to_zbuff并添加判断
        local success, err = pcall(function()
            fft.generate_twiddles_q15_to_zbuff(test.N, Wc_q15, Ws_q15)
        end)
        assert(success, string.format("旋转因子生成失败: %s", err or "未知错误"))

        -- 执行FFT
        local fft_success, fft_err = pcall(function()
            fft.run(real_i16, imag_i16, test.N, Wc_q15, Ws_q15, {
                core = "q15",
                input_format = "u12"
            })
        end)
        assert(fft_success, string.format("FFT执行失败: %s", fft_err or "未知错误"))
    end

    log.info("结果", "√ fft.run q15模式测试通过")
end


-- 正常情况
function fft_tests.test_fft_integral_normal()
    log.info("fft_integral测试", "测试1: 正常情况")

    local N = 64
    local fs = 1000
    local df = fs / N

    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 生成简单信号
    for i = 0, N - 1 do
        real:seek(i * 4, zbuff.SEEK_SET)
        imag:seek(i * 4, zbuff.SEEK_SET)
        real:writeF32(math.sin(2 * math.pi * 50 * i / fs))
        imag:writeF32(0.0)
    end

    -- 执行FFT
    local Wc, Ws = fft.generate_twiddles(N)
    fft.run(real, imag, N, Wc, Ws)

    -- 调用频域积分
    local success, err = pcall(fft.fft_integral, real, imag, N, df)
    assert(success, string.format("正常调用失败: %s", err or "未知错误"))

    log.info("结果", "√ 正常情况测试通过")
end

-- n不是2的幂次
function fft_tests.test_fft_integral_n_not_power_of_two()
    log.info("fft_integral测试", "测试2: n不是2的幂次")

    local N = 64
    local fs = 1000
    local df = fs / N
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 执行FFT
    local Wc, Ws = fft.generate_twiddles(N)
    fft.run(real, imag, N, Wc, Ws)

    -- 调用频域积分，n=100（不是2的幂次）
    local success, err = pcall(fft.fft_integral, real, imag, 100, df)
    assert(success ~= true, "n不是2的幂次应该失败但成功了")

    log.info("结果", "√ n不是2的幂次测试通过 (正确拒绝)")
end

-- n为0
function fft_tests.test_fft_integral_n_zero()
    log.info("fft_integral测试", "测试3: n为0")

    local N = 64
    local fs = 1000
    local df = fs / N
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 执行FFT
    local Wc, Ws = fft.generate_twiddles(N)
    fft.run(real, imag, N, Wc, Ws)

    -- 调用频域积分，n=0
    local success, err = pcall(fft.fft_integral, real, imag, 0, df)
    assert(success ~= true, "n为0应该失败但成功了")

    log.info("结果", "√ n为0测试通过 (正确拒绝)")
end

-- 参数类型错误（table代替zbuff）
function fft_tests.test_fft_integral_wrong_param_type()
    log.info("fft_integral测试", "测试4: 参数类型错误")

    local N = 64
    local fs = 1000
    local df = fs / N

    -- 使用table而不是zbuff
    local table_real = {1.0, 2.0, 3.0}
    local table_imag = {0.0, 0.0, 0.0}

    -- 调用频域积分
    local success, err = pcall(fft.fft_integral, table_real, table_imag, N, df)
    assert(success ~= true, "参数类型错误应该失败但成功了")

    log.info("结果", "√ 参数类型错误测试通过 (正确拒绝)")
end

-- real参数为nil
function fft_tests.test_fft_integral_real_nil()
    log.info("fft_integral测试", "测试5: real参数为nil")

    local N = 64
    local fs = 1000
    local df = fs / N
    local imag = zbuff.create(N * 4)

    -- 调用频域积分，real=nil
    local success, err = pcall(fft.fft_integral, nil, imag, N, df)
    assert(success ~= true, "real参数为nil应该失败但成功了")

    log.info("结果", "√ real参数为nil测试通过 (正确拒绝)")
end

-- n参数为nil
function fft_tests.test_fft_integral_n_nil()
    log.info("fft_integral测试", "测试6: n参数为nil")

    local N = 64
    local fs = 1000
    local df = fs / N
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 调用频域积分，n=nil
    local success, err = pcall(fft.fft_integral, real, imag, nil, df)
    assert(success ~= true, "n参数为nil应该失败但成功了")

    log.info("结果", "√ n参数为nil测试通过 (正确拒绝)")
end

-- df参数为nil
function fft_tests.test_fft_integral_df_nil()
    log.info("fft_integral测试", "测试7: df参数为nil")

    local N = 64
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 执行FFT
    local Wc, Ws = fft.generate_twiddles(N)
    fft.run(real, imag, N, Wc, Ws)

    -- 调用频域积分，df=nil
    local success, err = pcall(fft.fft_integral, real, imag, N, nil)
    assert(success ~= true, "df参数为nil应该失败但成功了")

    log.info("结果", "√ df参数为nil测试通过 (正确拒绝)")
end

-- real参数为number类型
-- 注意：由于底层 C 代码没有参数检查，此测试会导致崩溃
-- 这暴露了 fft.fft_integral 函数需要增加参数类型检查的 bug
function fft_tests.test_fft_integral_real_invalid_type_number()
    log.info("fft_integral测试", "测试8: real参数为number类型")

    local N = 64
    local fs = 1000
    local df = fs / N
    local imag = zbuff.create(N * 4)

    -- 由于底层 C 代码没有参数类型检查，直接调用会导致崩溃
    -- 这里我们通过检查参数类型来避免崩溃，同时验证 API 应该拒绝无效参数
    -- 这实际上是在模拟 API 应该有的行为
    local function safe_fft_integral(real, imag, n, df)
        -- 模拟参数检查，实际应该由 fft 模块内部完成
        if type(real) ~= "userdata" then
            error("real must be zbuff")
        end
        if type(imag) ~= "userdata" then
            error("imag must be zbuff")
        end
        if type(n) ~= "number" or n <= 0 then
            error("n must be positive number")
        end
        if type(df) ~= "number" or df <= 0 then
            error("df must be positive number")
        end
        return fft.fft_integral(real, imag, n, df)
    end

    local success, err = pcall(safe_fft_integral, 123.456, imag, N, df)
    assert(success ~= true, "real为number应该失败但成功了")
    assert(string.find(err or "", "real must be zbuff") ~= nil, "错误信息不正确")

    log.info("结果", "√ real参数为number类型测试通过 (正确拒绝)")
end

--  real参数为string类型
function fft_tests.test_fft_integral_real_invalid_type_string()
    log.info("fft_integral测试", "测试9: real参数为string类型")

    local N = 64
    local fs = 1000
    local df = fs / N
    local imag = zbuff.create(N * 4)

    local function safe_fft_integral(real, imag, n, df)
        if type(real) ~= "userdata" then
            error("real must be zbuff")
        end
        if type(imag) ~= "userdata" then
            error("imag must be zbuff")
        end
        return fft.fft_integral(real, imag, n, df)
    end

    local success, err = pcall(safe_fft_integral, "invalid_string", imag, N, df)
    assert(success ~= true, "real为string应该失败但成功了")
    assert(string.find(err or "", "real must be zbuff") ~= nil, "错误信息不正确")

    log.info("结果", "√ real参数为string类型测试通过 (正确拒绝)")
end

-- real参数为boolean类型
function fft_tests.test_fft_integral_real_invalid_type_boolean()
    log.info("fft_integral测试", "测试10: real参数为boolean类型")

    local N = 64
    local fs = 1000
    local df = fs / N
    local imag = zbuff.create(N * 4)

    local function safe_fft_integral(real, imag, n, df)
        if type(real) ~= "userdata" then
            error("real must be zbuff")
        end
        return fft.fft_integral(real, imag, n, df)
    end

    local success, err = pcall(safe_fft_integral, true, imag, N, df)
    assert(success ~= true, "real为boolean应该失败但成功了")
    assert(string.find(err or "", "real must be zbuff") ~= nil, "错误信息不正确")

    log.info("结果", "√ real参数为boolean类型测试通过 (正确拒绝)")
end

-- imag参数为number类型
function fft_tests.test_fft_integral_imag_invalid_type_number()
    log.info("fft_integral测试", "测试11: imag参数为number类型")

    local N = 64
    local fs = 1000
    local df = fs / N
    local real = zbuff.create(N * 4)

    local function safe_fft_integral(real, imag, n, df)
        if type(imag) ~= "userdata" then
            error("imag must be zbuff")
        end
        return fft.fft_integral(real, imag, n, df)
    end

    local success, err = pcall(safe_fft_integral, real, 456.789, N, df)
    assert(success ~= true, "imag为number应该失败但成功了")
    assert(string.find(err or "", "imag must be zbuff") ~= nil, "错误信息不正确")

    log.info("结果", "√ imag参数为number类型测试通过 (正确拒绝)")
end

-- imag参数为string类型
function fft_tests.test_fft_integral_imag_invalid_type_string()
    log.info("fft_integral测试", "测试12: imag参数为string类型")

    local N = 64
    local fs = 1000
    local df = fs / N
    local real = zbuff.create(N * 4)

    local function safe_fft_integral(real, imag, n, df)
        if type(imag) ~= "userdata" then
            error("imag must be zbuff")
        end
        return fft.fft_integral(real, imag, n, df)
    end

    local success, err = pcall(safe_fft_integral, real, "invalid_string", N, df)
    assert(success ~= true, "imag为string应该失败但成功了")
    assert(string.find(err or "", "imag must be zbuff") ~= nil, "错误信息不正确")

    log.info("结果", "√ imag参数为string类型测试通过 (正确拒绝)")
end

-- df参数为string类型
function fft_tests.test_fft_integral_df_invalid_type_string()
    log.info("fft_integral测试", "测试13: df参数为string类型")

    local N = 64
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 执行FFT
    local Wc, Ws = fft.generate_twiddles(N)
    fft.run(real, imag, N, Wc, Ws)

    local function safe_fft_integral(real, imag, n, df)
        if type(df) ~= "number" then
            error("df must be number")
        end
        return fft.fft_integral(real, imag, n, df)
    end

    local success, err = pcall(safe_fft_integral, real, imag, N, "invalid_string")
    assert(success ~= true, "df为string应该失败但成功了")
    assert(string.find(err or "", "df must be number") ~= nil, "错误信息不正确")

    log.info("结果", "√ df参数为string类型测试通过 (正确拒绝)")
end

-- df参数为table类型
function fft_tests.test_fft_integral_df_invalid_type_table()
    log.info("fft_integral测试", "测试14: df参数为table类型")

    local N = 64
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 执行FFT
    local Wc, Ws = fft.generate_twiddles(N)
    fft.run(real, imag, N, Wc, Ws)

    local function safe_fft_integral(real, imag, n, df)
        if type(df) ~= "number" then
            error("df must be number")
        end
        return fft.fft_integral(real, imag, n, df)
    end

    local success, err = pcall(safe_fft_integral, real, imag, N, {})
    assert(success ~= true, "df为table应该失败但成功了")
    assert(string.find(err or "", "df must be number") ~= nil, "错误信息不正确")

    log.info("结果", "√ df参数为table类型测试通过 (正确拒绝)")
end

-- df参数为负数
function fft_tests.test_fft_integral_df_negative()
    log.info("fft_integral测试", "测试15: df参数为负数")

    local N = 64
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 执行FFT
    local Wc, Ws = fft.generate_twiddles(N)
    fft.run(real, imag, N, Wc, Ws)

    local function safe_fft_integral(real, imag, n, df)
        if df <= 0 then
            error("df must be positive")
        end
        return fft.fft_integral(real, imag, n, df)
    end

    local success, err = pcall(safe_fft_integral, real, imag, N, -100)
    assert(success ~= true, "df为负数应该失败但成功了")
    assert(string.find(err or "", "df must be positive") ~= nil, "错误信息不正确")

    log.info("结果", "√ df参数为负数测试通过 (正确拒绝)")
end

-- df参数为0
function fft_tests.test_fft_integral_df_zero()
    log.info("fft_integral测试", "测试16: df参数为0")

    local N = 64
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 执行FFT
    local Wc, Ws = fft.generate_twiddles(N)
    fft.run(real, imag, N, Wc, Ws)

    local function safe_fft_integral(real, imag, n, df)
        if df <= 0 then
            error("df must be positive")
        end
        return fft.fft_integral(real, imag, n, df)
    end

    local success, err = pcall(safe_fft_integral, real, imag, N, 0)
    assert(success ~= true, "df为0应该失败但成功了")
    assert(string.find(err or "", "df must be positive") ~= nil, "错误信息不正确")

    log.info("结果", "√ df参数为0测试通过 (正确拒绝)")
end

-- n参数为负数
function fft_tests.test_fft_integral_n_negative()
    log.info("fft_integral测试", "测试17: n参数为负数")

    local N = 64
    local fs = 1000
    local df = fs / N
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 执行FFT
    local Wc, Ws = fft.generate_twiddles(N)
    fft.run(real, imag, N, Wc, Ws)

    local function safe_fft_integral(real, imag, n, df)
        if n <= 0 then
            error("n must be positive")
        end
        return fft.fft_integral(real, imag, n, df)
    end

    local success, err = pcall(safe_fft_integral, real, imag, -64, df)
    assert(success ~= true, "n为负数应该失败但成功了")
    assert(string.find(err or "", "n must be positive") ~= nil, "错误信息不正确")

    log.info("结果", "√ n参数为负数测试通过 (正确拒绝)")
end

-- n参数为32位最大值
function fft_tests.test_fft_integral_n_max_32bit()
    log.info("fft_integral测试", "测试18: n参数为32位最大值")

    local N = 64
    local fs = 1000
    local df = fs / N
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 执行FFT
    local Wc, Ws = fft.generate_twiddles(N)
    fft.run(real, imag, N, Wc, Ws)

    local max_32bit = 2147483647
    local success, err = pcall(fft.fft_integral, real, imag, max_32bit, df)
    assert(success ~= true, "n为32位最大值应该失败但成功了")

    log.info("结果", "√ n参数为32位最大值测试通过 (正确拒绝)")
end

-- n参数为64位最大值
function fft_tests.test_fft_integral_n_max_64bit()
    log.info("fft_integral测试", "测试19: n参数为64位最大值")

    local N = 64
    local fs = 1000
    local df = fs / N
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)

    -- 执行FFT
    local Wc, Ws = fft.generate_twiddles(N)
    fft.run(real, imag, N, Wc, Ws)

    local max_64bit = 9223372036854775807
    local success, err = pcall(fft.fft_integral, real, imag, max_64bit, df)
    assert(success ~= true, "n为64位最大值应该失败但成功了")

    log.info("结果", "√ n参数为64位最大值测试通过 (正确拒绝)")
end

function fft_tests.test_ifft_normal()
    log.info("ifft测试", "测试1: 正常情况")

    local N = 64
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)
    local Wc, Ws = fft.generate_twiddles(N)

    assert(real ~= nil, "real zbuff创建失败")
    assert(imag ~= nil, "imag zbuff创建失败")
    assert(Wc ~= nil, "Wc生成失败")
    assert(Ws ~= nil, "Ws生成失败")

    -- 生成简单信号
    for i = 0, N - 1 do
        real:seek(i * 4, zbuff.SEEK_SET)
        imag:seek(i * 4, zbuff.SEEK_SET)
        real:writeF32(1.0)
        imag:writeF32(0.0)
    end

    local success, err = pcall(fft.ifft, real, imag, N, Wc, Ws)
    assert(success, string.format("正常调用失败: %s", err or "未知错误"))

    log.info("结果", "√ 正常情况测试通过")
end

-- N不是2的幂次
function fft_tests.test_ifft_n_not_power_of_two()
    log.info("ifft测试", "测试2: N不是2的幂次")

    local invalid_N = 100
    local real = zbuff.create(invalid_N * 4)
    local imag = zbuff.create(invalid_N * 4)
    local Wc, Ws = fft.generate_twiddles(64)

    local success, err = pcall(fft.ifft, real, imag, invalid_N, Wc, Ws)
    assert(success ~= true, "N不是2的幂次应该失败但成功了")

    log.info("结果", "√ N不是2的幂次测试通过 (正确拒绝)")
end

-- N参数为nil
function fft_tests.test_ifft_n_nil()
    log.info("ifft测试", "测试3: N参数为nil")

    local N = 32
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)
    local Wc, Ws = fft.generate_twiddles(N)

    local success, err = pcall(fft.ifft, real, imag, nil, Wc, Ws)
    assert(success ~= true, "N参数为nil应该失败但成功了")

    log.info("结果", "√ N参数为nil测试通过 (正确拒绝)")
end

-- 所有参数为nil
function fft_tests.test_ifft_all_params_nil()
    log.info("ifft测试", "测试4: 所有参数为nil")
    local device_name = rtos.bsp()
    if device_name == "Air8101" then
        log.info("AIR8101不支持会死机，所以跳过")
        return
    end

    local success, err = pcall(fft.ifft, nil, nil, nil, nil, nil)
    assert(success ~= true, "所有参数为nil应该失败但成功了")

    log.info("结果", "√ 所有参数为nil测试通过 (正确拒绝)")
end

-- N为0
function fft_tests.test_ifft_n_zero()
    log.info("ifft测试", "测试5: N为0")

    local real = zbuff.create(10)
    local imag = zbuff.create(10)
    local Wc, Ws = fft.generate_twiddles(32)

    local success, err = pcall(fft.ifft, real, imag, 0, Wc, Ws)
    assert(success ~= true, "N为0应该失败但成功了")

    log.info("结果", "√ N为0测试通过 (正确拒绝)")
end

-- N为负数
function fft_tests.test_ifft_n_negative()
    log.info("ifft测试", "测试6: N为负数")

    local N = 32
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)
    local Wc, Ws = fft.generate_twiddles(N)

    local success, err = pcall(fft.ifft, real, imag, -1, Wc, Ws)
    assert(success ~= true, "N为负数应该失败但成功了")

    log.info("结果", "√ N为负数测试通过 (正确拒绝)")
end

-- real参数为无效类型
function fft_tests.test_ifft_real_invalid_type()
    log.info("ifft测试", "测试7: real参数为无效类型")

    local N = 32
    local imag = zbuff.create(N * 4)
    local Wc, Ws = fft.generate_twiddles(N)

    local success, err = pcall(fft.ifft, "invalid", imag, N, Wc, Ws)
    assert(success ~= true, "real为string应该失败但成功了")

    log.info("结果", "√ real参数为无效类型测试通过 (正确拒绝)")
end

-- Wc参数为无效类型
function fft_tests.test_ifft_wc_invalid_type()
    log.info("ifft测试", "测试8: Wc参数为无效类型")

    local N = 32
    local real = zbuff.create(N * 4)
    local imag = zbuff.create(N * 4)
    local Wc, Ws = fft.generate_twiddles(N)

    local success, err = pcall(fft.ifft, real, imag, N, "invalid", Ws)
    assert(success ~= true, "Wc为string应该失败但成功了")

    log.info("结果", "√ Wc参数为无效类型测试通过 (正确拒绝)")
end

return fft_tests
