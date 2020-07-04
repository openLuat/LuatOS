package org.luatos.toolkit.bean;

import org.luatos.toolkit.Luats;
import org.nutz.lang.Strings;

public class FnParam extends FnReturn {

    private String name;

    public String getName() {
        return name;
    }

    public void setName(String name) {
        if (Strings.isBlank(name)) {
            this.name = null;
        } else {
            this.name = name;
        }
    }

    public boolean isName(String name) {
        return Luats.isSame(this.name, name);
    }

    public boolean isNameEndsWith(String name) {
        if (null != this.name) {
            return this.name.endsWith(name);
        }
        return false;
    }

    public String toString() {
        String str = type;
        if (str.endsWith(" *")) {
            str += name;
        } else {
            str += " " + name;
        }
        if (!Strings.isBlank(comment)) {
            str += "/* " + comment + " */";
        }
        return str;
    }

    public boolean equals(Object o) {
        if (o instanceof FnParam) {
            FnParam fp = (FnParam) o;

            if (!super.equals(fp)) {
                return false;
            }

            if (!Luats.isSame(this.name, fp.name))
                return false;

            return true;
        }
        return false;
    }

}
