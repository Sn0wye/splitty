/**
 * The app's four languages. English sits at the root; the others are prefixed. The app
 * links to `/{prefix}/privacy` from its own language setting, so these paths are a contract
 * with `AppLanguage` in the iOS client: `pt-BR` there is `pt-br` here.
 */
export const locales = ["en", "pt-br", "es", "fr"] as const;
export type Locale = (typeof locales)[number];

export const htmlLang: Record<Locale, string> = {
  en: "en",
  "pt-br": "pt-BR",
  es: "es",
  fr: "fr",
};

/** Autonyms, as the app's language picker shows them. */
export const localeNames: Record<Locale, string> = {
  en: "English",
  "pt-br": "Português (Brasil)",
  es: "Español",
  fr: "Français",
};

/** The demo's currency. Each language gets the money its readers most likely split. */
export const currency: Record<Locale, string> = {
  en: "USD",
  "pt-br": "BRL",
  es: "EUR",
  fr: "EUR",
};

export type Page = "" | "privacy" | "terms" | "support";

export function pathFor(locale: Locale, page: Page = ""): string {
  const prefix = locale === "en" ? "" : `/${locale}`;
  return page ? `${prefix}/${page}` : `${prefix}/`;
}

/** `getStaticPaths` for a `[...lang]` route: English has no segment. */
export function localePaths() {
  return locales.map((locale) => ({
    params: { lang: locale === "en" ? undefined : locale },
    props: { locale },
  }));
}

/**
 * How the app writes each currency, from `Currency` in the iOS client: the symbol's side and
 * spacing and both separators belong to the currency, not to the reader's language. So a
 * euro amount reads `1.240,00 €` in every language, as it does in the app.
 */
const writing: Record<string, { symbol: string; follows: boolean; spaced: boolean; decimal: string; group: string }> = {
  USD: { symbol: "$", follows: false, spaced: false, decimal: ".", group: "," },
  GBP: { symbol: "£", follows: false, spaced: false, decimal: ".", group: "," },
  BRL: { symbol: "R$", follows: false, spaced: true, decimal: ",", group: "." },
  EUR: { symbol: "€", follows: true, spaced: true, decimal: ",", group: "." },
};

/** `Money.formatted`: an amount in a currency, written the app's way. */
export function formatAmount(value: number, code: string): string {
  const style = writing[code] ?? writing.USD;
  const [whole, cents] = Math.abs(value).toFixed(2).split(".");
  const number = `${whole.replace(/\B(?=(\d{3})+(?!\d))/g, style.group)}${style.decimal}${cents}`;
  const space = style.spaced ? "\u00a0" : "";
  const written = style.follows ? `${number}${space}${style.symbol}` : `${style.symbol}${space}${number}`;
  return value < 0 ? `-${written}` : written;
}

/** The symbol and decimal key the keypad shows for a currency. */
export function currencyWriting(code: string) {
  return writing[code] ?? writing.USD;
}

export function formatMoney(locale: Locale, value: number, code: string = currency[locale]): string {
  return formatAmount(value, code);
}

export function formatDate(locale: Locale, iso: string): string {
  return new Intl.DateTimeFormat(htmlLang[locale], { dateStyle: "long", timeZone: "UTC" }).format(
    new Date(iso),
  );
}
