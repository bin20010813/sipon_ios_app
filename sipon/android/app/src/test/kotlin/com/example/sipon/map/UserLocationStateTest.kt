package com.example.sipon.map

import org.junit.Assert.*
import org.junit.Test

class UserLocationStateTest {
    private val now = 500_000_000_000L
    private val buttonFix = Gcj02Point(113.282, 23.125)

    @Test fun buttonFixDisplaysWithoutWaitingForNativeGpsAndIsNotConvertedAgain() {
        val state = UserLocationState()
        assertNull(state.current(now))
        state.update(buttonFix, now, now)
        assertEquals(buttonFix, state.current(now))
    }

    @Test fun delayedNativeCacheCannotReplaceButtonFixButNewFixCan() {
        val state = UserLocationState()
        val other = Gcj02Point(113.283, 23.126)
        state.update(buttonFix, now, now)
        state.update(other, now - 1, now)
        assertEquals(buttonFix, state.current(now))
        state.update(other, now + 1, now + 1)
        assertEquals(other, state.current(now + 1))
    }

    @Test fun staleFutureAndInvalidFixesAreNotDisplayed() {
        val state = UserLocationState()
        state.update(buttonFix, now - 121_000_000_000L, now)
        state.update(buttonFix, now + 1, now)
        state.update(Gcj02Point(Double.NaN, 23.125), now, now)
        assertNull(state.current(now))
        state.update(buttonFix, now, now)
        assertNull(state.current(now + 121_000_000_000L))
        state.clear()
        assertNull(state.current(now))
    }
}
