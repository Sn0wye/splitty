export type Operator = '+' | '-' | '*' | '/';
function apply(left: number, operator: Operator, right: number): number | null {
  if (operator === '+') return left + right;
  if (operator === '-') return left - right;
  if (operator === '*') return left * right;
  return right === 0 ? null : left / right;
}
/** Whole amounts read as `42`, cents as `42.50`. In-progress entry is shown raw. */
function formatPlainFromCents(cents: number): string {
  const sign = cents < 0 ? '-' : '';
  const magnitude = Math.abs(cents);
  const whole = Math.trunc(magnitude / 100);
  const fraction = magnitude % 100;
  return fraction === 0 ? `${sign}${whole}` : `${sign}${whole}.${String(fraction).padStart(2, '0')}`;
}
/** Calculator state. Operations intentionally evaluate left-to-right, matching the iOS client. */
export class AmountExpression {
  private entry: string | null = null;
  private accumulator = 0;
  pendingOperator: Operator | null = null;
  constructor(cents?: number) { if (cents !== undefined) this.entry = formatPlainFromCents(cents); }
  get displayText(): string { return this.entry ?? formatPlainFromCents(Math.round(this.accumulator * 100)); }
  get resolvedCents(): number { return Math.round(this.resolved * 100); }
  private get entryValue(): number | null { if (this.entry === null || this.entry === '' || this.entry === '.') return null; const n = Number(this.entry); return Number.isFinite(n) ? n : null; }
  private get resolved(): number { const right = this.entryValue; if (!this.pendingOperator || right === null) return right ?? this.accumulator; return apply(this.accumulator, this.pendingOperator, right) ?? this.accumulator; }
  typeDigit(digit: number): void { if (digit < 0 || digit > 9 || !Number.isInteger(digit)) return; if (this.entry === null || this.entry === '0') this.entry = String(digit); else if (this.entry.includes('.') ? this.entry.split('.')[1]!.length < 2 : this.entry.length < 9) this.entry += String(digit); }
  typeDecimalPoint(): void { if (this.entry === null) this.entry = '0.'; else if (!this.entry.includes('.')) this.entry += '.'; }
  backspace(): void {
    if (this.entry === null && !this.pendingOperator && this.accumulator !== 0) {
      this.entry = formatPlainFromCents(Math.round(this.accumulator * 100));
      this.accumulator = 0;
    }
    if (this.entry !== null) this.entry = this.entry.slice(0, -1) || null;
  }
  clear(): void { this.entry = null; this.accumulator = 0; this.pendingOperator = null; }
  replaceCents(cents: number): void { this.entry = formatPlainFromCents(cents); this.accumulator = 0; this.pendingOperator = null; }
  apply(operator: Operator): void { const right = this.entryValue; if (right !== null) { this.accumulator = this.pendingOperator ? (apply(this.accumulator, this.pendingOperator, right) ?? this.accumulator) : right; this.entry = null; } this.pendingOperator = operator; }
  evaluate(): void { this.accumulator = this.resolved; this.entry = null; this.pendingOperator = null; }
}
