package org.amnezia.core.storage

import android.content.Context
import android.content.SharedPreferences
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.amnezia.core.models.ServerProfile
import org.amnezia.core.parsers.AmneziaUrlDecoder

class ProfileStorage(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        // Profiles saved before AWG 2.0 support stored H1..H4 as numbers; lenient mode reads them into String.
        isLenient = true
    }

    @Synchronized
    fun loadProfiles(): List<ServerProfile> {
        val raw = prefs.getString(KEY_PROFILES, null) ?: return emptyList()
        val profiles = try {
            json.decodeFromString<List<ServerProfile>>(raw)
        } catch (e: Exception) {
            return emptyList()
        }
        if (prefs.getInt(KEY_SCHEMA_VERSION, 1) >= SCHEMA_VERSION) return profiles

        // v1 dropped AWG 2.0 fields (S3/S4, I1..I5) and truncated H1..H4 ranges on import;
        // re-parse each profile from its original config so existing servers work without re-importing.
        val migrated = profiles.map { profile ->
            val source = profile.rawConfig ?: return@map profile
            val reparsed = runCatching { AmneziaUrlDecoder.decode(source) }
                .recoverCatching { AmneziaUrlDecoder.decode("vpn://$source") }
                .getOrNull() ?: return@map profile
            reparsed.copy(
                id = profile.id,
                name = profile.name,
                pingMs = profile.pingMs,
                flagEmoji = profile.flagEmoji,
                rawConfig = source
            )
        }
        saveProfiles(migrated)
        prefs.edit().putInt(KEY_SCHEMA_VERSION, SCHEMA_VERSION).apply()
        return migrated
    }

    @Synchronized
    fun saveProfiles(profiles: List<ServerProfile>) {
        val raw = json.encodeToString(profiles)
        prefs.edit().putString(KEY_PROFILES, raw).apply()
    }

    @Synchronized
    fun addProfile(profile: ServerProfile) {
        val existing = loadProfiles().toMutableList()
        existing.removeAll { it.id == profile.id }
        existing.add(0, profile)
        saveProfiles(existing)

        if (getSelectedProfileId() == null) {
            selectProfile(profile.id)
        }
    }

    @Synchronized
    fun updateProfile(profile: ServerProfile) {
        val existing = loadProfiles().toMutableList()
        val index = existing.indexOfFirst { it.id == profile.id }
        if (index != -1) {
            existing[index] = profile
            saveProfiles(existing)
        }
    }

    @Synchronized
    fun deleteProfile(id: String) {
        val existing = loadProfiles().toMutableList()
        existing.removeAll { it.id == id }
        saveProfiles(existing)

        if (getSelectedProfileId() == id) {
            selectProfile(existing.firstOrNull()?.id)
        }
    }

    @Synchronized
    fun getSelectedProfileId(): String? {
        return prefs.getString(KEY_SELECTED_ID, null)
    }

    @Synchronized
    fun selectProfile(id: String?) {
        if (id != null) {
            prefs.edit().putString(KEY_SELECTED_ID, id).apply()
        } else {
            prefs.edit().remove(KEY_SELECTED_ID).apply()
        }
    }

    @Synchronized
    fun selectedProfile(): ServerProfile? {
        val all = loadProfiles()
        if (all.isEmpty()) return null
        val selectedId = getSelectedProfileId() ?: return all.firstOrNull()
        return all.firstOrNull { it.id == selectedId } ?: all.firstOrNull()
    }

    companion object {
        private const val PREFS_NAME = "amnezia_profiles_prefs"
        private const val KEY_PROFILES = "amnezia_server_profiles"
        private const val KEY_SELECTED_ID = "amnezia_selected_profile_id"
        private const val KEY_SCHEMA_VERSION = "amnezia_profiles_schema_version"
        private const val SCHEMA_VERSION = 2
    }
}
