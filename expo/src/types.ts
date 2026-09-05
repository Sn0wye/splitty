export type ExpenseType = 'expense' | 'payment';
export type SplitMode = 'equal' | 'custom' | 'percentage';

export interface User { id: number; name: string; email: string; avatarUrl?: string | null; createdAt: string; updatedAt: string }
export interface GroupMember { id: number; userId: number; name: string; email: string; avatarUrl: string }
export interface Group { id: number; name: string; description?: string | null; netBalance: number; createdAt: string; members: GroupMember[] }
/** POST/PUT group mutations return the persistence entity, not the list DTO. */
export interface GroupMutationResponse { id: number; name: string; description?: string | null; createdAt?: string }
export interface ExpenseSplit { id: number; expenseId: number; userId: number; amount: number; percentage?: number | null; user: User }
export interface Expense { id: number; groupId: number; paidBy: number; amount: number; description: string; type: ExpenseType; splitMode?: SplitMode | null; date?: string | null; createdAt: string; updatedAt: string; paidByUser: User; splits: ExpenseSplit[] }
export interface Balance { id: number; userId: number; groupId: number; peerId: number; amount: number; user: User; peer: User }
export interface BalanceSummary { balances: Balance[]; balancesPending: boolean }
export interface Invite { code: string; groupId: number; createdAt: string; expiresAt: string; maxUses?: number | null; usedCount: number }
export interface LoginResponse { token: string; user: User }
export interface ExpenseSplitRequest { userId: number; amount: number; percentage?: number }
export interface CreateExpenseRequest { paidBy: number; amount: number; description: string; date?: string; splitMode: SplitMode; splits: ExpenseSplitRequest[] }
export interface UpdateExpenseRequest { paidBy?: number; amount?: number; description?: string; date?: string; splitMode?: SplitMode; splits?: ExpenseSplitRequest[] }
export interface ApiErrorPayload { statusCode?: number; message?: string; errors?: Record<string, string[] | string> }
