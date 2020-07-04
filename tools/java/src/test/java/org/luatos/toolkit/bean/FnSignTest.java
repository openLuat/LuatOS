package org.luatos.toolkit.bean;

import static org.junit.Assert.*;

import org.junit.Test;
import org.luatos.toolkit.api.FnSignParser;
import org.luatos.toolkit.impl.CFnSignParser;
import org.luatos.toolkit.impl.LuaDocFnSignParser;
import org.nutz.json.Json;
import org.nutz.lang.Files;

public class FnSignTest {

    @Test
    public void test_lua_cmt_fn_0() {
        String input = Files.read("input/lua_cmt_fn_0.txt");
        String expec = Files.read("expec/lua_cmt_fn_0.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        FnSignParser fsg = new LuaDocFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

    @Test
    public void test_lua_cmt_fn_1() {
        String input = Files.read("input/lua_cmt_fn_1.txt");
        String expec = Files.read("expec/lua_cmt_fn_1.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        FnSignParser fsg = new LuaDocFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

    @Test
    public void test_c_sign_fn_0() {
        String input = Files.read("input/c_sign_fn_0.txt");
        String expec = Files.read("expec/c_sign_fn_0.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        FnSignParser fsg = new CFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

    @Test
    public void test_c_sign_fn_1() {
        String input = Files.read("input/c_sign_fn_1.txt");
        String expec = Files.read("expec/c_sign_fn_1.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        FnSignParser fsg = new CFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

    @Test
    public void test_c_sign_fn_2() {
        String input = Files.read("input/c_sign_fn_2.txt");
        String expec = Files.read("expec/c_sign_fn_2.json");
        FnSign expFn = Json.fromJson(FnSign.class, expec);

        FnSignParser fsg = new CFnSignParser();
        FnSign axuFn = fsg.parse(input);
        assertTrue(axuFn.equals(expFn));
    }

}
