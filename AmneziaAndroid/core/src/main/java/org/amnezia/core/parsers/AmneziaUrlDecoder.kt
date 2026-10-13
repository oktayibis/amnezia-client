package org.amnezia.core.parsers

import android.util.Base64
import org.amnezia.core.models.ProtocolType
import org.amnezia.core.models.ServerProfile
import org.json.JSONArray
import org.json.JSONObject

object AmneziaUrlDecoder {

    fun decode(input: String): ServerProfile {
        val trimmed = input.trim()
        var payload = trimmed
        if (payload.lowercase().startsWith("vpn://")) {
            payload = payload.substring(6)
                .replace("\u2013", "-")
                .replace("\u2014", "-")
                .replace(" ", "")
                .replace("\t", "")
                .replace("\r", "")
                .replace("\n", "")
        }

        // Try decoding Base64URL
        val data = decodeBase64URL(payload)
        if (data == null) {
            // Check if raw JSON
            if (trimmed.startsWith("{")) {
                val json = JSONObject(trimmed)
                return parseAmneziaJson(json)
            }
            // Check if wg-quick format
            if (trimmed.contains("[Interface]") && trimmed.contains("[Peer]")) {
                return WgQuickConfigParser.parse(trimmed)
            }
            throw IllegalArgumentException("Failed to decode base64 or recognize format")
        }

        // Decompress with Qt zlib
        val decompressed = ZlibHelper.decompress(data)
        val stringContent = String(decompressed, Charsets.UTF_8)

        // Try JSON first (standard Amnezia configs are JSON)
        val jsonObject = try {
            JSONObject(stringContent)
        } catch (e: Exception) {
            null
        }

        if (jsonObject != null) {
            return parseAmneziaJson(jsonObject)
        }

        if (stringContent.contains("[Interface]") && stringContent.contains("[Peer]")) {
            return WgQuickConfigParser.parse(stringContent)
        }

        throw IllegalArgumentException("Unrecognized configuration format")
    }

    fun encodeToUrl(profile: ServerProfile): String {
        val json = profileToAmneziaJson(profile)
        val jsonBytes = json.toString().toByteArray(Charsets.UTF_8)
        val compressed = ZlibHelper.compressQt(jsonBytes)
        val base64Url = encodeBase64URL(compressed)
        return "vpn://$base64Url"
    }

    private fun parseAmneziaJson(root: JSONObject): ServerProfile {
        val description = root.optString("description", "").trim()
        val rootHost = root.optString("hostName", "")

        val dnsList = mutableListOf<String>()
        val dns1 = root.optString("dns1", "")
        val dns2 = root.optString("dns2", "")
        if (dns1.isNotEmpty()) dnsList.add(dns1)
        if (dns2.isNotEmpty()) dnsList.add(dns2)

        val containers = root.optJSONArray("containers")
        if (containers == null || containers.length() == 0) {
            if (root.has("last_config")) {
                return parseLastConfig(root.get("last_config"), root, root, description, rootHost, dnsList)
            }
            throw IllegalArgumentException("Missing containers in Amnezia JSON")
        }

        var targetContainer: JSONObject? = null
        val defaultContainer = root.optString("defaultContainer", "")
        for (i in 0 until containers.length()) {
            val c = containers.getJSONObject(i)
            val name = c.optString("container", "")
            if (name == defaultContainer) {
                targetContainer = c
                break
            }
        }
        if (targetContainer == null) {
            for (i in 0 until containers.length()) {
                val c = containers.getJSONObject(i)
                val name = c.optString("container", "").lowercase()
                if (name.contains("awg") || name.contains("wireguard")) {
                    targetContainer = c
                    break
                }
            }
        }
        if (targetContainer == null) {
            targetContainer = containers.getJSONObject(0)
        }

        val containerType = targetContainer.optString("container", "amnezia-awg")
        val protocolKey = containerType.replace("amnezia-", "")

        var protocolConfig: JSONObject? = targetContainer.optJSONObject(protocolKey)
        if (protocolConfig == null) protocolConfig = targetContainer.optJSONObject("awg")
        if (protocolConfig == null) protocolConfig = targetContainer.optJSONObject("wireguard")
        if (protocolConfig == null) {
            val keys = targetContainer.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                val sub = targetContainer.optJSONObject(k)
                if (sub != null && sub.has("last_config")) {
                    protocolConfig = sub
                    break
                }
            }
        }

        val lastConfigObj = protocolConfig?.opt("last_config")
            ?: throw IllegalArgumentException("Missing last_config in container $containerType")

