# Release süreci

Yeni bir sürüm tag'i push edildiğinde [.github/workflows/release.yml](../.github/workflows/release.yml) çalışır, imzalı kurulum dosyalarını üretir ve bir GitHub Release olarak yayınlar.

```sh
git switch main && git pull
git tag v1.2.0
git push origin v1.2.0
```

- `v1.2.0` → normal release, `v1.2.0-beta.1` → pre-release.
- `versionName` tag'den gelir (`1.2.0`), `versionCode` = `major*1000000 + minor*1000 + patch` (`1002000`). Aynı temel sürümün pre-release'leri aynı `versionCode`'u paylaşır.

## Çıktılar

| Dosya | Nerede | Kimin için |
|---|---|---|
| `AWGConnect-<sürüm>-android.apk` | GitHub Release | Telefon/tablet kurulumu |
| `AWGConnect-<sürüm>-androidtv.apk` | GitHub Release | Android TV kurulumu |
| `AWGConnect-<sürüm>-macos.dmg` | GitHub Release | macOS kurulumu (aşağıdaki imza notuna bakın) |
| `SHA256SUMS.txt` | GitHub Release | Dosya doğrulama |
| `.aab` + R8 `mapping.txt` | Actions run → `android-store-bundles` artifact'i | Store yüklemesi / crash çözümleme |

## Gerekli GitHub secret'ları

Repo → Settings → Secrets and variables → Actions:

| Secret | İçerik |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i upload-keystore.jks` çıktısı |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore şifresi |
| `ANDROID_KEY_ALIAS` | Anahtar alias'ı (ör. `upload`) |
| `ANDROID_KEY_PASSWORD` | Anahtar şifresi |

| `MACOS_CERTIFICATE_P12_BASE64` | İmza sertifikası + özel anahtar: Anahtar Zinciri → sertifika → Dışa Aktar (.p12), sonra `base64 -i cert.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | .p12 dışa aktarılırken verilen şifre |
| `MACOS_APP_PROFILE_BASE64` | `com.oktayibis.awgconnect.mac` provisioning profile'ı, `base64 -i app.provisionprofile` |
| `MACOS_TUNNEL_PROFILE_BASE64` | `com.oktayibis.awgconnect.mac.tunnel` provisioning profile'ı, `base64 -i tunnel.provisionprofile` |
| `MACOS_NOTARY_KEY_BASE64`, `MACOS_NOTARY_KEY_ID`, `MACOS_NOTARY_ISSUER_ID` | *(İsteğe bağlı)* App Store Connect API anahtarı (.p8). Verilirse DMG notarize edilir; sadece Developer ID sertifikasıyla anlamlıdır. |

Secret'lar eksikse workflow hata vererek durur; imzasız dosya yayınlanmaz.

## macOS DMG

DMG'yi [scripts/macos-dmg.sh](../scripts/macos-dmg.sh) üretir: uygulamayı imzasız arşivler, sürümü tag'den yazar, framework'ü, tünel uzantısını ve uygulamayı verilen sertifika ve profillerle imzalar, sonra DMG'ye paketler. Aynı script yerelde de çalışır:

```sh
VERSION=1.2.0 SIGN_IDENTITY="Apple Development: …" \
APP_PROFILE=app.provisionprofile TUNNEL_PROFILE=tunnel.provisionprofile \
./scripts/macos-dmg.sh   # → dist/AWGConnect-1.2.0-macos.dmg
```

**İmza notu:** Şu an elimizde sadece **Apple Development** sertifikası ve geliştirme profilleri var.
- Bu DMG yalnızca profile kayıtlı Mac'lerde çalışır. Yeni bir Mac eklemek için developer.apple.com'da cihazı kaydedip profilleri yeniden oluşturun ve secret'ları güncelleyin.
- GitHub'dan indirilen dosyada Gatekeeper uyarı verir. Kurduktan sonra bir kez `xattr -dr com.apple.quarantine "/Applications/AWG Connect.app"` çalıştırın.
- Mac'te Xcode'un yönettiği profiller `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` altında durur. Geçerlilik tarihlerini script her build'de yazdırır; süresi dolmadan yenileyin.

Herkese açık dağıtım için **Developer ID** gerekir. Ancak macOS'ta app extension olarak paketlenmiş bir Network Extension yalnızca Mac App Store üzerinden dağıtılabilir; Developer ID ile dağıtmak için tüneli **system extension**'a çevirmek gerekir. Bu ayrı bir iştir.

> **Keystore'u kaybetmeyin.** GitHub'dan APK kuran kullanıcılar güncellemeleri ancak aynı anahtarla imzalanmış APK ile alabilir. Keystore dosyasını ve şifreleri bir parola yöneticisinde yedekleyin. Google Play'de Play App Signing kullanıldığında bu anahtar "upload key" olur ve kaybolursa Play Console'dan sıfırlanabilir; GitHub dağıtımı için böyle bir kurtarma yolu yoktur.

## Sonraki adımlar

- **iOS:** Dağıtım yolu (App Store / TestFlight) netleşince workflow'a bir job eklenecek.
- **macOS herkese açık dağıtım:** Mac App Store ya da Developer ID + system extension (yukarıdaki imza notuna bakın).
- **Store yüklemesi:** Google Play (`.aab`) ve App Store Connect yüklemesi hesaplar açılınca eklenecek.
