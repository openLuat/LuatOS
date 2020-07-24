package com.luatos.toolkit.impl;

import static org.junit.Assert.*;

import org.junit.Test;
import org.nutz.json.Json;
import org.nutz.lang.Files;
import org.nutz.lang.Lang;
import org.nutz.lang.util.NutMap;

import com.luatos.toolkit.bean.LuHead;

public class TagParserTest {

    @Test
    public void test_head_0_NutMap() {
        String input = Files.read("input/head_0.txt");
        String expec = Files.read("expec/head_0.json");
        NutMap exMap = Json.fromJson(NutMap.class, expec);

        NutMapTagParser par = new NutMapTagParser();
        NutMap axMap = par.parse(input);
        assertTrue(Lang.equals(exMap, axMap));
    }

    @Test
    public void test_head_0_LuHead() {
        String input = Files.read("input/head_0.txt");
        String expec = Files.read("expec/head_0.json");
        LuHead exHed = Json.fromJson(LuHead.class, expec);

        LuHeadParser par = new LuHeadParser();
        LuHead axHed = par.parse(input);
        assertTrue(exHed.equals(axHed));
    }

}
