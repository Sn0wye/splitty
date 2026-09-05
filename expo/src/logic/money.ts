/** Money is represented as integer cents until the REST boundary. */
export function centsFromApi(value: number | string): number {
  const text = String(value).trim();
  const [whole = '0', fraction = ''] = text.split('.');
  const sign = whole.startsWith('-') ? -1 : 1;
  const absoluteWhole = whole.replace('-', '');
  const digits = (fraction + '00').slice(0, 2);
  return sign * (Number(absoluteWhole || 0) * 100 + Number(digits));
}
export function apiAmount(cents: number): number { return cents / 100; }
/** `$42.50` — Swift `Money.formatted`, hardcoded `$`, always two fraction digits. */
export function formatCents(cents: number): string {
  const sign = cents < 0 ? '-' : '';
  const magnitude = Math.abs(cents);
  return `${sign}$${Math.floor(magnitude / 100)}.${String(magnitude % 100).padStart(2, '0')}`;
}

/** `42`, `42.50` — for typed fields. */
export function plainString(cents: number): string {
  const sign = cents < 0 ? '-' : '';
  const magnitude = Math.abs(cents);
  const whole = Math.floor(magnitude / 100);
  const fraction = magnitude % 100;
  return fraction === 0 ? `${sign}${whole}` : `${sign}${whole}.${String(fraction).padStart(2, '0')}`;
}
export function parseTypedMoney(text: string): number | null {
  if (!/^\d+(\.\d{0,2})?$/.test(text.trim())) return null;
  const [whole = '0', fraction = ''] = text.trim().split('.');
  const cents = Number(whole) * 100 + Number((fraction + '00').slice(0, 2));
  return Number.isSafeInteger(cents) ? cents : null;
}

/** Parses the API's numeric(5,2) percentage scale without binary rounding. */
export function parseTypedPercentage(text: string): number | null {
  if (!/^\d+(\.\d{0,2})?$/.test(text.trim())) return null;
  const value = Number(text.trim());
  return Number.isFinite(value) && value <= 100 ? value : null;
}
