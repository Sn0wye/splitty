import { describe, expect, it } from 'vitest';
import { AmountExpression } from '@/logic/amountExpression';
import { centsFromApi, formatCents, parseTypedMoney, parseTypedPercentage } from '@/logic/money';
import { detailDateText, overallBalanceCents, overallBalanceCopy } from '@/logic/copy';
import { equalAmounts, makeSplitPayload, percentageAmounts, percentString, restoredSplit, validateSplit } from '@/logic/split';
import { groupExpensesByDay, localDayKey, timelineDayLabel } from '@/logic/timeline';
import { decodeSuccessBody } from '@/api/response';
import { HttpError } from '@/api/errors';
import { shouldClearSession } from '@/auth/session';
import { memberDisplayName } from '@/logic/memberName';
import { amountGlyphs } from '@/logic/glyphs';
import { catalog, grouped } from '@/theme/catalog';
import { expenseFormReturnHref } from '@/nav/expenseForm';
import { expenseDateSheetDetent, EXPENSE_DATE_SHEET_HEIGHT } from '@/nav/dateSheet';
import type { Expense } from '@/types';

describe('money', () => {
  it('preserves integer cents at the API boundary', () => {
    expect(centsFromApi(12.34)).toBe(1234);
    expect(centsFromApi('0.05')).toBe(5);
    expect(parseTypedMoney('7.2')).toBe(720);
  });
  it('formats like Swift Money.formatted', () => {
    expect(formatCents(4250)).toBe('$42.50');
    expect(formatCents(4200)).toBe('$42.00');
    expect(formatCents(-5)).toBe('-$0.05');
  });
  it('rejects malformed and over-scale typed values', () => {
    expect(parseTypedMoney('.')).toBeNull();
    expect(parseTypedMoney('1.234')).toBeNull();
    expect(parseTypedPercentage('12.345')).toBeNull();
  });
});

describe('amount expression', () => {
  it('starts at zero', () => {
    const expression = new AmountExpression();
    expect(expression.displayText).toBe('0');
    expect(expression.resolvedCents).toBe(0);
  });
  it('keeps the displayed trailing point while typing', () => {
    const expression = new AmountExpression();
    expression.typeDigit(7);
    expression.typeDecimalPoint();
    expect(expression.displayText).toBe('7.');
    expect(expression.resolvedCents).toBe(700);
  });
  it('seeds from an existing amount including trailing cents', () => {
    const expression = new AmountExpression(4250);
    expect(expression.displayText).toBe('42.50');
    expect(expression.resolvedCents).toBe(4250);
  });
  it('seeds a whole amount without trailing zeros', () => {
    expect(new AmountExpression(4200).displayText).toBe('42');
  });
  it('stops at two decimal places', () => {
    const expression = new AmountExpression();
    expression.typeDigit(1);
    expression.typeDecimalPoint();
    expression.typeDigit(2);
    expression.typeDigit(3);
    expression.typeDigit(4);
    expect(expression.displayText).toBe('1.23');
  });
  it('chains operations left-to-right', () => {
    const expression = new AmountExpression();
    expression.typeDigit(2);
    expression.apply('+');
    expression.typeDigit(3);
    expression.apply('*');
    expression.typeDigit(4);
    expression.evaluate();
    expect(expression.resolvedCents).toBe(2000);
  });
  it('does not invent a division-by-zero result', () => {
    const expression = new AmountExpression();
    expression.typeDigit(8);
    expression.apply('/');
    expression.typeDigit(0);
    expression.evaluate();
    expect(expression.resolvedCents).toBe(800);
  });
  it('resolves a pending operation without tapping equals', () => {
    const expression = new AmountExpression();
    expression.typeDigit(1);
    expression.typeDigit(0);
    expression.apply('+');
    expression.typeDigit(5);
    expect(expression.displayText).toBe('5');
    expect(expression.resolvedCents).toBe(1500);
  });
});

