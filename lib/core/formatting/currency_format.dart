import "package:intl/intl.dart";

/// BCP 47 locale used with [NumberFormat] so symbols, grouping, and decimals
/// match common conventions for each ISO 4217 code.
String _localeForCurrencyCode(String code) {
  switch (code.toUpperCase()) {
    case "GBP":
      return "en_GB";
    case "EUR":
      return "en_IE";
    case "USD":
      return "en_US";
    case "CAD":
      return "en_CA";
    case "AUD":
      return "en_AU";
    case "NZD":
      return "en_NZ";
    case "JPY":
      return "ja_JP";
    case "CHF":
      return "de_CH";
    case "SEK":
      return "sv_SE";
    case "NOK":
      return "nb_NO";
    case "DKK":
      return "da_DK";
    case "PLN":
      return "pl_PL";
    case "CZK":
      return "cs_CZ";
    case "HUF":
      return "hu_HU";
    case "RON":
      return "ro_RO";
    case "INR":
      return "en_IN";
    case "CNY":
      return "zh_CN";
    case "HKD":
      return "zh_HK";
    case "SGD":
      return "en_SG";
    case "MXN":
      return "es_MX";
    case "BRL":
      return "pt_BR";
    case "ZAR":
      return "en_ZA";
    default:
      return "en_US";
  }
}

/// Formats [amount] using locale-appropriate grouping, symbol, and fraction
/// digits for [currencyCode] (ISO 4217, e.g. GBP, EUR, USD).
String formatCurrencyAmount(double amount, String currencyCode) {
  final code = currencyCode.trim().toUpperCase();
  if (code.isEmpty) {
    return amount.toString();
  }
  final locale = _localeForCurrencyCode(code);
  return NumberFormat.currency(
    locale: locale,
    name: code,
  ).format(amount);
}
