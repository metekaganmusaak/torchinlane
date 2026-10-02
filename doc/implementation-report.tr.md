# Torchinlane 0.2.0 — uygulama raporu

Bu çalışma, mevcut Dart/Fastlane CLI yapısını koruyarak çok dilli mağaza içerik
ve görsel yönetimi, yerel GUI, credential doğrulaması, imzalama kurulumu ve CI
üretimi ekledi. Bu rapor kod değişikliklerini ve doğrulamaları açıklar. GitHub gönderimi veya
gerçek Apple/Google mağaza yayını yapılmadı. Pub.dev paket sürümü 0.2.0’dır;
paket yayını, uygulamanın mağazaya yayımlanmasından ayrı bir işlemdir.

## Düzeltilen hatalar

- **iOS production release notes:** Notlar `deliver` parametresine verilmesine
  rağmen `skip_metadata: true` yüzünden yüklenmiyordu. Not bulunan akışta metadata
  yüklemesi açıldı; boş notlarda atlanıyor. Sadece not yükleyen geçici metadata
  dizini, uygulamanın başka Fastlane metinlerinin yanlışlıkla yüklenmesini önlüyor.
- **İlk Apple sürümü:** Apple'ın ilk sürümünde What's New bulunmuyor. Canlı
  sürümün varlığı kontrol edilerek ilk sürümde bu alan atlanıyor; yerel notlar
  silinmiyor. Bağımsız eski not güncelleme komutu bu durumu açık hata ile bildiriyor.
- **TestFlight lokalizasyonları:** Tek kaynak dil yerine `localized_build_info`
  ile çok dilli What to Test gönderiliyor. Not varsa build processing bekleniyor;
  30 dakika sınırı var. `--with-store` kullanıldığında GUI'de yazılan JSON notları
  da bu akışa dahil ediliyor.
- **Google not güncelleme hedefi:** Yalnızca internal track'e yazan akışa track ve
  mevcut version code seçimi eklendi. Not-only yüklemede eski dillerin notları
  yeni metinlerle birleştiriliyor; sürüm kodları, release status ve diğer
  release'ler korunuyor.
- **Yanlış dil kodları:** Apple Bangla `bn-BD`, Google Hebrew `iw-IL` olarak
  düzeltildi; Apple'ın desteklemediği Filipino atlanıyor. Bölgesel varyantlar ayrı.
- **Sessiz metin kesme:** 500/4000 karakterden sonrası kesilmiyor; kullanıcıya
  hata gösteriliyor. Apple keywords alanı ayrıca 100 UTF-8 byte sınırına göre
  kontrol ediliyor. Diğer metinlerin Unicode code point uzunluğu sayılıyor.
- **Credential ve changelog yolları:** Sabit .p8/changelog yolları yerine YAML
  ayarları ve CI environment override'ları kullanılıyor. Üretilen build.sh de
  yapılandırılmış changelog dizinini kullanıyor.
- **Android screenshot:** ADB çıktısı artık binary olarak okunuyor; PNG verisini
  String'den byte listesine çevirmeye çalışan hatalı kod kaldırıldı.
- **YAML ve template metinleri:** Kolon/tırnak içeren uygulama isimleri ve sayısal
  görünen takım ID'leri quoted YAML ile korunuyor. Shell değişkenlerinde özel
  karakterler kaçırılıyor; API ID'leri Ruby'ye kod olarak gömülmüyor.
- **Dokümantasyon yanlışlığı:** Draft Google internal release'in test kullanıcısına
  sunulduğu iddiası kaldırıldı. Draft build sunulmaz; serving için explicit
  `--release-status completed` veya kademeli rollout gerekir.
- Geçici yükleme dizinleri temizleniyor, HTTP isteklerinde timeout var,
  AI modeli environment ile seçiliyor ve HTTP client'lar kapatılıyor.

## Yeni mağaza içerik altyapısı

Yeni `store` komutu init, locales, validate, export, translate, push ve pull
alt komutlarını ve API gerektirmeyen `prompt` komutunu içeriyor. Metinler `store/ios/<locale>.json` ve
`store/android/<locale>.json` dosyalarında; görseller platform/dil/cihaz grubuna
ayrılmış klasörlerde saklanıyor.

