package org.amnezia.core.parsers

import org.amnezia.core.models.ProtocolType
import org.amnezia.core.models.ServerProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AmneziaUrlDecoderTest {

    @Test
    fun testDecodeAmneziaJsonAndEncodeRoundtrip() {
        val sampleProfile = ServerProfile(
            name = "Frankfurt AmneziaWG",
            protocolType = ProtocolType.AMNEZIA_WG,
            host = "198.51.100.25",
            port = 51820,
            clientIp = "10.8.0.2/32",
            dnsServers = listOf("1.1.1.1", "1.0.0.1"),
            publicKey = "HIgoByamLBM63vLzGsm53+zR2yv8a0Q9G4v0vXgZ5xU=",
            privateKey = "yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=",
            presharedKey = "pskSecret1234567890abcdef=",
            allowedIps = listOf("0.0.0.0/0", "::/0"),
            jc = 4,
            jmin = 40,
            jmax = 70,
            s1 = 15,
            s2 = 30,
            h1 = "12345678",
            h2 = "87654321",
            h3 = "11223344",
            h4 = "44332211",
            mtu = 1280
        )

        // Encode to vpn:// URL
        val urlString = AmneziaUrlDecoder.encodeToUrl(sampleProfile)
        assertTrue(urlString.startsWith("vpn://"))

        // Decode from vpn:// URL
        val decodedProfile = AmneziaUrlDecoder.decode(urlString)

        assertEquals(sampleProfile.name, decodedProfile.name)
        assertEquals(ProtocolType.AMNEZIA_WG, decodedProfile.protocolType)
        assertEquals("198.51.100.25", decodedProfile.host)
        assertEquals(51820, decodedProfile.port)
        assertEquals(sampleProfile.privateKey, decodedProfile.privateKey)
        assertEquals(sampleProfile.publicKey, decodedProfile.publicKey)
        assertEquals(sampleProfile.presharedKey, decodedProfile.presharedKey)
        assertEquals("10.8.0.2/32", decodedProfile.clientIp)
        assertEquals(listOf("1.1.1.1", "1.0.0.1"), decodedProfile.dnsServers)
        assertEquals(1280, decodedProfile.mtu)

        // Check AWG Obfuscation parameters
        assertEquals(4, decodedProfile.jc)
        assertEquals(40, decodedProfile.jmin)
        assertEquals(70, decodedProfile.jmax)
        assertEquals(15, decodedProfile.s1)
        assertEquals(30, decodedProfile.s2)
        assertEquals("12345678", decodedProfile.h1)
        assertEquals("87654321", decodedProfile.h2)
        assertEquals("11223344", decodedProfile.h3)
        assertEquals("44332211", decodedProfile.h4)
    }

    @Test
    fun testDecodeRawJsonString() {
        val jsonStr = """
        {
          "containers": [
            {
              "container": "amnezia-wireguard",
              "wireguard": {
                "last_config": "{\"clientPrivKey\":\"AAAA...\",\"serverPubKey\":\"BBBB...\",\"clientIp\":\"10.0.0.5/32\",\"hostName\":\"vpn.example.com\",\"port\":51820}"
              }
            }
          ],
          "description": "Standard WireGuard Server",
          "dns1": "8.8.8.8"
        }
        """.trimIndent()

        val profile = AmneziaUrlDecoder.decode(jsonStr)
        assertEquals("Standard WireGuard Server", profile.name)
        assertEquals(ProtocolType.WIREGUARD, profile.protocolType)
        assertEquals("vpn.example.com", profile.host)
        assertEquals(51820, profile.port)
        assertEquals(listOf("8.8.8.8"), profile.dnsServers)
    }

    @Test
    fun testRealUserPastedUrl() {
        val realUrl = "vpn://AAALTXjatVZbT-M4FH7nV1TVvC0UO7ZzQcNIBco0MNP7LhQyqtLEbbNNk5BLoYP47-tL2qbCPLDSpCCffN9nn2P7HMevRzX21L04yt0gomlWP6s9Cow_rztLqNznOaMPQUG0IcPrEBFICNKJeQItDVhAs7BWP1bINSG3TGJqGGraiQYQtAg0IVTKEZdrEABgmoaJTjQILQtCSEylHEu5ZhrYNIDO5JoFiGVipJLbIvavaU379nVaAy8sKOYIwPJfPrpu6Uj39JlBdAwQs2e6D3Y6DwCv2gcC4rIGY5-YyEDGN6VjsQpKBn3I4A8Z8hFz43EGK6mV-8JJAtRsEImNUrJDueeQKEkxN6QrOTE7ZCg5MT9LRYVulk9Yns4CnoT1VyfisMNyz2Hvjjr7nPrxTqeVOlXaVXVI6pT5VtXhrU6RaBWdXcb3hzOs6rGcaRVC7yH8HiLvoBtPQriKsayRKAEHcBCVS1yFh9v9gaSKljEivQqWUSKjCpZxWhXMDcP4mfqTIMk4-ShxyYGG-J3uY5D42RmHJPJrN5IXBjTKbV_6WNqXneX9IH1yl3ded7y5mJs3eDT_uf53OVjlfTcpfhSrTLtvXeDzSjhyEBbNdvoNswEb-ntFkgbryZJupG6RP4HNjzAbd-lVv40fMEHjsUEG-bxveIvZYDb3v_9jrJebUazwlhTT_VD_N3BRTnKIRzvKaTpzPfrLcaKm76c0y2rnte1sTpHG8KvOkGFfegP7Z3MwnrDX49qXYeuy27kq35mox6bp5vSWbpj2U7N0ohuP9cHcYOkk3AvbfWE24fYQcpQlEzM1ZrIMYhbilsEtzCyLGW2hUx4KjOQ91ScBI_lg6vJnJBakquadyOY-_3ShMzc8et6issVlS2TL_h57lKZ8I3vFNAw8uRVg2rTSFRh9vyg6hh3AUe7dze_uV6fAa-Ewot5fF_1Z9_r6edE_F9tIs4WbUl_27objgsxo2zMf7tyH0ejZM8hTu7XR6XUSxfYm-9u_vV1AGC-bvHdT1qjd40m0K8rjmqhDJ2pFfhIHUc53CzcgMhtsexqQ4DOEEeR72mO3kSDLWa7fUpq4YbCmfOn5xldSeBFnecdd0fKQOBiqIlvlxfYzYVQLM9k5YcVEk4lwUx7s1fMqidOcwyK4PZot9zX4qfXZj5zRdE3Tw3L-1EaxM-3NiVSfTB60-NbyoJWCNM5jLw4na74MsfjaK29sWTGNaD5x5akgLwXiWFBeDfLUjTLufCIccHnhJ_UD4dthv_0NlKvdVUR_B-4Ju3Bq-25vR_LslldWn87cIswvP-y302VeGiR5Ob2hWO4a3NFRJi8yDfGrwPKSKhJ3B2-zTdxSDnKtfvR29B9c7L1y"

        val profile = AmneziaUrlDecoder.decode(realUrl)
        assertEquals("Server 1", profile.name)
        assertEquals(ProtocolType.AMNEZIA_WG, profile.protocolType)
        assertEquals("94.138.209.154", profile.host)
        assertEquals(34316, profile.port)
        assertEquals("htq0yLlsYOeDQH4Z453YY75RtgQ7chfRfgdGV7vkyTo=", profile.privateKey)
        assertEquals("0bA9rm0TGBuN7Ii1TtcWgWXm/0cE4lnec+BQfOFFwhQ=", profile.publicKey)
        assertEquals("OlYu5feHc8ZWaZTTwc75qHEy6eFpnoIysUdKKh11okA=", profile.presharedKey)
        assertEquals("10.8.1.6/32", profile.clientIp)
        assertEquals("1351553658-1920902942", profile.h1)
        assertEquals("1985824122-2031951811", profile.h2)
        assertEquals("2100088783-2119911158", profile.h3)
        assertEquals("2128748706-2129059843", profile.h4)
        assertEquals(37, profile.s3)
        assertEquals(9, profile.s4)
        assertEquals("<r 2><b 0x858000010001000000000669636c6f756403636f6d0000010001c00c000100010000105a00044d583737>", profile.i1)
        assertEquals(null, profile.i2)
    }
}
