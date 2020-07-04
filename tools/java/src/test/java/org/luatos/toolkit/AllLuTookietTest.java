package org.luatos.toolkit;

import org.junit.runner.RunWith;
import org.junit.runners.Suite;
import org.luatos.toolkit.bean.LuAllBeanTest;
import org.luatos.toolkit.impl.LuAllParserTest;

@RunWith(Suite.class)
@Suite.SuiteClasses({LuAllBeanTest.class, LuAllParserTest.class})
public class AllLuTookietTest {}
