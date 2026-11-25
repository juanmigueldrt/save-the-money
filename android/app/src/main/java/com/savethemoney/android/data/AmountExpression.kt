package com.savethemoney.android.data

import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode

/**
 * Importe escrito como una cuenta sencilla: "12,50+3×2" o "100/3" (AmountExpression.swift de STMCore).
 * Admite + − × ÷ (y también - * x / :) y paréntesis. Cada número se lee con [Money.parse],
 * así que "1.234,56" y "12.50" valen igual que en el resto de la app.
 * El resultado se redondea al céntimo (la mitad hacia arriba).
 */
object AmountExpression {
    /** Calcula el importe en céntimos, o nulo si el texto no es una cuenta válida (o divide entre cero). */
    fun evaluate(text: String): Long? {
        val tokens = tokenize(text) ?: return null
        if (tokens.isEmpty()) return null
        val parser = Parser(tokens)
        val value = parser.expression() ?: return null
        if (!parser.isAtEnd) return null
        val cents = value.movePointRight(2).setScale(0, RoundingMode.HALF_UP)
        if (cents.abs() >= BigDecimal("9e15")) return null
        return cents.toLong()
    }

    /** true si el texto tiene alguna operación (para enseñar el resultado debajo del campo). */
    fun hasOperation(text: String): Boolean {
        val tokens = tokenize(text) ?: return false
        // Un "-" al principio es sólo el signo.
        return tokens.drop(1).any { it is Token.Op } || tokens.any { it == Token.Open }
    }

    internal sealed interface Token {
        data class Number(val value: BigDecimal) : Token
        data class Op(val op: Char) : Token
        data object Open : Token
        data object Close : Token
    }

    internal fun tokenize(text: String): List<Token>? {
        val tokens = mutableListOf<Token>()
        val number = StringBuilder()
        fun flush(): Boolean {
            if (number.isEmpty()) return true
            val minor = Money.parse(number.toString())
            number.clear()
            tokens += Token.Number(BigDecimal.valueOf(minor ?: return false).movePointLeft(2))
            return true
        }
        val cleaned = text.replace("€", "").replace("EUR", "")
        for (ch in cleaned) {
            val token: Token? = when (ch) {
                in '0'..'9', ',', '.' -> { number.append(ch); continue }
                ' ', '\u00A0', '\u202F' -> continue
                '+' -> Token.Op('+')
                '-', Money.MINUS -> Token.Op('-')
                '*', '×', 'x', 'X' -> Token.Op('*')
                '/', '÷', ':' -> Token.Op('/')
                '(' -> Token.Open
                ')' -> Token.Close
                else -> null
            }
            if (token == null || !flush()) return null
            tokens += token
        }
        return if (flush()) tokens else null
    }

    /** Precedencia normal: × ÷ antes que + −. */
    private class Parser(val tokens: List<Token>) {
        var index = 0
        val isAtEnd get() = index == tokens.size
        private val peek get() = tokens.getOrNull(index)

        fun expression(): BigDecimal? {
            var value = term() ?: return null
            while (true) {
                val op = (peek as? Token.Op)?.op?.takeIf { it == '+' || it == '-' } ?: return value
                index++
                val rhs = term() ?: return null
                value = if (op == '+') value + rhs else value - rhs
            }
        }

        fun term(): BigDecimal? {
            var value = factor() ?: return null
            while (true) {
                val op = (peek as? Token.Op)?.op?.takeIf { it == '*' || it == '/' } ?: return value
                index++
                val rhs = factor() ?: return null
                value = if (op == '*') value * rhs else {
                    if (rhs.signum() == 0) return null
                    value.divide(rhs, MathContext.DECIMAL64)
                }
            }
        }

        fun factor(): BigDecimal? = when (val t = peek) {
            is Token.Number -> { index++; t.value }
            Token.Open -> {
                index++
                val value = expression()
                if (value == null || peek != Token.Close) null else { index++; value }
            }
            is Token.Op -> when (t.op) {
                '-' -> { index++; factor()?.negate() }
                '+' -> { index++; factor() }
                else -> null
            }
            else -> null
        }
    }
}
