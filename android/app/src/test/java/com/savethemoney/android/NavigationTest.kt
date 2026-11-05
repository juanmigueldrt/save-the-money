package com.savethemoney.android

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NavigationTest {
    private val design = Design.parse(File("src/main/assets/screens.json").readText())

    @Test
    fun allScreensAndColorsLoad() {
        assertEquals(34, design.screens.size)
        assertEquals(design.light.keys, design.dark.keys)
        assertTrue(design.light.size >= 41)
    }

    @Test
    fun everyLinkResolvesAndEveryScreenIsReachable() {
        wireNavigation(design) // lanza si algún enlace no encuentra su capa
        val reachable = mutableSetOf(1)
        val queue = ArrayDeque(listOf(1))
        while (queue.isNotEmpty()) {
            val n = queue.removeFirst()
            design.screen(n).descendants().mapNotNull { it.action }.forEach { a ->
                val to = when (a) { is Action.Go -> a.screen; is Action.Tab -> a.screen; is Action.Reset -> a.screen; Action.Back -> null }
                if (to != null && reachable.add(to)) queue += to
            }
        }
        assertEquals((1..34).toSet() - reachable, emptySet<Int>())
    }
}
