package org.amnezia.core.parsers

import kotlinx.serialization.json.Json
import org.amnezia.core.models.ProtocolType
import org.amnezia.core.models.ServerProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WgQuickConfigParserTest {

    private val awg3Conf = """
        [Interface]
        Address = 10.8.1.10/32
        DNS = 1.1.1.1, 1.0.0.1
        PrivateKey = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=
        Jc = 4
        Jmin = 10
        Jmax = 50
        S1 = 115
        S2 = 36
        S3 = 37
        S4 = 9
        H1 = 1351553658-1920902942
        H2 = 1985824122-2031951811
        H3 = 2100088783-2119911158
        H4 = 2128748706-2129059843
        I1 = <r 2><b 0x8580>
        HeaderProtectionKey = ddddddddddddddddddddddddddddddddddddddddddd=
        ContentPaddingAddition = 0-64
        RekeyAfterTime = 120
        RekeyTimeout = 5
        RejectAfterTime = 180
        KeepaliveTimeout = 10
        MaxHandshakeAttempts = 18
        RandomTrailers = true
        DisableCookies = false

        [Peer]
        PublicKey = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb=
        PresharedKey = ccccccccccccccccccccccccccccccccccccccccccc=
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = 203.0.113.10:34316
        PersistentKeepalive = 22-30
    """.trimIndent()

    @Test
    fun parsesAwg3KeysAndKeepaliveRange() {
        val profile = WgQuickConfigParser.parse(awg3Conf)

        assertEquals(ProtocolType.AMNEZIA_WG, profile.protocolType)
        assertEquals("22-30", profile.persistentKeepalive)
        assertEquals(9, profile.s4)
        val awg3 = profile.awg3!!
        assertEquals(ServerProfile.AWG3_KEYS.size, awg3.size)
        assertEquals("ddddddddddddddddddddddddddddddddddddddddddd=", awg3["HeaderProtectionKey"])
        assertEquals("0-64", awg3["ContentPaddingAddition"])
        assertEquals("true", awg3["RandomTrailers"])
        assertEquals("false", awg3["DisableCookies"])
    }

    @Test
    fun awg3RoundtripKeepsEveryKeyInTemplateOrder() {
        val serialized = WgQuickConfigParser.serialize(WgQuickConfigParser.parse(awg3Conf))

        awg3Conf.lines()
            .filter { line -> ServerProfile.AWG3_KEYS.any { line.startsWith("$it =") } }
            .forEach { assertTrue("missing $it", serialized.contains(it)) }
        assertTrue(serialized.contains("PersistentKeepalive = 22-30"))

        val positions = ServerProfile.AWG3_KEYS.map { serialized.indexOf("\n$it = ") }
        assertTrue(positions.all { it >= 0 })
        assertEquals(positions.sorted(), positions)

        // A second pass is stable.
        assertEquals(serialized, WgQuickConfigParser.serialize(WgQuickConfigParser.parse(serialized)))
    }

    @Test
    fun awg2ConfHasNoAwg3SettingsAndKeepsDefaultKeepalive() {
        val awg2 = awg3Conf.lines()
            .filterNot { line -> ServerProfile.AWG3_KEYS.any { line.startsWith(it) } || line.startsWith("PersistentKeepalive") }
            .joinToString("\n")
        val profile = WgQuickConfigParser.parse(awg2)

        assertNull(profile.awg3)
        assertNull(profile.persistentKeepalive)
        val serialized = WgQuickConfigParser.serialize(profile)
        assertFalse(ServerProfile.AWG3_KEYS.any { serialized.contains(it) })
        assertTrue(serialized.contains("PersistentKeepalive = 25"))
    }

    @Test
    fun parseKeepalive() {
        assertEquals("25", ServerProfile.parseKeepalive("25"))
        assertEquals("22-30", ServerProfile.parseKeepalive(" 22 - 30 "))
        assertNull(ServerProfile.parseKeepalive("30-22"))
        assertNull(ServerProfile.parseKeepalive("abc"))
        assertNull(ServerProfile.parseKeepalive(""))
        assertNull(ServerProfile.parseKeepalive(null))
    }

    @Test
    fun profilesSavedBeforeAwg3StillDecode() {
        // Shape of a profile persisted by the previous release: no awg3, no persistentKeepalive.
        val legacy = """{"id":"1","name":"Old","host":"203.0.113.10","port":51820,"privateKey":"a","publicKey":"b","jc":4,"h1":"1"}"""
        val profile = Json { ignoreUnknownKeys = true }.decodeFromString<ServerProfile>(legacy)

        assertNull(profile.awg3)
        assertNull(profile.persistentKeepalive)
        assertEquals("25", profile.persistentKeepaliveValue)
    }
}