Boş alanlar yükleme dosyalarına eklenmiyor; mevcut mağaza metni silinmiyor.
Metadata, görsel ve release notes ayrı scope'larla gönderilebiliyor. Görsellerin
formatı, çözünürlüğü, sayısı ve transparan pikselleri önceden kontrol ediliyor.
Fastlane için gereken staging düzeni otomatik oluşturuluyor ve yükleme bitince
siliniyor. Google görselleri checksum ile senkronize ediyor. Apple screenshot
replacement açıkça seçildiğinde ilgili dillerin bütün mevcut cihaz screenshot
setlerini temizleyebilir; bunun davranışı GUI ve belgelerde açıklandı.

Dil listeleri Apple API tablosundan ve Fastlane'in Google dil listesinden
kontrol edildi. Dart registry'sinden üretilen `fastlane/locales.json` Ruby
helper'ı tarafından okunuyor; iki farklı hardcoded mapping kalmadı. Bu liste
sürümle birlikte güncellenen bir snapshot; her çalıştırmada internetten çekilmez.

Pull uzak metinleri snapshot olarak saklıyor, alanların yerel/uzak değerlerini
karşılaştırıyor ve istenirse `.bak` ile içe aktarıyor. Görsel indirme yok;
Google pull store listing metinlerini indirir, track release notes'unu indirmez.

## Yerel GUI

`torchinlane studio` tek komutla tarayıcı paneli açıyor. HTML/CSS/JavaScript
pakete gömülü; Node, ayrı Flutter desktop build veya web hosting gerekmiyor.
Dart HTTP sunucusu sadece loopback adresine bağlanıyor. Oturum token'ı,
Host/Origin kontrolleri, asset path/symlink kontrolleri ve işlem kilidi var.

Panelde proje kurulumu, locale ekleme, metin/karakter-byte sayaçları, görsel
import/sıralama, çeviri, validation/export, uzak metin karşılaştırma/import,
credential import/doğrulama ve build/upload işlemleri bulunuyor. İşlem logları
asenkron izleniyor; işlem sürerken düzenlemeler kilitleniyor. CLI ve GUI aynı
StoreContent/StoreService/credential bileşenlerini kullanıyor.

## Credential ve imzalama otomasyonu

`.p8`/Google JSON içe aktarma, gitignore, POSIX dosya izinleri ve reusable
profile desteği eklendi. Profil anahtarları home dizininde saklanarak birden
fazla projede kullanılabiliyor. `credentials verify` gerçek API/app erişimini
kontrol ediyor; Google edit'i commit etmeden bırakıyor. Deploy build'den önce
app erişimini kontrol ediyor; bir platformun erişim hatası diğerini durdurmuyor.

`credentials bootstrap-google` mevcut gcloud login'i ile API/service-account
kurulumunu ve isteğe göre JSON key import veya GitHub repository'ye kısıtlı
WIF oluşturmayı yapıyor. Cloud projesi ve kullanıcının IAM yetkileri önceden
mevcut olmalı; Play Console app yetkisi ilk seferde ayrıca veriliyor.

`signing android` mevcut upload keystore'u içe alıp protected key.properties
oluşturuyor. Standart Flutter Kotlin/Groovy Gradle dosyasında debug signing
placeholder'ını release signing ile değiştiriyor ve backup alıyor. Özel signing
blokları ezilmiyor; manual integration gerektiği açıkça bildiriliyor.

`signing sync` iOS için private/encrypted Fastlane match repository'sinden
sertifika/profile kuruyor; `--write` ile uygun Apple izinleri altında
oluşturma/yenileme de yapılabiliyor. Runner Release/Profile signing ayarları ve
ExportOptions kurulan profile göre güncelleniyor, yerel dosyalar yedekleniyor.

## CI ve deploy

`ci init` manual dispatch, bağımsız Android/iOS job'ları, Ruby/Flutter/Fastlane
kurulumu, credential restoration, signing, access validation ve store upload
seçeneği bulunan GitHub Actions workflow'u oluşturuyor. WIF veya JSON credential
seçilebilir. Mevcut workflow overwrite için explicit `--force` gerekir.

`deploy --with-store` içerikleri build öncesi doğruluyor, binary upload sonrası
mağaza metin/görsellerini gönderiyor. Google release status/rollout CLI'dan
seçilebiliyor. Apple production review otomatik gönderilmiyor. Başarılı
upload'dan sonra notların otomatik silinmesi kaldırıldı; audit/retry için kalıyor.

Üretilen CI'da generator'ın paket sürümü pin'li. Yayımlanmamış bir geliştirme
sürümüyle workflow üretilirse activation satırı Git/local source kurulumu ile
değiştirilmelidir. CI secrets/account/signing
hazırlıkları workflow oluşturmakla tamamlanmış sayılmaz.

