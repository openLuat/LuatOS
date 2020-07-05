package org.luatos.toolkit.impl;

import java.io.BufferedWriter;
import java.io.OutputStream;
import java.io.OutputStreamWriter;

import org.luatos.toolkit.api.LuDocRender;
import org.luatos.toolkit.bean.LuDocument;
import org.nutz.json.Json;
import org.nutz.json.JsonFormat;
import org.nutz.lang.Streams;

public class JsonLuDocRender implements LuDocRender {

    @Override
    public void render(LuDocument doc, OutputStream ops) {
        BufferedWriter br = Streams.buffw(new OutputStreamWriter(ops));

        try {
            Json.toJson(br, doc, JsonFormat.nice());
        }
        finally {
            Streams.safeFlush(br);
        }
    }

}
