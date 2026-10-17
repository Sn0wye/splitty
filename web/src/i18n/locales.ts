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

export function formatMoney(locale: Locale, value: number): string {
  return new Intl.NumberFormat(htmlLang[locale], {
    style: "currency",
    currency: currency[locale],
  }).format(value);
}

export function formatDate(locale: Locale, iso: string): string {
  return new Intl.DateTimeFormat(htmlLang[locale], { dateStyle: "long", timeZone: "UTC" }).format(
    new Date(iso),
  );
}
