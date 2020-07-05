package org.luatos.toolkit.api;

import java.io.IOException;

import org.luatos.toolkit.bean.LuatDocSet;

public interface LuDocSetRender {

    void render(LuatDocSet ds) throws IOException;

}
