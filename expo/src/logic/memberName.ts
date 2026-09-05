export function memberDisplayName(userId: number, name: string, currentUserId: number | undefined): string {
  return currentUserId !== undefined && userId === currentUserId ? 'You' : name;
}
