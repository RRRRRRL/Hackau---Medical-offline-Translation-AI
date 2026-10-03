package com.hacku.fieldtalk.domain

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LanguageTest {
    @Test fun supportedPairsRequireEnglish() {
        assertTrue(Language.ENGLISH.canTranslateTo(Language.CHINESE))
        assertTrue(Language.RUSSIAN.canTranslateTo(Language.ENGLISH))
        assertFalse(Language.CHINESE.canTranslateTo(Language.RUSSIAN))
        assertFalse(Language.ENGLISH.canTranslateTo(Language.ENGLISH))
    }
}
