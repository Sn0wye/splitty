import type { Expense, ExpenseSplitRequest, GroupMember, SplitMode } from '@/types';
import { apiAmount, centsFromApi, formatCents } from './money';

export function equalAmounts(totalCents: number, userIds: readonly number[]): Record<number, number> {
  if (totalCents <= 0 || userIds.length === 0) return {};
  const ordered = [...new Set(userIds)].sort((a, b) => a - b);
  const base = Math.floor(totalCents / ordered.length), remainder = totalCents % ordered.length;
  return Object.fromEntries(ordered.map((id, index) => [id, base + (index < remainder ? 1 : 0)]));
}
function percentageHundredths(value: number): number | null {
  if (!Number.isFinite(value) || value < 0) return null;
  const text = String(value);
  if (!/^\d+(\.\d{0,2})?$/.test(text)) return null;
  const [whole = '0', fraction = ''] = text.split('.');
  return Number(whole) * 100 + Number((fraction + '00').slice(0, 2));
}
export function percentageAmounts(totalCents: number, percentages: Record<number, number>): Record<number, number> {
  const ids = Object.keys(percentages).map(Number).filter(id => (percentages[id] ?? 0) > 0).sort((a, b) => a - b);
  if (ids.length === 0 || totalCents <= 0) return {};
  const result: Record<number, number> = {};
  for (const id of ids) {
    const hundredths = percentageHundredths(percentages[id] ?? 0) ?? 0;
    result[id] = Math.floor((totalCents * hundredths) / 10000);
  }
  let remainder = totalCents - Object.values(result).reduce((sum, value) => sum + value, 0);
  for (const id of ids) if (remainder-- > 0) result[id] = (result[id] ?? 0) + 1;
  return result;
}
export function splitAmounts(totalCents: number, mode: SplitMode, participants: number[], custom: Record<number, number>, percentages: Record<number, number>): Record<number, number> {
  if (mode === 'equal') return equalAmounts(totalCents, participants);
  if (mode === 'percentage') return percentageAmounts(totalCents, percentages);
  return { ...custom };
}
export function memberIds(members: GroupMember[]): number[] { return members.map(member => member.userId); }

/** `20`, `12.5` — no trailing zeros, matching Swift `Percent.string`. */
export function percentString(value: number): string {
  const rounded = Math.round(value * 100) / 100;
  return String(rounded);
}

