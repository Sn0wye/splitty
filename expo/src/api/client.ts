import * as SecureStore from 'expo-secure-store';
import type { ApiErrorPayload, BalanceSummary, CreateExpenseRequest, Expense, Group, GroupMutationResponse, Invite, LoginResponse, UpdateExpenseRequest, User } from '@/types';
import { apiAmount, centsFromApi } from '@/logic/money';
import { HttpError } from '@/api/errors';
import { decodeSuccessBody } from '@/api/response';

export { HttpError } from '@/api/errors';

const TOKEN_KEY = 'splitty.jwt';
export const tokenStore = { get: () => SecureStore.getItemAsync(TOKEN_KEY), set: (token: string) => SecureStore.setItemAsync(TOKEN_KEY, token), clear: () => SecureStore.deleteItemAsync(TOKEN_KEY) };

const baseUrl = (process.env.EXPO_PUBLIC_API_BASE_URL ?? '').replace(/\/$/, '');
let unauthorizedHandler: (() => void) | undefined;
export function onUnauthorized(handler: () => void): void { unauthorizedHandler = handler; }
async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  if (!baseUrl) throw new Error('EXPO_PUBLIC_API_BASE_URL is missing');
  const token = await tokenStore.get();
  const headers = new Headers(init.headers);
  headers.set('Accept', 'application/json');
  if (init.body) headers.set('Content-Type', 'application/json');
  if (token) headers.set('Authorization', `Bearer ${token}`);
  let response: Response;
  try { response = await fetch(`${baseUrl}${path}`, { ...init, headers }); } catch { throw new HttpError(0, 'Unable to reach Splitty. Check your connection.'); }
  if (response.status === 401) { unauthorizedHandler?.(); throw new HttpError(401, 'Your session expired.'); }
  if (!response.ok) { let payload: ApiErrorPayload = {}; try { payload = await response.json() as ApiErrorPayload; } catch { /* empty error response */ } const validationMessages = payload.errors ? Object.values(payload.errors).flatMap(value => Array.isArray(value) ? value : [value]).filter(message => typeof message === 'string' && message.length > 0) : []; throw new HttpError(response.status, payload.message ?? (validationMessages.length > 0 ? validationMessages.join(' ') : `Request failed (${response.status}).`)); }
  return decodeSuccessBody<T>(response.status, await response.text());
}
const query = <T,>(path: string, init?: RequestInit): Promise<T> => request<T>(path, init);
const body = (value: unknown): RequestInit => ({ method: 'POST', body: JSON.stringify(value) });

export const api = {
  profile: () => query<User>('/auth'),
  devLogin: async (email: string) => { const response = await query<LoginResponse>('/auth/dev-login', body({ email })); await tokenStore.set(response.token); return response.user; },
  googleLogin: async (authCode: string) => { const response = await query<LoginResponse>('/oauth/google', body({ authCode })); await tokenStore.set(response.token); return response.user; },
  groups: () => query<Group[]>('/group'),
  group: (id: number) => query<Group>(`/group/${id}`),
  createGroup: (name: string, description?: string) => query<GroupMutationResponse>('/group', body({ name, description })),
  updateGroup: (id: number, name?: string, description?: string) => query<GroupMutationResponse>(`/group/${id}`, { method: 'PUT', body: JSON.stringify({ name, description }) }),
  expenses: (groupId: number) => query<Expense[]>(`/group/${groupId}/expenses`),
  expense: (groupId: number, expenseId: number) => query<Expense>(`/group/${groupId}/expenses/${expenseId}`),
  createExpense: (groupId: number, input: { description: string; amountCents: number; paidBy: number; date?: string; splitMode: CreateExpenseRequest['splitMode']; splits: CreateExpenseRequest['splits'] }) => query<Expense>(`/group/${groupId}/expenses`, { method: 'POST', body: JSON.stringify({ description: input.description, amount: apiAmount(input.amountCents), paidBy: input.paidBy, date: input.date, splitMode: input.splitMode, splits: input.splits }) }),
  updateExpense: (groupId: number, expenseId: number, input: UpdateExpenseRequest & { amountCents?: number }) => { const { amountCents, ...rest } = input; return query<Expense>(`/group/${groupId}/expenses/${expenseId}`, { method: 'PUT', body: JSON.stringify({ ...rest, ...(amountCents === undefined ? {} : { amount: apiAmount(amountCents) }) }) }); },
  deleteExpense: (groupId: number, expenseId: number) => query<void>(`/group/${groupId}/expenses/${expenseId}`, { method: 'DELETE' }),
  balances: (groupId: number) => query<BalanceSummary>(`/group/${groupId}/expenses/summary`),
  refreshBalances: (groupId: number) => query<void>(`/group/${groupId}/expenses/summary`, { method: 'POST' }),
  settle: (groupId: number, withUserId: number, amountCents: number) => query<void>(`/group/${groupId}/settle`, body({ withUserId, amount: apiAmount(amountCents) })),
  deleteSettlement: (groupId: number, expenseId: number) => query<void>(`/group/${groupId}/settlements/${expenseId}`, { method: 'DELETE' }),
  updateSettlement: (groupId: number, expenseId: number, amountCents: number, date?: string) => query<void>(`/group/${groupId}/settlements/${expenseId}`, { method: 'PUT', body: JSON.stringify({ amount: apiAmount(amountCents), date }) }),
  invite: (groupId: number, maxUses?: number) => query<Invite>(`/group/${groupId}/invites`, body({ maxUses })),
  acceptInvite: (code: string) => query<Group>(`/invite/${encodeURIComponent(code)}/accept`, body({})),
  leave: (groupId: number) => query<void>(`/group/${groupId}/leave`, body({})),
  removeMember: (groupId: number, userId: number) => query<void>(`/group/${groupId}/members/${userId}`, { method: 'DELETE' }),
  centsFromApi
};
