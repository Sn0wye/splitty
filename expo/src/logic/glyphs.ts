export function amountGlyphs(text: string): { id: string; character: string }[] {
  return Array.from(text).map((character, index) => ({
    id: `${index}-${character}`,
    character
  }));
}
