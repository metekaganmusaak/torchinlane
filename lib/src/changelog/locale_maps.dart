/// Store locale mappings, ported from ChangelogHelper.rb. Used for CLI-side
/// validation/reporting; the authoritative mapping used at upload time lives
/// in fastlane/ChangelogHelper.rb (kept in Ruby to avoid a second source of truth).
const googlePlayLocaleMap = <String, String>{
  'ar': 'ar', 'bn': 'bn-BD', 'cs': 'cs-CZ', 'da': 'da-DK', 'de': 'de-DE',
  'el': 'el-GR', 'en': 'en-US', 'es': 'es-ES', 'fa': 'fa', 'fi': 'fi-FI',
  'fr': 'fr-FR', 'he': 'he', 'hi': 'hi-IN', 'hu': 'hu-HU', 'id': 'id',
  'it': 'it-IT', 'ja': 'ja-JP', 'ko': 'ko-KR', 'nl': 'nl-NL', 'no': 'no-NO',
  'pl': 'pl-PL', 'pt': 'pt-BR', 'ro': 'ro', 'ru': 'ru-RU', 'sk': 'sk',
  'sv': 'sv-SE', 'th': 'th', 'tl': 'fil', 'tr': 'tr-TR', 'uk': 'uk',
  'vi': 'vi', 'zh': 'zh-CN',
};

const appStoreLocaleMap = <String, String?>{
  'ar': 'ar-SA', 'bn': 'bn', 'cs': 'cs', 'da': 'da', 'de': 'de-DE',
  'el': 'el', 'en': 'en-US', 'es': 'es-ES', 'fa': null, 'fi': 'fi',
  'fr': 'fr-FR', 'he': 'he', 'hi': 'hi', 'hu': 'hu', 'id': 'id',
  'it': 'it', 'ja': 'ja', 'ko': 'ko', 'nl': 'nl-NL', 'no': 'no',
  'pl': 'pl', 'pt': 'pt-BR', 'ro': 'ro', 'ru': 'ru', 'sk': 'sk',
  'sv': 'sv', 'th': 'th', 'tl': 'fil', 'tr': 'tr', 'uk': 'uk',
  'vi': 'vi', 'zh': 'zh-Hans',
};

const googlePlayMaxChars = 500;
const appStoreMaxChars = 4000;
