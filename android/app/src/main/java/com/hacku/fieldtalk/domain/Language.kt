package com.hacku.fieldtalk.domain

import java.util.Locale

enum class Language(val code: String, val displayName: String, val locale: Locale) {
    ENGLISH("en", "English", Locale.US),
    CHINESE("zh", "简体中文", Locale.SIMPLIFIED_CHINESE),
    RUSSIAN("ru", "Русский", Locale("ru", "RU"));

    fun validTargets(): List<Language> = when (this) {
        ENGLISH -> listOf(CHINESE, RUSSIAN)
        CHINESE, RUSSIAN -> listOf(ENGLISH)
    }

    fun canTranslateTo(target: Language): Boolean = target in validTargets()
}
