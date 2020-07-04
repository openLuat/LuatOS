package org.luatos.toolkit.impl;

import static org.junit.Assert.*;

import org.junit.Test;
import org.luatos.toolkit.api.LuDocParser;
import org.luatos.toolkit.bean.LuDocument;
import org.nutz.json.Json;
import org.nutz.lang.Files;

public class CLuDocParserTest {

    @Test
    public void test_parse_0() {
        String input = Files.read("input/doc_parse_0.c");
        String expec = Files.read("expec/doc_parse_0.json");
        LuDocument expDoc = Json.fromJson(LuDocument.class, expec);

        LuDocParser pas = new CLuDocParser();
        LuDocument axuDoc = pas.parse(input);
        // System.out.println(Json.toJson(axuDoc,
        // JsonFormat.nice().setQuoteName(true)));
        assertNotNull(axuDoc);
        assertTrue(expDoc.equals(axuDoc));

    }

}