describe('splits', () => {
  it('allocates remainders to lowest IDs', () => expect(equalAmounts(10, [9, 2, 5])).toEqual({ 2: 4, 5: 3, 9: 3 }));
  it('floors percentages then allocates remainder', () => expect(percentageAmounts(101, { 2: 50, 5: 50 })).toEqual({ 2: 51, 5: 50 }));
  it('gives leftover cents to the lowest user ids', () => {
    expect(percentageAmounts(1000, { 9: 33.34, 2: 33.33, 4: 33.33 })).toEqual({ 2: 334, 4: 333, 9: 333 });
  });
  it('uses integer hundredths so binary float does not change the floor', () => {
    expect(percentageAmounts(10, { 1: 10.1, 2: 89.9 })).toEqual({ 1: 2, 2: 8 });
  });
  it('always sums percentage shares to the total', () => {
    for (const total of [1, 2, 7, 99, 100, 101, 1234, 99999]) {
      const amounts = percentageAmounts(total, { 1: 33.33, 2: 33.33, 3: 33.34 });
      expect(Object.values(amounts).reduce((sum, value) => sum + value, 0)).toBe(total);
    }
  });
  it('omits a share of zero', () => expect(percentageAmounts(10000, { 1: 100, 2: 0 })).toEqual({ 1: 10000 }));
  it('requires custom amounts to sum exactly', () => expect(validateSplit(100, 'custom', [], { 2: 30 }, {}).valid).toBe(false));
  it('says dollars left or over with a dollar sign and no trailing period', () => {
    expect(validateSplit(1000, 'custom', [], { 2: 500 }, {}).message).toBe('$5.00 left to assign');
    expect(validateSplit(1000, 'custom', [], { 2: 1500 }, {}).message).toBe('$5.00 over the total');
  });
  it('rejects invalid percentage scale and negative custom rows', () => {
    expect(validateSplit(100, 'percentage', [], {}, { 2: 50.001, 5: 49.999 }).valid).toBe(false);
    expect(validateSplit(100, 'custom', [], { 2: 120, 5: -20 }, {}).valid).toBe(false);
  });
  it('says over 100% when percentage sum exceeds one hundred', () => {
    expect(validateSplit(100, 'percentage', [], {}, { 2: 60, 5: 50 }).message).toBe('10% over 100%');
    expect(percentString(10)).toBe('10');
    expect(percentString(10.5)).toBe('10.5');
  });
  it('blocks an empty percentage split instead of claiming 100% is left', () => {
    expect(validateSplit(100, 'percentage', [], {}, {}).message).toBe('Select who this is split between');
  });
  it('preserves an explicitly custom restored mode', () => {
    const expense = { splitMode: 'custom', paidBy: 1, splits: [{ userId: 2, amount: 0.5 }, { userId: 5, amount: 1.5 }] } as Expense;
    expect(restoredSplit(expense).mode).toBe('custom');
  });
  it('keeps stored custom amounts and percentages as independent drafts', () => {
    const expense = {
      splitMode: 'percentage',
      paidBy: 1,
      splits: [
        { userId: 2, amount: 0.6, percentage: 60 },
        { userId: 5, amount: 0.4, percentage: 40 }
      ]
    } as Expense;
    const restored = restoredSplit(expense);
    expect(restored.custom).toEqual({ 2: 60, 5: 40 });
    expect(restored.percentages).toEqual({ 2: 60, 5: 40 });
  });
  it('seeds custom cents from an equal expense so switching mode is not blank', () => {
    const expense = {
      splitMode: 'equal',
      paidBy: 1,
      splits: [
        { userId: 2, amount: 0.5 },
        { userId: 5, amount: 0.5 }
      ]
    } as Expense;
    expect(restoredSplit(expense).custom).toEqual({ 2: 50, 5: 50 });
    expect(restoredSplit(expense).percentages).toEqual({});
  });
  it('omits zero-value participants from payload', () => expect(makeSplitPayload(100, 'custom', [], { 2: 100, 5: 0 }, {})).toEqual([{ userId: 2, amount: 1 }]));
});

describe('timeline', () => {
  it('uses user date and sorts newest first', () => {
    const make = (id: number, date: string): Expense => ({ id, groupId: 1, paidBy: 1, amount: 1, description: String(id), type: 'expense', splitMode: 'equal', date, createdAt: date, updatedAt: date, paidByUser: { id: 1, name: 'A', email: 'a', createdAt: date, updatedAt: date }, splits: [] });
    expect(groupExpensesByDay([make(1, '2025-01-01T00:00:00Z'), make(2, '2025-01-03T00:00:00Z')])[0]?.expenses[0]?.id).toBe(2);
  });
  it('labels a calendar day as Swift MMM d, E in en-US', () => {
    expect(timelineDayLabel(new Date(2025, 3, 12))).toBe('Apr 12, Sat');
  });
  it('groups by local calendar day rather than UTC', () => {
    const make = (id: number, date: string): Expense => ({ id, groupId: 1, paidBy: 1, amount: 1, description: String(id), type: 'expense', splitMode: 'equal', date, createdAt: date, updatedAt: date, paidByUser: { id: 1, name: 'A', email: 'a', createdAt: date, updatedAt: date }, splits: [] });
    const local = new Date(2025, 3, 12, 22, 0, 0);
    const groupedDays = groupExpensesByDay([make(1, local.toISOString())]);
    expect(groupedDays[0]?.key).toBe(localDayKey(local));
    expect(groupedDays[0]?.key).toBe('2025-04-12');
    const utcKey = local.toISOString().slice(0, 10);
    if (utcKey !== '2025-04-12') expect(groupedDays[0]?.key).not.toBe(utcKey);
    expect(groupedDays[0]?.label).toBe('Apr 12, Sat');
  });
});

