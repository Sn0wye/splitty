import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { router, useLocalSearchParams } from 'expo-router';
import { expenseFormReturnHref } from '@/nav/expenseForm';
import { api } from '@/api/client';
import { hapticSuccess } from '@/haptics';
import { AmountExpression } from '@/logic/amountExpression';
import { memberDisplayName } from '@/logic/memberName';
import { centsFromApi, parseTypedMoney, parseTypedPercentage, plainString } from '@/logic/money';
import { makeSplitPayload, memberIds, restoredSplit, splitAmounts, splitSummary, validateSplit } from '@/logic/split';
import { useAuth } from '@/auth/AuthContext';
import type { Expense, Group, SplitMode } from '@/types';
import { toApiDate } from '@/logic/date';

export type ExpenseFormValue = {
  status: 'ready';
  group: Group;
  display: string;
  description: string;
  setDescription: (value: string) => void;
  date: Date;
  setDate: (value: Date) => void;
  paidBy: number;
  setPaidBy: (value: number) => void;
  mode: SplitMode;
  setMode: (value: SplitMode) => void;
  participants: number[];
  setParticipants: React.Dispatch<React.SetStateAction<number[]>>;
  custom: Record<number, string>;
  setCustom: React.Dispatch<React.SetStateAction<Record<number, string>>>;
  percentages: Record<number, string>;
  setPercentages: React.Dispatch<React.SetStateAction<Record<number, string>>>;
  busy: boolean;
  saveError: string;
  totalCents: number;
  preview: Record<number, number>;
  summary: string;
  canSave: boolean;
  blocking?: string;
  you: (userId: number, name: string) => string;
  pressKey: (key: string) => void;
  save: () => Promise<void>;
};

type ExpenseFormState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | ExpenseFormValue;

const ExpenseFormContext = createContext<ExpenseFormState>({ status: 'loading' });

