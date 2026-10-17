import { en, type Dictionary } from "./en";
import { es } from "./es";
import { fr } from "./fr";
import { ptBr } from "./pt-br";
import type { Locale } from "./locales";

export * from "./locales";
export type { Dictionary };

const dictionaries: Record<Locale, Dictionary> = { en, "pt-br": ptBr, es, fr };

export function t(locale: Locale): Dictionary {
  return dictionaries[locale];
}

/** Fills `{name}` placeholders. Translations reorder them freely. */
export function fill(template: string, values: Record<string, string>): string {
  return template.replace(/\{(\w+)\}/g, (match, key: string) => values[key] ?? match);
}
