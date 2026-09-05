/** Where a successful create/edit must land — the group, never the amount step. */
export function expenseFormReturnHref(groupId: number): `/(tabs)/group/${number}` {
  return `/(tabs)/group/${groupId}`;
}
