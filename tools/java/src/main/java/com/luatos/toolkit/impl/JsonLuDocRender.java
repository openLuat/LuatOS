package com.luatos.toolkit.impl;

import java.io.BufferedWriter;
import java.io.OutputStream;
import java.io.OutputStreamWriter;

import org.nutz.json.Json;
import org.nutz.json.JsonFormat;
import org.nutz.lang.Streams;

import com.luatos.toolkit.LuatRenderingSetup;
import com.luatos.toolkit.api.LuDocRender;
import com.luatos.toolkit.bean.LuDocument;

public class JsonLuDocRender implements LuDocRender {

    @Override
    public boolean render(LuDocument doc, OutputStream ops, LuatRenderingSetup setup) {
        BufferedWriter br = Streams.buffw(new OutputStreamWriter(ops));

        try {
            Json.toJson(br, doc, JsonFormat.nice());
            return true;
        }
        finally {
            Streams.safeFlush(br);
        }
    }

}
