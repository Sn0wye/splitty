/** Empty 200/204/202 bodies are success with no payload, matching Swift EmptyResponse. */
export function decodeSuccessBody<T>(status: number, text: string): T {
  if (status === 204 || status === 202 || text.trim() === '') return undefined as T;
  return JSON.parse(text) as T;
}
