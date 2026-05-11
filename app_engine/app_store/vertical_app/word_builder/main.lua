PROJECT = "WORD_BUILDER"
VERSION = "001.999.001"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 增加中文字体缓存大小
if sysfon then
    sysfon.config({hzfont_cache = 512})
end
-- 备选方案：如果上面的不行，尝试这个
if os and os.getenv then
    os.execute("sys.set_hzfont_cache 512")
end

require "word_builder_win"

sys.publish("OPEN_WORD_BUILDER_WIN")

sys.run()