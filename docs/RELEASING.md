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

Secret'lar eksikse workflow hata vererek durur; imzasız dosya yayınlanmaz.

> **Keystore'u kaybetmeyin.** GitHub'dan APK kuran kullanıcılar güncellemeleri ancak aynı anahtarla imzalanmış APK ile alabilir. Keystore dosyasını ve şifreleri bir parola yöneticisinde yedekleyin. Google Play'de Play App Signing kullanıldığında bu anahtar "upload key" olur ve kaybolursa Play Console'dan sıfırlanabilir; GitHub dağıtımı için böyle bir kurtarma yolu yoktur.

## Sonraki adımlar

- **iOS / macOS:** Apple Developer hesabı aktif olunca workflow'a `xcodebuild archive` + `-exportArchive` job'ı eklenecek (dağıtım sertifikası ve uygulama + tünel uzantısı provisioning profile'ları secret olarak).
- **Store yüklemesi:** Google Play (`.aab`) ve App Store Connect yüklemesi hesaplar açılınca eklenecek.
