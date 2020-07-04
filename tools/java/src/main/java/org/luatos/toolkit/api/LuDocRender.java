package org.luatos.toolkit.api;

import java.io.OutputStream;

import org.luatos.toolkit.bean.LuDocument;

public interface LuDocRender {

    void render(LuDocument doc, OutputStream ops);

}
