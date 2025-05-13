local tabview_demo = {}

function tabview_demo.demo()
    --Create a Tab view object
    local tabview;
    tabview = lvgl.tabview_create(lvgl.scr_act(), nil);

    --Add 3 tabs (the tabs are page (lvgl.page) and can be scrolled
    local tab1 = lvgl.tabview_add_tab(tabview, "Tab 1");
    local tab2 = lvgl.tabview_add_tab(tabview, "Tab 2");
    local tab3 = lvgl.tabview_add_tab(tabview, "Tab 3");


    --Add content to the tabs
    local label = lvgl.label_create(tab1, nil);
    lvgl.label_set_text(label, 
[[This the first tab
If the content
of a tab
become too long
the it 
automatically
become
scrollable.]]);

    label = lvgl.label_create(tab2, nil);
    lvgl.label_set_text(label, "Second tab");

    label = lvgl.label_create(tab3, nil);
    lvgl.label_set_text(label, "Third tab");
end

return tabview_demo
