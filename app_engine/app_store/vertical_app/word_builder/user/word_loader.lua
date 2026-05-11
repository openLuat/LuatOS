--[[
@module  word_loader
@summary 背单词应用 - 词库加载模块（从txt文件读取）
@version 1.0
@date    2026.04.21
]]

local word_loader = {}

local word_list = {}
local word_count = 0

local function load_words_from_file(file_path)
    local possible_paths = {
        file_path,
        "./" .. file_path,
        "../" .. file_path,
        "user/words.txt",
        "./user/words.txt",
        "../user/words.txt",
        "/app_store/word_builder/user/words.txt"
    }
    
    local f = nil
    local actual_path = ""
    
    for _, path in ipairs(possible_paths) do
        f = io.open(path, "r")
        if f then
            actual_path = path
            break
        end
    end
    
    if not f then
        log.error("word_loader", "Cannot open file: " .. file_path)
        log.error("word_loader", "Tried paths: " .. table.concat(possible_paths, ", "))
        return 0
    end
    
    log.info("word_loader", "Found words file at: " .. actual_path)
    
    word_list = {}
    word_count = 0
    
    for line in f:lines() do
        local word, meaning = line:match("^([^\t]+)\t(.+)")
        if word and meaning then
            word_count = word_count + 1
            table.insert(word_list, {
                word = word:trim(),
                meaning = meaning:trim(),
                phonetic = ""
            })
        end
    end
    
    f:close()
    return word_count
end

function word_loader.load(file_path)
    local count = load_words_from_file(file_path)
    log.info("word_loader", "Loaded " .. count .. " words from " .. file_path)
    return count
end

function word_loader.get_count()
    return word_count
end

function word_loader.get_word(index)
    if index >= 1 and index <= word_count then
        return word_list[index]
    end
    return nil
end

-- 打乱数组（洗牌算法）
function word_loader.shuffle(t)
    local result = {}
    for i = 1, #t do
        result[i] = t[i]
    end
    local n = #result
    for i = n, 2, -1 do
        local j = math.random(i)
        result[i], result[j] = result[j], result[i]
    end
    return result
end

function word_loader.get_random_words(count)
    local shuffled = word_loader.shuffle(word_list)
    local result = {}
    for i = 1, math.min(count, word_count) do
        result[i] = shuffled[i]
    end
    return result
end

function word_loader.get_all_words()
    local result = {}
    for i = 1, word_count do
        table.insert(result, word_list[i])
    end
    return result
end

return word_loader