## Doğrulama

- `dart analyze`: temiz.
- `dart test`: 50 test geçti; başlangıçtaki 17 testten genişletildi.
- Üretilen Fastfile/Appfile/helper Ruby syntax ve build.sh shell syntax kontrolleri geçti.
- Ruby mock entegrasyonları iOS metadata not yüklemesini, localized TestFlight
  beklemesini, JSON/legacy note önceliğini ve Google partial note preservation'ı
  kontrol etti; gerçek mağazaya istek yapmadı.
- Workflow YAML, embedded Bash/Python scriptleri, Gradle signing patch ve
  password escaping kontrolleri geçti.
- Yerel kurulu Fastlane 2.230.0 içindeki kullanılan Supply/Spaceship metotlarının
  varlığı ayrıca kontrol edildi. OAuth authorized_user ve yeni locale desteği
  için güncel Fastlane kullanımı belgelerde belirtildi.
- Dart native executable derlemesi başarılı.
- Gerçek Chrome smoke testi: setup, locale editing, image import, validation,
  dry upload, export ve derlenmiş CLI üzerinden deploy planı; desktop/mobile kontrolü; JavaScript hatası yok.
- `dart pub publish --dry-run`: gerçek yayın yapmadan paket içeriği kontrol edildi.
  Değişiklikler henüz commit edilmediği için working-tree uyarısı bekleniyor.

Bu doğrulamalar gerçek Apple/Google upload, gerçek Claude translation, gerçek
Cloud IAM kurulumu veya imzalı Flutter uygulama build'i yerine geçmez. Bu
hesaplara ait credential'lar kullanılmadı; account-specific sonuçlar canlı
entegrasyonla doğrulanmalıdır.

## Manuel kalan sınırlar

Apple API erişimi ve ilk p8 üretimi/indirimi; developer account registration,
agreements/declarations; store app record oluşturma ve ilk Google build; ilk
Play Console yetki ataması; mevcut Android upload key temini; özel flavor/target
imzalama ve uygulamaya özgü otomatik ekran gezme/görsel tasarım işi bu sürümde
sıfır kullanıcı müdahalesiyle çözülmüyor. Apple final review submission da mevcut
politikaya uygun şekilde manual kalıyor. Bu adımlar sonrası rutin release
işlemleri CLI/CI'dan otomatik çalıştırılabilir.

## Kullanıma başlama

Bu checkout'u yerel kurmak için:

```bash
dart pub global activate --source path /path/to/torchinlane
```

Sonra her Flutter uygulamasında:

```bash
torchinlane update -y    # daha önce init yapılmışsa
torchinlane studio       # yeni projede Setup ekranından da başlanabilir
```

Detaylar: [README](../README.md), [mağaza içerikleri](store-content.md),
[credential/signing/CI](automation.md), [migration](migration.md).

## API anahtarı olmadan çeviri

`store translate` varsayılan olarak API çağırmak yerine Claude Code/Codex'e
yapıştırılacak görevi üretir; `store prompt` aynı akışın açık isimli komutudur.
GUI'de Prepare agent task / Copy task / Reload agent changes eklendi. Kaynak
metinler ve mevcut hedef dosyaların snapshot'ları, yalnızca izin verilen dosya
yolları, eksik alanlar, platforma özgü dil kodları ve alan sınırları göreve
eklenir. Yeni değişiklikleri ezmeme, marka/URL/placeholder koruma ve sonuçları
validate etme kuralları verilir. Görev üretimi ağ bağlantısı veya API key
gerektirmez ve proje dosyalarını değiştirmez. Ajanın değişiklikleri ayrıca
incelenmelidir; prompt kuralları ajana yönlendirmedir, teknik sandbox değildir.

Doğrudan Anthropic çevirisi yalnızca `store translate --api` veya paneldeki
isteğe bağlı API butonuyla çalışır. Ajan kullanımının kendi abonelik/limitleri
geçerlidir. Eski `changelog translate` API davranışını korur.

Ek doğrulama: 50 test başarılı, dart analyze temiz. API anahtarı olmadan
derlenmiş CLI'da `translate` ve `prompt` çalıştırıldı; hedef dosyaların değişmediği
kontrol edildi. Gerçek Chrome testinde görev hazırlama/kopyalama, ajanın dosya
değişikliklerini yeniden yükleme ve doğrulama akışı masaüstü/mobil panelde
kontrol edildi; JavaScript hatası bulunmadı.
