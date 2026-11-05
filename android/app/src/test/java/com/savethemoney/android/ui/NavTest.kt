package com.savethemoney.android.ui

import com.savethemoney.android.ui.components.Tab
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class NavTest {
    @Test
    fun goAndBackKeepTheStack() {
        val nav = Nav(4)
        nav.go(5)
        nav.go(34)
        nav.back()
        assertEquals(listOf(4, 5), nav.stack)
        nav.back()
        nav.back() // la raíz no se quita
        assertEquals(4, nav.current)
        assertFalse(nav.canGoBack)
    }

    @Test
    fun tabAndResetStartANewStack() {
        val nav = Nav(1)
        nav.go(2)
        nav.tab(Tab.Metas)
        assertEquals(listOf(22), nav.stack)
        nav.go(23)
        nav.reset(1)
        assertEquals(listOf(1), nav.stack)
    }
}
