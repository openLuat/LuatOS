--[[
@module  vending_machine_win
@summary 智能售货机页面模块
@version 1.0
@date    2026.04.05
]]

local win_id = nil
local main_container, screen_container, info_panel, products_container, action_panel
local selected_info_label, message_label
local product_cards = {}
local selected_product_id = nil
local is_paying = false

local INIT_PRODUCTS = {
    { id = 1, name = "可乐", price = 3, stock = 5, icon = "/luadb/cola.png", initial_stock = 5 },
    { id = 2, name = "雪碧", price = 3, stock = 4, icon = "/luadb/sprite.png", initial_stock = 4 },
    { id = 3, name = "橙汁", price = 4, stock = 3, icon = "/luadb/orange_juice.png", initial_stock = 3 },
    { id = 4, name = "矿泉水", price = 2, stock = 5, icon = "/luadb/material_water.png", initial_stock = 5 },
    { id = 5, name = "薯片", price = 5, stock = 3, icon = "/luadb/potato_chips.png", initial_stock = 3 },
    { id = 6, name = "巧克力", price = 6, stock = 2, icon = "/luadb/chocolate.png", initial_stock = 2 },
    { id = 7, name = "饼干", price = 4, stock = 4, icon = "/luadb/biscuit.png", initial_stock = 4 },
    { id = 8, name = "能量饮", price = 7, stock = 2, icon = "/luadb/energy_drink.png", initial_stock = 2 }
}

local products = {}

local function read_png_wh(path)
    if not path or not path:lower():match("%.png$") then
        return nil, nil
    end
    if not io or not io.open then
        return nil, nil
    end
    local fd = io.open(path, "rb")
    if not fd then
        return nil, nil
    end
    local data = fd:read(24)
    fd:close()
    if not data or #data < 24 then
        return nil, nil
    end
    local b1 = string.byte(data, 17)
    local b2 = string.byte(data, 18)
    local b3 = string.byte(data, 19)
    local b4 = string.byte(data, 20)
    local w = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4

    b1 = string.byte(data, 21)
    b2 = string.byte(data, 22)
    b3 = string.byte(data, 23)
    b4 = string.byte(data, 24)
    local h = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
    if w <= 0 or h <= 0 then
        return nil, nil
    end
    return w, h
end

local function computeImageZoom(target_w, target_h, image_path)
    local img_w, img_h = read_png_wh(image_path)
    if not img_w or not img_h then
        return 256
    end
    local zoom = math.floor(math.min(target_w / img_w, target_h / img_h) * 256)
    if zoom < 64 then zoom = 64 end
    if zoom > 512 then zoom = 512 end
    return zoom
end

local function show_message(msg, is_error)
    if message_label then
        message_label:set_text(msg)
    end
end

local function get_product_by_id(id)
    for i, p in ipairs(products) do
        if p.id == id then
            return p
        end
    end
    return nil
end

local function update_selected_ui()
    if selected_product_id == nil then
        selected_info_label:set_text("未选中商品")
        return
    end
    local product = get_product_by_id(selected_product_id)
    if product and product.stock > 0 then
        selected_info_label:set_text(product.name .. " " .. product.price .. "元")
    elseif product and product.stock <= 0 then
        selected_info_label:set_text(product.name .. " (售罄)")
        selected_product_id = nil
    else
        selected_info_label:set_text("无效商品")
        selected_product_id = nil
    end
end

local function clear_selected()
    selected_product_id = nil
    update_selected_ui()
    for i, card in ipairs(product_cards) do
        card.container:set_color(0xFFFFFF)
        card.container:set_border_color(0xE0E0E0)
    end
end

local function apply_highlight()
    if selected_product_id == nil then return end
    for i, card in ipairs(product_cards) do
        if card.product_id == selected_product_id then
            local product = get_product_by_id(selected_product_id)
            if product and product.stock > 0 then
                card.container:set_color(0xFFFFE0)
                card.container:set_border_color(0xFBC531)
            else
                clear_selected()
            end
        end
    end
end

local function refresh_ui()
    for i, card in ipairs(product_cards) do
        local product = get_product_by_id(card.product_id)
        if product then
            card.stock_label:set_text(product.stock > 0 and "库存: " .. product.stock or "售罄")
            if product.stock <= 0 then
                card.container:set_color(0xCED6E0)
            else
                card.container:set_color(0xFFFFFF)
            end
        end
    end
    apply_highlight()
    update_selected_ui()
end