describe('empty success bodies', () => {
  it('treats an empty 200 like 204', () => {
    expect(decodeSuccessBody(200, '')).toBeUndefined();
    expect(decodeSuccessBody(200, '   ')).toBeUndefined();
    expect(decodeSuccessBody(204, '')).toBeUndefined();
    expect(decodeSuccessBody(200, '{"ok":true}')).toEqual({ ok: true });
  });
});

describe('session restore', () => {
  it('clears the JWT only on 401', () => {
    expect(shouldClearSession(new HttpError(401, 'expired'))).toBe(true);
    expect(shouldClearSession(new HttpError(0, 'offline'))).toBe(false);
    expect(shouldClearSession(new HttpError(500, 'blip'))).toBe(false);
  });
});

describe('balance copy', () => {
  it('matches Swift BalanceCopy.overall', () => {
    expect(overallBalanceCopy(100)).toBe('You are owed $1.00 overall');
    expect(overallBalanceCopy(-250)).toBe('You owe $2.50 overall');
    expect(overallBalanceCopy(0)).toBe('You are all settled up');
  });
  it('hides overall cents when the groups list is empty', () => {
    expect(overallBalanceCents([])).toBeNull();
    expect(overallBalanceCents([{ netBalance: 0 }])).toBe(0);
    expect(overallBalanceCents([{ netBalance: 1.5 }, { netBalance: -0.5 }])).toBe(100);
  });
});

describe('detail dates', () => {
  it('uses an abbreviated month', () => {
    expect(detailDateText(new Date(2025, 3, 12))).toMatch(/Apr/);
    expect(detailDateText(new Date(2025, 3, 12))).not.toMatch(/April/);
  });
});

describe('expense form navigation', () => {
  it('returns to the group, not the amount step', () => {
    expect(expenseFormReturnHref(7)).toBe('/(tabs)/group/7');
  });
});

describe('date sheet detent', () => {
  it('maps 460pt to a ratio Expo Router can present', () => {
    expect(EXPENSE_DATE_SHEET_HEIGHT).toBe(460);
    expect(expenseDateSheetDetent(852)).toBeCloseTo(460 / 852);
    expect(expenseDateSheetDetent(400)).toBe(1);
  });
});

describe('member labels', () => {
  it('calls the signed-in user You, not the selected payer', () => {
    expect(memberDisplayName(2, 'Ada', 2)).toBe('You');
    expect(memberDisplayName(3, 'Bob', 2)).toBe('Bob');
  });
});

describe('amount glyphs', () => {
  it('identifies a glyph by position and character', () => {
    expect(amountGlyphs('12')).toEqual([
      { id: '0-1', character: '1' },
      { id: '1-2', character: '2' }
    ]);
  });
});

describe('catalog colors', () => {
  it('uses dynamic iOS system red, green, and blue', () => {
    expect(catalog.systemRed.light).toBe('#FF3B30');
    expect(catalog.systemRed.dark).toBe('#FF453A');
    expect(catalog.systemGreen.light).toBe('#34C759');
    expect(catalog.systemGreen.dark).toBe('#30D158');
    expect(catalog.systemBlue.light).toBe('#007AFF');
    expect(catalog.systemBlue.dark).toBe('#0A84FF');
  });
  it('uses AccentColor #3B82F6 as the default tint', () => {
    expect(catalog.accent.light).toBe('#3B82F6');
    expect(catalog.accent.dark).toBe('#3B82F6');
  });
  it('matches Swift inset-grouped geometry', () => {
    expect(grouped.sideInset).toBe(20);
    expect(grouped.cornerRadius).toBe(10);
  });
});
