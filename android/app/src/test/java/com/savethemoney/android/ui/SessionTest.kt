package com.savethemoney.android.ui

import com.savethemoney.android.data.AppError
import com.savethemoney.android.data.Backend
import com.savethemoney.android.data.InMemoryBackend
import com.savethemoney.android.data.InMemoryFinance
import com.savethemoney.android.data.Username
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SessionTest {
    @Test
    fun signOutWithoutNetworkEndsSignedOut() = runBlocking {
        val memory = InMemoryBackend()
        memory.signUp(Username.parse("ana").getOrThrow(), "secreto123", null)
        // Como SupabaseBackend: borra la sesión local aunque falle la llamada al servidor.
        val offline = object : Backend by memory {
            override suspend fun signOut() {
                try {
                    throw AppError.Network
                } finally {
                    memory.signOut()
                }
            }
        }
        val session = Session(offline, InMemoryFinance(), isDemo = true)
        session.refresh()

        session.signOut()

        assertEquals(Session.State.SignedOut, session.state)
        assertNull(offline.currentUserId())
        session.refresh()
        assertEquals(Session.State.SignedOut, session.state)
    }
}
