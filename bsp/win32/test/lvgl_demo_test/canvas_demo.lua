local canvas_demo = {}

local CANVAS_WIDTH  = 200
local CANVAS_HEIGHT = 150

function canvas_demo.demo()
    local obj = lvgl.obj_create(nil, nil);
    local rect_dsc = lvgl.draw_rect_dsc_t();
    lvgl.draw_rect_dsc_init(rect_dsc);
    rect_dsc.radius = 10;
    rect_dsc.bg_opa = lvgl.OPA_COVER;
    rect_dsc.bg_grad_dir = lvgl.GRAD_DIR_HOR;
    rect_dsc.bg_color = lvgl.COLOR_RED;
    rect_dsc.bg_grad_color = lvgl.COLOR_BLUE;
    rect_dsc.border_width = 2;
    rect_dsc.border_opa = lvgl.OPA_90;
    rect_dsc.border_color = lvgl.COLOR_WHITE;
    rect_dsc.shadow_width = 5;
    rect_dsc.shadow_ofs_x = 5;
    rect_dsc.shadow_ofs_y = 5;

    local label_dsc=lvgl.draw_label_dsc_t();
    lvgl.draw_label_dsc_init(label_dsc);
    -- label_dsc.color = lvgl.COLOR_YELLOW;
    label_dsc.color = lvgl.color_make(0xFF, 0xFF, 0x00)

    -- static lvgl.color_t cbuf[lvgl.CANVAS_BUF_SIZE_TRUE_COLOR(CANVAS_WIDTH, CANVAS_HEIGHT)];
    local cbuf = zbuff.create({CANVAS_WIDTH,CANVAS_HEIGHT,32})

    local canvas = lvgl.canvas_create(lvgl.scr_act(), nil);
    lvgl.canvas_set_buffer(canvas, cbuf, CANVAS_WIDTH, CANVAS_HEIGHT, lvgl.IMG_CF_TRUE_COLOR);
    lvgl.obj_align(canvas, nil, lvgl.ALIGN_CENTER, 0, 0);
    -- lvgl.canvas_fill_bg(canvas, lvgl.COLOR_SILVER, lvgl.OPA_COVER);
    -- lvgl.canvas_fill_bg(canvas, lvgl.color_make(0xC0, 0xC0, 0xC0), lvgl.OPA_COVER);
    lvgl.canvas_draw_rect(canvas, 70, 60, 100, 70, rect_dsc);

    lvgl.canvas_draw_text(canvas, 40, 20, 100, label_dsc, "Some text on text canvas", lvgl.LABEL_ALIGN_LEFT);

    -- /* Test the rotation. It requires an other buffer where the orignal image is stored.
    --     * So copy the current image to buffer and rotate it to the canvas */
    -- static lvgl.color_t cbuf_tmp[CANVAS_WIDTH * CANVAS_HEIGHT];
    local cbuf_tmp = zbuff.create({CANVAS_WIDTH,CANVAS_HEIGHT,32})
    -- memcpy(cbuf_tmp, cbuf, sizeof(cbuf_tmp));
    -- lvgl.img_dsc_t img;
    local img = lvgl.img_dsc_t()
    -- img.data = (void *)cbuf_tmp;
    img.data = cbuf_tmp;
    -- img.header.cf = lvgl.IMG_CF_TRUE_COLOR;
    -- img.header.w = CANVAS_WIDTH;
    -- img.header.h = CANVAS_HEIGHT;
    img.header_w = CANVAS_WIDTH;
    img.header_h = CANVAS_HEIGHT;

    -- lvgl.canvas_fill_bg(canvas, lvgl.COLOR_SILVER, lvgl.OPA_COVER);
    lvgl.canvas_fill_bg(canvas, lvgl.color_make(0xC0, 0xC0, 0xC0), lvgl.OPA_COVER);
    -- lvgl.canvas_transform(canvas, img, 30, lvgl.IMG_ZOOM_NONE, 0, 0, CANVAS_WIDTH / 2, CANVAS_HEIGHT / 2, true);
    lvgl.canvas_transform(canvas, img, 30, 256, 0, 0, CANVAS_WIDTH / 2, CANVAS_HEIGHT / 2, true);
    lvgl.scr_load(obj)
end

return canvas_demo