export function ExpenseFormProvider({ children }: { children: React.ReactNode }): React.JSX.Element {
  const { id, expenseId } = useLocalSearchParams<{ id: string; expenseId?: string }>();
  const groupId = Number(id);
  const editingId = expenseId ? Number(expenseId) : undefined;
  const { user } = useAuth();
  const expression = useMemo(() => new AmountExpression(), []);
  const loaded = useRef(false);
  const [group, setGroup] = useState<Group | null>(null);
  const [expense, setExpense] = useState<Expense | null>(null);
  const [description, setDescription] = useState('');
  const [date, setDate] = useState(new Date());
  const [display, setDisplay] = useState('0');
  const [paidBy, setPaidBy] = useState(0);
  const [mode, setMode] = useState<SplitMode>('equal');
  const [participants, setParticipants] = useState<number[]>([]);
  const [custom, setCustom] = useState<Record<number, string>>({});
  const [percentages, setPercentages] = useState<Record<number, string>>({});
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [saveError, setSaveError] = useState('');

  useEffect(() => {
    if (loaded.current) return;
    loaded.current = true;
    void (async () => {
      setLoading(true);
      try {
        const [nextGroup, nextExpense] = await Promise.all([
          api.group(groupId),
          editingId ? api.expense(groupId, editingId) : Promise.resolve(null)
        ]);
        setGroup(nextGroup);
        setExpense(nextExpense);
        const nextAmount = nextExpense ? centsFromApi(nextExpense.amount) : 0;
        setPaidBy(nextExpense?.paidBy ?? user?.id ?? nextGroup.members[0]?.userId ?? 0);
        setDescription(nextExpense?.description ?? '');
        setDate(nextExpense?.date ? new Date(nextExpense.date) : new Date());
        expression.replaceCents(nextAmount);
        setDisplay(expression.displayText);
        if (nextExpense) {
          const restored = restoredSplit(nextExpense);
          setMode(restored.mode);
          setParticipants(restored.participants);
          setCustom(Object.fromEntries(Object.entries(restored.custom).map(([key, value]) => [key, plainString(value)])));
          setPercentages(Object.fromEntries(Object.entries(restored.percentages).map(([key, value]) => [key, String(value)])));
        } else {
          setParticipants(memberIds(nextGroup.members));
        }
      } catch (error) {
        setLoadError(error instanceof Error ? error.message : 'Could not load this expense.');
      } finally {
        setLoading(false);
      }
    })();
  }, [editingId, expression, groupId, user]);

  const pressKey = useCallback((key: string) => {
    if (/^\d$/.test(key)) expression.typeDigit(Number(key));
    else if (key === '.') expression.typeDecimalPoint();
    else if (key === 'back') expression.backspace();
    setDisplay(expression.displayText);
  }, [expression]);

  const totalCents = expression.resolvedCents;
  const numericCustom = Object.fromEntries(Object.entries(custom).map(([key, value]) => [Number(key), value.trim() === '' ? 0 : parseTypedMoney(value) ?? Number.NaN]));
  const numericPercentages = Object.fromEntries(Object.entries(percentages).map(([key, value]) => [Number(key), value.trim() === '' ? 0 : parseTypedPercentage(value) ?? Number.NaN]));
  const validation = validateSplit(totalCents, mode, participants, numericCustom, numericPercentages);
  const preview = splitAmounts(totalCents, mode, participants, numericCustom, numericPercentages);
  const you = useCallback((memberUserId: number, name: string) => memberDisplayName(memberUserId, name, user?.id), [user]);
  const canSave = Boolean(group && description.trim()) && validation.valid && !busy;
  const starvedMember = validation.starvedUserId === undefined
    ? undefined
    : group?.members.find(member => member.userId === validation.starvedUserId);
  const blocking = totalCents <= 0
    ? undefined
    : validation.starvedUserId !== undefined
      ? `${you(validation.starvedUserId, starvedMember?.name ?? 'Participant')}'s share rounds down to nothing`
      : validation.message;

  const save = useCallback(async () => {
    if (!canSave || !group) return;
    setBusy(true);
    setSaveError('');
    try {
      const splits = makeSplitPayload(totalCents, mode, participants, numericCustom, numericPercentages);
      const dateValue = toApiDate(date);
      if (editingId && expense) {
        await api.updateExpense(groupId, editingId, { description: description.trim(), amountCents: totalCents, paidBy, date: dateValue, splitMode: mode, splits });
      } else {
        await api.createExpense(groupId, { description: description.trim(), amountCents: totalCents, paidBy, date: dateValue, splitMode: mode, splits });
      }
      hapticSuccess();
      router.dismissTo(expenseFormReturnHref(groupId));
    } catch (error) {
      setSaveError(error instanceof Error ? error.message : 'Try again.');
    } finally {
      setBusy(false);
    }
  }, [canSave, date, description, editingId, expense, group, groupId, mode, numericCustom, numericPercentages, paidBy, participants, totalCents]);

  let state: ExpenseFormState;
  if (loading) state = { status: 'loading' };
  else if (loadError || !group || (editingId !== undefined && !expense)) {
    state = { status: 'error', message: loadError || 'Expense not found.' };
  } else {
    state = {
      status: 'ready',
      group,
      display,
      description,
      setDescription,
      date,
      setDate,
      paidBy,
      setPaidBy,
      mode,
      setMode,
      participants,
      setParticipants,
      custom,
      setCustom,
      percentages,
      setPercentages,
      busy,
      saveError,
      totalCents,
      preview,
      summary: splitSummary({
        payerId: paidBy,
        currentUserId: user?.id ?? 0,
        members: group.members,
        mode,
        participants,
        percentages: numericPercentages
      }),
      canSave,
      blocking,
      you,
      pressKey,
      save
    };
  }

  return <ExpenseFormContext.Provider value={state}>{children}</ExpenseFormContext.Provider>;
}

export function useExpenseFormState(): ExpenseFormState {
  return useContext(ExpenseFormContext);
}

export function useExpenseForm(): ExpenseFormValue {
  const value = useContext(ExpenseFormContext);
  if (value.status !== 'ready') throw new Error('Expense form is not ready');
  return value;
}