export type SplitValidation = { valid: boolean; message?: string; starvedUserId?: number };
export function validateSplit(totalCents: number, mode: SplitMode, participants: number[], custom: Record<number, number>, percentages: Record<number, number>): SplitValidation {
  if (totalCents <= 0) return { valid: false, message: 'Enter an amount greater than zero.' };
  if (mode === 'equal' && participants.length === 0) return { valid: false, message: 'Select who this is split between' };
  if (mode === 'custom') {
    const values = Object.values(custom);
    if (values.some(value => !Number.isFinite(value) || value < 0 || !Number.isInteger(value))) return { valid: false, message: 'Enter valid nonnegative amounts.' };
    const difference = totalCents - values.reduce((a, b) => a + b, 0);
    if (difference !== 0) {
      return {
        valid: false,
        message: difference > 0
          ? `${formatCents(difference)} left to assign`
          : `${formatCents(-difference)} over the total`
      };
    }
  }
  if (mode === 'percentage') {
    const active = Object.fromEntries(Object.entries(percentages).filter(([, value]) => value > 0));
    if (Object.keys(active).length === 0) return { valid: false, message: 'Select who this is split between' };
    const scaledValues = Object.values(active).map(percentageHundredths);
    if (scaledValues.some(value => value === null)) return { valid: false, message: 'Enter percentages with at most two decimal places.' };
    const scaledSum = scaledValues.reduce<number>((sum, value) => sum + (value ?? 0), 0);
    if (scaledSum !== 10000) {
      const unassigned = (10000 - scaledSum) / 100;
      return {
        valid: false,
        message: unassigned > 0
          ? `${percentString(unassigned)}% left to assign`
          : `${percentString(-unassigned)}% over 100%`
      };
    }
    const amounts = percentageAmounts(totalCents, active);
    const starved = Object.keys(active).find(id => (amounts[Number(id)] ?? 0) === 0);
    if (starved) return { valid: false, starvedUserId: Number(starved) };
  }
  return { valid: true };
}
export function restoredSplit(expense: Expense): { mode: SplitMode; participants: number[]; custom: Record<number, number>; percentages: Record<number, number> } {
  const custom = Object.fromEntries(expense.splits.map(split => [split.userId, centsFromApi(split.amount)]));
  const percentages = expense.splits.every(split => split.percentage != null)
    ? Object.fromEntries(expense.splits.map(split => [split.userId, split.percentage ?? 0]))
    : {};
  if (expense.splitMode === 'equal') return { mode: 'equal', participants: expense.splits.map(split => split.userId), custom, percentages };
  if (expense.splitMode === 'percentage' && Object.keys(percentages).length === expense.splits.length) {
    return { mode: 'percentage', participants: expense.splits.map(split => split.userId), custom, percentages };
  }
  if (expense.splitMode === 'custom') return { mode: 'custom', participants: expense.splits.map(split => split.userId), custom, percentages };
  const amounts = Object.values(custom);
  const equal = amounts.length > 0 && Math.max(...amounts) - Math.min(...amounts) <= 1;
  return equal
    ? { mode: 'equal', participants: Object.keys(custom).map(Number), custom, percentages }
    : { mode: 'custom', participants: expense.splits.map(split => split.userId), custom, percentages };
}
export function makeSplitPayload(totalCents: number, mode: SplitMode, participants: number[], custom: Record<number, number>, percentages: Record<number, number>): ExpenseSplitRequest[] {
  const amounts = splitAmounts(totalCents, mode, participants, custom, percentages);
  return Object.keys(amounts).map(Number).sort((a, b) => a - b).filter(id => (amounts[id] ?? 0) > 0).map(userId => ({ userId, amount: apiAmount(amounts[userId] ?? 0), ...(mode === 'percentage' ? { percentage: percentages[userId] } : {}) }));
}

export function splitSummary(args: {
  payerId: number;
  currentUserId: number;
  members: GroupMember[];
  mode: SplitMode;
  participants: number[];
  percentages: Record<number, number>;
}): string {
  const payer = args.payerId === args.currentUserId
    ? 'you'
    : args.members.find(member => member.userId === args.payerId)?.name ?? 'someone else';
  if (args.mode === 'custom') return `Paid by ${payer} and split by amounts`;
  if (args.mode === 'percentage') {
    const scaled = Object.values(args.percentages).filter(value => value > 0).reduce((sum, value) => sum + Math.round(value * 100), 0);
    const unassigned = (10000 - scaled) / 100;
    if (unassigned > 0) return `Paid by ${payer}, ${percentString(unassigned)}% left to assign`;
    if (unassigned < 0) return `Paid by ${payer}, ${percentString(-unassigned)}% over 100%`;
    return `Paid by ${payer} and split by percentages`;
  }
  if (args.participants.length === 1) {
    const onlyId = args.participants[0];
    if (onlyId !== undefined && onlyId !== args.payerId) {
      const debtor = onlyId === args.currentUserId
        ? 'you owe'
        : `${args.members.find(member => member.userId === onlyId)?.name ?? 'they'} owes`;
      return `Paid by ${payer}, ${debtor} the full amount`;
    }
  }
  if (args.participants.length === args.members.length || args.members.length === 0) {
    return `Paid by ${payer} and split equally`;
  }
  return `Paid by ${payer} and split equally between ${args.participants.length} people`;
}

/** Signed impact on the signed-in user, matching Expense.getUserSplit. */
export function userSplitCents(expense: Expense, currentUserId: number): number {
  const total = centsFromApi(expense.amount);
  const own = centsFromApi(expense.splits.find(split => split.userId === currentUserId)?.amount ?? 0);
  return expense.paidBy === currentUserId ? total - own : -own;
}
