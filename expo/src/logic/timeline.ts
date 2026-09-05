import type { Expense } from '@/types';

export function effectiveDate(expense: Expense): Date {
  const value = expense.date ?? expense.createdAt;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? new Date(0) : parsed;
}

/** Local calendar day `YYYY-MM-DD`, matching Swift `Calendar.current`. */
export function localDayKey(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/** Swift `MMM d, E` in en-US — `Apr 12, Sat`. Today/Yesterday use the local calendar. */
export function timelineDayLabel(date: Date, now = new Date()): string {
  const start = (value: Date) => new Date(value.getFullYear(), value.getMonth(), value.getDate());
  const day = start(date);
  const today = start(now);
  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);
  if (day.getTime() === today.getTime()) return 'Today';
  if (day.getTime() === yesterday.getTime()) return 'Yesterday';
  const parts = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', weekday: 'short' }).formatToParts(date);
  const month = parts.find(part => part.type === 'month')?.value ?? '';
  const dayNum = parts.find(part => part.type === 'day')?.value ?? '';
  const weekday = parts.find(part => part.type === 'weekday')?.value ?? '';
  return `${month} ${dayNum}, ${weekday}`;
}

export function groupExpensesByDay(expenses: Expense[]): { key: string; label: string; expenses: Expense[] }[] {
  const groups = new Map<string, Expense[]>();
  for (const expense of [...expenses].sort((a, b) => effectiveDate(b).getTime() - effectiveDate(a).getTime())) {
    const key = localDayKey(effectiveDate(expense));
    groups.set(key, [...(groups.get(key) ?? []), expense]);
  }
  return [...groups.entries()].sort(([a], [b]) => b.localeCompare(a)).map(([key, rows]) => {
    const [year, month, day] = key.split('-').map(Number);
    const date = new Date(year ?? 0, (month ?? 1) - 1, day ?? 1);
    return { key, label: timelineDayLabel(date), expenses: rows };
  });
}
