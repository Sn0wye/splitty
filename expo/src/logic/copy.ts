import { centsFromApi, formatCents } from '@/logic/money';

/** Nil when there are no groups — distinct from a real all-settled total of zero. */
export function overallBalanceCents(groups: readonly { netBalance: number | string }[]): number | null {
  if (groups.length === 0) return null;
  return groups.reduce((sum, group) => sum + centsFromApi(group.netBalance), 0);
}

export function overallBalanceCopy(cents: number): string {
  if (cents > 0) return `You are owed ${formatCents(cents)} overall`;
  if (cents < 0) return `You owe ${formatCents(Math.abs(cents))} overall`;
  return 'You are all settled up';
}

export function groupCardOweLabel(cents: number): string {
  return cents > 0 ? 'You are owed' : 'You owe';
}

export function dateRowLabel(date: Date): string {
  const start = (value: Date) => new Date(value.getFullYear(), value.getMonth(), value.getDate());
  const today = start(new Date());
  const value = start(date);
  const diff = Math.round((today.getTime() - value.getTime()) / 86_400_000);
  if (diff === 0) return 'Today';
  if (diff === 1) return 'Yesterday';
  return date.toLocaleDateString('en-US', { day: 'numeric', month: 'short', year: 'numeric' });
}

export function detailDateText(date: Date): string {
  return date.toLocaleDateString('en-US', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
}

export function loginErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : '';
  if (message.includes('cancelled')) return '';
  if (message.includes('not configured') || message.includes('not set up') || message.includes('server authorization code') || message.includes('GIDServerClientID')) {
    return "Sign-in isn't set up correctly on this build.";
  }
  if (message.includes('not supported') || message.includes('development build') || message.includes('Expo Go')) {
    return "Sign-in isn't set up correctly on this build.";
  }
  if (message.includes('Unable to reach') || message.includes("Couldn't reach")) {
    return "Couldn't reach Splitty. Check your connection and try again.";
  }
  if (message.includes('401') || message.includes('verify')) {
    return "Google couldn't verify that account. Try again.";
  }
  return 'Sign-in failed. Try again.';
}