local function on_product_click(product_id)
    local product = get_product_by_id(product_id)
    if not product then return end
    
    if product.stock <= 0 then
        show_message("「" .. product.name .. "」已售罄，无法选中，请等待补货", true)
        return
    end
    
    if selected_product_id == product_id then
        clear_selected()
        show_message("已取消选中 " .. product.name, false)
    else
        clear_selected()
        selected_product_id = product_id
        apply_highlight()
        update_selected_ui()
        show_message("已选中：" .. product.name .. " " .. product.price .. "元，点击「扫码支付」购买", false)
    end
end

local function create_qr_modal(product)
    local modal = airui.container({
        parent = airui.screen,
        x = 0, y = 0, w = 480, h = 800,
        color = 0x000000,
        alpha = 0.75
    })
    
    local modal_content = airui.container({
        parent = modal,
        x = 70, y = 210, w = 340, h = 380,
        color = 0xFFFFFF,
        radius = 48
    })
    
    airui.label({
        parent = modal_content,
        x = 20, y = 8, w = 300, h = 24,
        text = "微信 / 支付宝 扫码支付",
        font_size = 18,
        color = 0x2C3E50,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    airui.label({
        parent = modal_content,
        x = 70, y = 35, w = 200, h = 24,
        text = product.price .. "元",
        font_size = 18,
        color = 0xE84118,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local qr_container = airui.container({
        parent = modal_content,
        x = 70, y = 62, w = 200, h = 200,
        color = 0xFFFFFF,
        radius = 28
    })
    
    local qr_zoom = computeImageZoom(200, 200, "/luadb/qrcode.png")
    airui.image({
        parent = qr_container,
        x = 0, y = 0, w = 200, h = 200,
        src = "/luadb/qrcode.png",
        zoom = qr_zoom
    })
    
    airui.label({
        parent = modal_content,
        x = 20, y = 270, w = 300, h = 18,
        text = "请使用手机扫描二维码完成支付",
        font_size = 12,
        color = 0x57606F,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local confirm_btn = airui.button({
        parent = modal_content,
        x = 20, y = 295, w = 140, h = 35,
        text = "我已支付完成",
        font_size = 14,
        color = 0x2ECC71,
        on_click = function()
            if is_paying then return end
            is_paying = true
            show_message("正在处理支付...", false)
            
            sys.timerStart(function()
                if product.stock <= 0 then
                    modal:destroy()
                    show_message("支付失败，" .. product.name .. " 已售罄", true)
                    is_paying = false
                    clear_selected()
                    refresh_ui()
                    return
                end
                
                product.stock = product.stock - 1
                refresh_ui()
                clear_selected()
                modal:destroy()
                show_message("支付成功！" .. product.name .. " 已出货，请取走商品。", false)
                
                if product.stock == 0 then
                    show_message("提示：" .. product.name .. " 已售罄，等待补货", false)
                end
                
                is_paying = false
            end, 600)
        end
    })
    
    local cancel_btn = airui.button({
        parent = modal_content,
        x = 180, y = 295, w = 140, h = 35,
        text = "取消",
        font_size = 14,
        color = 0xA4B0BE,
        on_click = function()
            modal:destroy()
            is_paying = false
        end
    })
    
    return modal
end

local function on_scan_pay_click()
    if is_paying then
        show_message("支付处理中，请稍后...", true)
        return
    end
    
    if selected_product_id == nil then
        show_message("请先点击商品选中要购买的商品", true)
        return
    end
    
    local product = get_product_by_id(selected_product_id)
    if not product then
        show_message("选中的商品无效，请重新选择", true)
        clear_selected()
        refresh_ui()
        return
    end
    
    if product.stock <= 0 then
        show_message("「" .. product.name .. "」已售罄，无法购买，请补货或选择其他商品", true)
        clear_selected()
        refresh_ui()
        return
    end
    
    create_qr_modal(product)
end

local function on_restock_click()
    for i, p in ipairs(products) do
        for j, init in ipairs(INIT_PRODUCTS) do
            if init.id == p.id then
                p.stock = init.initial_stock
                break
            end
        end
    end
    
    if selected_product_id ~= nil then
        local selected_prod = get_product_by_id(selected_product_id)
        if not selected_prod or selected_prod.stock <= 0 then
            clear_selected()
        else
            refresh_ui()
            show_message("补货完成！所有商品已补满，当前选中商品仍有库存", false)
            return
        end
    end
    
    refresh_ui()
    show_message("补货完成！所有商品库存已恢复至初始数量", false)
end

local function on_reset_click()
    for i, p in ipairs(products) do
        for j, init in ipairs(INIT_PRODUCTS) do
            if init.id == p.id then
                p.stock = init.initial_stock
                break
            end
        end
    end
    
    clear_selected()
    refresh_ui()
    show_message("售货机已重置，所有商品库存补满，请重新选择商品购买", false)
end

local function on_exit_click()
    if win_id then
        exwin.close(win_id)
    end
end

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x = 0, y = 0, w = 480, h = 800, color = 0x2F3640 })
    
    screen_container = airui.container({
        parent = main_container,
        x = 12, y = 16, w = 456, h = 680,
        color = 0xF0F3F8,
        radius = 28
    })
    
    info_panel = airui.container({
        parent = screen_container,
        x = 12, y = 12, w = 432, h = 100,
        color = 0x2C3E50,
        radius = 24
    })
    
    airui.label({
        parent = info_panel,
        x = 16, y = 12, w = 120, h = 30,
        text = "当前选中",
        font_size = 18,
        color = 0xFFFFFF
    })
    
    selected_info_label = airui.label({
        parent = info_panel,
        x = 140, y = 12, w = 276, h = 30,
        text = "未选中商品",
        font_size = 20,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    message_label = airui.label({
        parent = info_panel,
        x = 16, y = 52, w = 400, h = 40,
        text = "点击商品选中，然后点击「扫码支付」完成购买",
        font_size = 14,
        color = 0xFFFFFF
    })
    
    products_container = airui.container({
        parent = screen_container,
        x = 12, y = 124, w = 432, h = 544,
        color = 0xF0F3F8
    })
    
    local card_width = 200
    local card_height = 140
    local gap = 14
    local start_x = 14
    local start_y = 10
    
    for i, product in ipairs(INIT_PRODUCTS) do
        local row = math.floor((i - 1) / 2)
        local col = (i - 1) % 2
        local x = start_x + col * (card_width + gap)
        local y = start_y + row * (card_height + gap)
        
        local card = airui.container({
            parent = products_container,
            x = x, y = y, w = card_width, h = card_height,
            color = 0xFFFFFF,
            radius = 28,
            border_width = 1,
            border_color = 0xE0E0E0
        })
        
        local img_zoom = computeImageZoom(80, 50, product.icon)
        airui.image({
            parent = card,
            x = 60, y = 10, w = 80, h = 50,
            src = product.icon,
            zoom = img_zoom
        })
        
        airui.label({
            parent = card,
            x = 10, y = 65, w = 180, h = 24,
            text = product.name,
            font_size = 18,
            color = 0x2F3542,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        airui.label({
            parent = card,
            x = 10, y = 92, w = 90, h = 24,
            text = product.price .. "元",
            font_size = 20,
            color = 0xE84118,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        local stock_label = airui.label({
            parent = card,
            x = 100, y = 92, w = 90, h = 24,
            text = "库存: " .. product.stock,
            font_size = 13,
            color = 0x2F3542,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        local card_data = {
            container = card,
            product_id = product.id,
            stock_label = stock_label
        }
        
        card:set_on_click(function()
            on_product_click(product.id)
        end)
        
        table.insert(product_cards, card_data)
    end
    
    action_panel = airui.container({
        parent = main_container,
        x = 12, y = 706, w = 456, h = 78,
        color = 0x2C3E50,
        radius = 28
    })
    
    airui.button({
        parent = action_panel,
        x = 12, y = 13, w = 130, h = 52,
        text = "扫码支付",
        font_size = 20,
        color = 0x2ECC71,
        on_click = on_scan_pay_click
    })
    
    airui.button({
        parent = action_panel,
        x = 152, y = 13, w = 80, h = 52,
        text = "补货",
        font_size = 18,
        color = 0x57606F,
        on_click = on_restock_click
    })
    
    airui.button({
        parent = action_panel,
        x = 242, y = 13, w = 80, h = 52,
        text = "重置",
        font_size = 18,
        color = 0x57606F,
        on_click = on_reset_click
    })
    
    airui.button({
        parent = action_panel,
        x = 332, y = 13, w = 80, h = 52,
        text = "退出",
        font_size = 18,
        color = 0xE84118,
        on_click = on_exit_click
    })
end

local function on_create()
    products = {}
    for i, p in ipairs(INIT_PRODUCTS) do
        table.insert(products, {
            id = p.id,
            name = p.name,
            price = p.price,
            stock = p.stock,
            icon = p.icon,
            initial_stock = p.initial_stock
        })
    end
    
    create_ui()
    show_message("扫码支付售货机 | 点击商品选中，再扫码支付 | 「退出」按钮仅作展示", false)
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_VENDING_MACHINE_WIN", open_handler)
