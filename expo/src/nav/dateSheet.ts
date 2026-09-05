/** Swift `presentationDetents([.height(460)])`. Expo Router detents are height ratios. */
export const EXPENSE_DATE_SHEET_HEIGHT = 460;

export function expenseDateSheetDetent(windowHeight: number): number {
  if (windowHeight <= 0) return 1;
  return Math.min(1, EXPENSE_DATE_SHEET_HEIGHT / windowHeight);
}
