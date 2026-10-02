# Studio ile adım adım kullanım

Flutter projenizin klasöründe çalıştırın:

```bash
torchinlane studio
```

Tarayıcı açılır. Terminali açık bırakın; Ctrl+C paneli kapatır.
`torchinlane init` komutunu önceden çalıştırmanız gerekmez. Mevcut kurulumunuz
varsa panel onu tanır. CLI sürümünü `torchinlane --version` ile görebilirsiniz.

## 1. Başlangıç ekranında durumunuza bakın

Yalnızca kullanacağınız mağazayı seçin. Tamamlanan adımlarda **Tamam** görünür.
“Yeniden kurulum gerekmez” veya “Bu adımı geçebilirsin” yazan işleri tekrarlamayın.
**Önerilen adıma git** düğmesi bir sonraki eksik işi açar. Dosyalarınız ajandan
veya başka bir araçtan değişirse **Dosyaları tekrar kontrol et** düğmesini kullanın.

- Kimlik dosyasının bulunması, hesabın mağaza erişimi olduğu anlamına gelmez.
  Canlı kontrol ayrı gösterilir; otomatik mağaza bağlantısı kurulmaz.
- Metin/çeviri hazırlamak için Apple/Google anahtarı veya build araçları gerekmez.
- Yalnızca metadata yüklemek için uygulamanızı yeniden build etmeniz gerekmez.

## 2. Kurulum: yalnızca eksik değerleri tamamlayın

**Kurulum** adımında uygulama adı, kaynak dil (`tr` veya `en` gibi) ve seçilen
mağazanın uygulama kimliğini girin. **Ayarları kaydet** düğmesine basın.
Var olan değerler zaten görünür; doğruysa değiştirmeyin. Yardımcı dosyalar
güncelse dosya tamamlama düğmesi pasif olur.

Mağazaya yükleme yapacağınız zaman Apple .p8 veya Google JSON dosyanızı ekleyin.
Panel geçerli bir dosya bulduysa tekrar indirmeyin/eklemeyin. Dosyanın nereden
alınacağı ilgili bağlantı bölümünde anlatılır. Ardından **Mağaza erişimini
kontrol et** düğmesini kullanın. Bu işlem içerik yüklemez. Başarılı kontrol aynı
Studio sunucu oturumunda hatırlanır; uygulama/anahtar değişirse yeniden gerekir.
Studio yeniden başlatıldığında canlı erişim tekrar kontrol edilebilir; bu,
kimlik dosyasını yeniden içe aktarmayı gerektirmez.

**Araçları kontrol et** Ruby/Fastlane, Flutter ve gerekirse CocoaPods/Xcode'u
çalıştırarak kontrol eder. Kurulum yapmaz. Eksik Fastlane/CocoaPods varsa ayrı
onarım düğmesini kullanın. Flutter, Android SDK ve Xcode kurulumu bu onarımın
kapsamında değildir. İmzalama yalnızca yeni release build oluşturacaksanız
önemlidir; mevcut çalışan imzalamanızı yeniden kurmayın.

## 3. Metinler: bir dilde yazın

**Metinler → Kaynak dili aç** ile bildiğiniz dilde uygulama adı, açıklama ve
“Bu sürümde neler değişti?” alanlarını doldurun. **Metinleri kaydet** düğmesine
basın. Apple ve Google'ın alanları farklı olduğu için mağazaları ayrı seçersiniz.
Diğer mağazada ortak metinleri yazdıysanız **Diğer mağazadan kaynak metni al**
düğmesi yalnızca boş ortak alanları doldurur; dolu metinleri ezmez.

Kaynak metinleriniz zaten hazırsa tekrar yazmayın. Mağazadaki metinleri yerel
projenize almak isterseniz **Gönder → İleri yükleme seçenekleri** altında
karşılaştırma/içe alma seçenekleri bulunur. Google pull, listing metinlerini
alır; track release notes'unu ve görselleri indirmez.

## 4. Çeviri: kopyala, ajana ver, kontrol et

1. **Çeviri** adımından hedef dilleri ekleyin. Dolu çeviriler varsa korunur.
2. **Çeviri görevini hazırla → Görevi kopyala** düğmelerine basın.
3. Claude Code veya Codex'i aynı Flutter projesinde açıp görevi yapıştırın.
   Ajan `store/` içindeki ilgili JSON dosyalarını doldurur. Apple/Google dil
   kodları, alan sınırları ve korunacak metinler görevin içinde hazırdır.
4. Ajan bitince **Sonuçları yükle ve kontrol et** düğmesine basın.
   Hata varsa ilgili metni düzeltin. Eksik alan kalmadıysa tekrar çeviri gerekmez.

Bu akış Torchinlane çeviri API anahtarı istemez. Ajanınızın kendi abonelik ve
kullanım limitleri geçerlidir. Bir görev yalnızca seçilen mağazayı kapsar;
iki mağaza kullanıyorsanız diğerini seçip aynı adımları uygulayın. Görevdeki
kurallar ajana yönlendirmedir; sonuçları ve değişiklikleri gözden geçirin.
İsteğe bağlı ücretli API seçeneği ileri seçeneklerde kalır.

## 5. Görseller: yalnızca değiştirecekseniz

Mağazadaki görseller uygunsa geçin. Yeni görsel ekleyecekseniz mağaza, dil ve
cihaz/görsel türünü seçip PNG/JPEG dosyalarını ekleyin. Görsel içindeki yazılar
otomatik çevrilmez; her dil için hazır dosya gerekir. Oklar sıralamayı değiştirir.

## 6. Gönder: önce planı kontrol edin

Varsayılan **Uygulama metinleri** seçeneğiyle başlayın. **Yükleme planını kontrol
et** yalnızca doğrulama yapar. Hazırsa **İçeriği gönder** düğmesine basın.
Sürüm notları seçerseniz Google için mevcut build numarasını ve kanalını girin.
Bu bilgiler yalnızca mağazada bulunan ilgili sürümün notlarını günceller.

Yeni AAB/IPA göndermek istiyorsanız **Yeni uygulama build'i göndereceğim**
bölümünü açın. Hazır build seçeneği yeniden build oluşturmaz. Bu akış Google
release'ini taslak bırakır ve Apple incelemesini otomatik başlatmaz.
