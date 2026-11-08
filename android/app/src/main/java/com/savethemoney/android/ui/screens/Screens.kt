package com.savethemoney.android.ui.screens

import androidx.compose.runtime.Composable
import com.savethemoney.android.ui.Nav

const val SCREEN_COUNT = 34

/** Pinta la pantalla [number] del diseño. */
@Composable
fun ScreenFor(number: Int, nav: Nav) {
    when (number) {
        1 -> Pantalla01(nav); 2 -> Pantalla02(nav); 3 -> Pantalla03(nav); 4 -> Pantalla04(nav)
        5 -> Pantalla05(nav); 6 -> Pantalla06(nav); 7 -> Pantalla07(nav); 8 -> Pantalla08(nav)
        9 -> Pantalla09(nav); 10 -> Pantalla10(nav); 11 -> Pantalla11(nav); 12 -> Pantalla12(nav)
        13 -> Pantalla13(nav); 14 -> Pantalla14(nav); 15 -> Pantalla15(nav); 16 -> Pantalla16(nav)
        17 -> Pantalla17(nav); 18 -> Pantalla18(nav); 19 -> Pantalla19(nav); 20 -> Pantalla20(nav)
        21 -> Pantalla21(nav); 22 -> Pantalla22(nav); 23 -> Pantalla23(nav); 24 -> Pantalla24(nav)
        25 -> Pantalla25(nav); 26 -> Pantalla26(nav); 27 -> Pantalla27(nav); 28 -> Pantalla28(nav)
        29 -> Pantalla29(nav); 30 -> Pantalla30(nav); 31 -> Pantalla31(nav); 32 -> Pantalla32(nav)
        33 -> Pantalla33(nav); 34 -> Pantalla34(nav)
        // Fuera del diseño: el formulario de aportar a una meta.
        35 -> Pantalla35(nav)
    }
}

