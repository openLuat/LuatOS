package org.luatos.toolkit.bean;

import static org.junit.Assert.*;

import org.junit.Test;
import org.nutz.lang.Files;

public class LuDocCommentTest {

    @Test
    public void test_lua_0() {
        String input = Files.read("input/cmt_lua_0.txt");
        String expec = Files.read("expec/cmt_lua_0.txt");

        LuDocComment dc = new LuDocComment(input);
        assertTrue(dc.isLuaSign());
        assertEquals(expec, dc.toString());
    }

    @Test
    public void test_multi_0() {
        String input = Files.read("input/cmt_c_multi_0.txt");
        String expec = Files.read("expec/cmt_c_multi_0.txt");

        LuDocComment dc = new LuDocComment(input);
        assertTrue(dc.isText());
        assertEquals(expec, dc.toString());
    }

    @Test
    public void test_multi_1() {
        String input = Files.read("input/cmt_c_multi_1.txt");
        String expec = Files.read("expec/cmt_c_multi_1.txt");

        LuDocComment dc = new LuDocComment(input);
        assertTrue(dc.isText());
        assertEquals(expec, dc.toString());
    }

    @Test
    public void test_single_0() {
        String input = Files.read("input/cmt_c_single_0.txt");
        String expec = Files.read("expec/cmt_c_single_0.txt");

        LuDocComment dc = new LuDocComment(input);
        assertTrue(dc.isText());
        assertEquals(expec, dc.toString());
    }

}
