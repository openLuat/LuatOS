package org.luatos.toolkit.impl;

import static org.junit.Assert.*;

import org.junit.Test;
import org.luatos.toolkit.api.LuDocParser;
import org.luatos.toolkit.bean.LuComment;
import org.luatos.toolkit.bean.LuDocument;
import org.nutz.lang.Files;

public class CLuDocParserTest {

    @Test
    public void testParse() {
        String input = Files.read("input/test_src_luat_lib_rtos.c");
        String expec = Files.read("expec/test_src_luat_lib_rtos.json");

        LuDocParser pas = new CLuDocParser();
        LuDocument doc = pas.parse(input);
        assertNotNull(doc);
    }

}
