import { HttpError } from '@/api/errors';

/** Keep a restored JWT unless the server said it is unauthorized. */
export function shouldClearSession(error: unknown): boolean {
  return error instanceof HttpError && error.status === 401;
}
