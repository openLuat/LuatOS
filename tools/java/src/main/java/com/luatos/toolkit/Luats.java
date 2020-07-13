package com.luatos.toolkit;

import java.util.Iterator;
import java.util.List;

import org.nutz.lang.Strings;

import com.luatos.toolkit.bean.LuComment;

public abstract class Luats {

    public static boolean isSame(Object o1, Object o2) {
        if (null != o1) {
            if (!o1.equals(o2)) {
                return false;
            }
        } else if (null != o2) {
            return false;
        }
        return true;
    }

    public static boolean isSameList(List<?> l1, List<?> l2) {
        if (null != l1) {
            if (null == l2)
                return false;

            if (l1.size() != l2.size())
                return false;

            Iterator<?> it1 = l1.iterator();
            Iterator<?> it2 = l2.iterator();

            while (it1.hasNext()) {
                Object o1 = it1.next();
                Object o2 = it2.next();
                if (!isSame(o1, o2)) {
                    return false;
                }
                return true;
            }

        } else if (null != l2) {
            return false;
        }
        return true;
    }

    public static void printEntities(List<Object> entities) {
        // 测试打印一下
        String hr = Strings.dup('-', 40);
        for (Object en : entities) {
            System.out.println(hr);
            if (en instanceof LuComment) {
                System.out.printf("- {%s}\n", ((LuComment) en).getType());
            } else {
                System.out.println("- <CFunction>");
            }
            System.out.println("-");
            System.out.println(en.toString());
        }
    }

}
