package com.luatos.toolkit.api;

import java.io.OutputStream;

import com.luatos.toolkit.LuatRenderingSetup;
import com.luatos.toolkit.bean.LuDocument;

public interface LuDocRender {

    boolean render(LuDocument doc, OutputStream ops, LuatRenderingSetup setup);

}