        return parseLastConfig(lastConfigObj, protocolConfig, root, description, rootHost, dnsList)
    }

    private fun parseLastConfig(
        lastConfigObj: Any,
        containerParams: JSONObject,
        root: JSONObject,
        description: String,
        rootHost: String,
        dnsList: List<String>
    ): ServerProfile {
        val configDict: JSONObject = when (lastConfigObj) {
            is String -> {
                val json = try {
                    JSONObject(lastConfigObj)
                } catch (e: Exception) {
                    null
                }
                if (json != null) {
                    json
                } else if (lastConfigObj.contains("[Interface]") && lastConfigObj.contains("[Peer]")) {
                    return WgQuickConfigParser.parse(lastConfigObj)
                } else {
                    throw IllegalArgumentException("Malformed last_config string")
                }
            }
            is JSONObject -> lastConfigObj
            else -> throw IllegalArgumentException("Malformed last_config")
        }

        fun findString(vararg keys: String): String? {
            for (k in keys) {
                if (configDict.has(k)) {
                    val v = configDict.optString(k, "").trim()
                    if (v.isNotEmpty()) return v
                }
            }
            return null
        }

        val clientPrivKey = findString("clientPrivKey", "client_priv_key", "client_private_key", "PrivateKey")
            ?: throw IllegalArgumentException("Missing client private key")
        val serverPubKey = findString("serverPubKey", "server_pub_key", "server_public_key", "PublicKey")
            ?: throw IllegalArgumentException("Missing server public key")

        var hostName = findString("hostName", "host_name", "server_ip", "serverIp", "Endpoint")
            ?: rootHost.ifEmpty { "127.0.0.1" }
        var port = 51820

        if (configDict.has("port")) {
            port = configDict.optInt("port", 51820)
        } else if (configDict.has("server_port")) {
            port = configDict.optInt("server_port", 51820)
        }

        if (hostName.contains(":") && !hostName.contains("[")) {
            val parts = hostName.split(":")
            if (parts.size == 2) {
                hostName = parts[0]
                parts[1].toIntOrNull()?.let { port = it }
            }
        }

        val rawIp = findString("clientIp", "client_ip", "Address") ?: "10.0.0.2/32"
        val clientIp = if (!rawIp.contains("/")) {
            if (rawIp.contains(":")) "$rawIp/128" else "$rawIp/32"
        } else rawIp
        val psk = findString("pskKey", "psk_key", "preshared_key", "PresharedKey")
        val mtu = configDict.optInt("mtu", 1280)

        // Read AWG obfuscation params from both containerParams and configDict
        fun getAwgInt(key: String): Int? {
            val raw = if (configDict.has(key)) configDict.opt(key)
            else if (containerParams.has(key)) containerParams.opt(key)
            else null

            if (raw == null) return null
            if (raw is Number) return raw.toInt()
            val str = raw.toString().trim()
            if (str.isEmpty()) return null
            if (str.contains("-")) {
                val minStr = str.split("-")[0].trim()
                return minStr.toIntOrNull()
            }
            return str.toIntOrNull()
        }

        // Kept verbatim: H1..H4 may be ranges ("123-456") and I1..I5 are tag strings in AWG 2.0.
        fun getAwgString(key: String): String? {
            val raw = if (configDict.has(key)) configDict.opt(key)
            else if (containerParams.has(key)) containerParams.opt(key)
            else null

            if (raw == null || raw == JSONObject.NULL) return null
            val str = if (raw is Number) raw.toLong().toString() else raw.toString().trim()
            return str.ifEmpty { null }
        }

        val jc = getAwgInt("Jc") ?: getAwgInt("jc")
        val jmin = getAwgInt("Jmin") ?: getAwgInt("jmin")
        val jmax = getAwgInt("Jmax") ?: getAwgInt("jmax")
        val s1 = getAwgInt("S1") ?: getAwgInt("s1")
        val s2 = getAwgInt("S2") ?: getAwgInt("s2")
        val s3 = getAwgInt("S3") ?: getAwgInt("s3")
        val s4 = getAwgInt("S4") ?: getAwgInt("s4")
        val h1 = getAwgString("H1") ?: getAwgString("h1")
        val h2 = getAwgString("H2") ?: getAwgString("h2")
        val h3 = getAwgString("H3") ?: getAwgString("h3")
        val h4 = getAwgString("H4") ?: getAwgString("h4")
        val i1 = getAwgString("I1") ?: getAwgString("i1")
        val i2 = getAwgString("I2") ?: getAwgString("i2")
        val i3 = getAwgString("I3") ?: getAwgString("i3")
        val i4 = getAwgString("I4") ?: getAwgString("i4")
        val i5 = getAwgString("I5") ?: getAwgString("i5")

        val isAwg = jc != null || jmin != null || jmax != null || s1 != null || s2 != null ||
                h1 != null || h2 != null || h3 != null || h4 != null
        val protocolType = if (isAwg) ProtocolType.AMNEZIA_WG else ProtocolType.WIREGUARD
        val serverName = if (description.isNotEmpty()) description else "Amnezia ($hostName)"

        return ServerProfile(
            name = serverName,
            protocolType = protocolType,
            host = hostName,
            port = port,
            clientIp = clientIp,
            dnsServers = dnsList.ifEmpty { listOf("1.1.1.1", "1.0.0.1") },
            publicKey = serverPubKey,
            privateKey = clientPrivKey,
            presharedKey = psk,
            allowedIps = listOf("0.0.0.0/0", "::/0"),
            jc = jc,
            jmin = jmin,
            jmax = jmax,
            s1 = s1,
            s2 = s2,
            s3 = s3,
            s4 = s4,
            h1 = h1,
            h2 = h2,
            h3 = h3,
            h4 = h4,
            i1 = i1,
            i2 = i2,
            i3 = i3,
            i4 = i4,
            i5 = i5,
            mtu = mtu
        )
    }

    private fun profileToAmneziaJson(profile: ServerProfile): JSONObject {
        val root = JSONObject()
        root.put("description", profile.name)
        root.put("hostName", profile.host)
        if (profile.dnsServers.isNotEmpty()) {
            root.put("dns1", profile.dnsServers[0])
            if (profile.dnsServers.size > 1) root.put("dns2", profile.dnsServers[1])
        }

        val isAwg = profile.protocolType == ProtocolType.AMNEZIA_WG
        val containerName = if (isAwg) "amnezia-awg" else "amnezia-wireguard"
        root.put("defaultContainer", containerName)

        val lastConfig = JSONObject()
        lastConfig.put("clientPrivKey", profile.privateKey)
        lastConfig.put("serverPubKey", profile.publicKey)
        lastConfig.put("clientIp", profile.clientIp)
        lastConfig.put("port", profile.port)
        lastConfig.put("hostName", profile.host)
        lastConfig.put("mtu", profile.mtu)
        profile.presharedKey?.let { lastConfig.put("pskKey", it) }

        if (isAwg) {
            profile.jc?.let { lastConfig.put("Jc", it) }
            profile.jmin?.let { lastConfig.put("Jmin", it) }
            profile.jmax?.let { lastConfig.put("Jmax", it) }
            profile.s1?.let { lastConfig.put("S1", it) }
            profile.s2?.let { lastConfig.put("S2", it) }
            profile.s3?.let { lastConfig.put("S3", it) }
            profile.s4?.let { lastConfig.put("S4", it) }
            profile.h1?.let { lastConfig.put("H1", it) }
            profile.h2?.let { lastConfig.put("H2", it) }
            profile.h3?.let { lastConfig.put("H3", it) }
            profile.h4?.let { lastConfig.put("H4", it) }
            profile.i1?.let { lastConfig.put("I1", it) }
            profile.i2?.let { lastConfig.put("I2", it) }
            profile.i3?.let { lastConfig.put("I3", it) }
            profile.i4?.let { lastConfig.put("I4", it) }
            profile.i5?.let { lastConfig.put("I5", it) }
        }

        val protoDict = JSONObject()
        protoDict.put("last_config", lastConfig)

        val containerObj = JSONObject()
        containerObj.put("container", containerName)
        containerObj.put(if (isAwg) "awg" else "wireguard", protoDict)

        val containers = JSONArray()
        containers.put(containerObj)
        root.put("containers", containers)

        return root
    }

    private fun decodeBase64URL(input: String): ByteArray? {
        var base64 = input
            .replace("-", "+")
            .replace("_", "/")
        val padLength = (4 - (base64.length % 4)) % 4
        if (padLength in 1..3) {
            base64 += "=".repeat(padLength)
        }

        return try {
            java.util.Base64.getDecoder().decode(base64)
        } catch (e: Throwable) {
            try {
                android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
            } catch (e2: Throwable) {
                null
            }
        }
    }

    private fun encodeBase64URL(bytes: ByteArray): String {
        return try {
            java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(bytes).trim()
        } catch (e: Throwable) {
            android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP or android.util.Base64.URL_SAFE)
                .replace("=", "")
                .trim()
        }
    }
}
