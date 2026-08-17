/** API が返すエラー。onError でJSONレスポンスへ変換される。 */
export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message?: string,
  ) {
    super(message ?? code);
    this.name = 'ApiError';
  }
}

export const unauthorized = (code = 'unauthorized', message?: string) =>
  new ApiError(401, code, message);

export const badRequest = (code = 'bad_request', message?: string) =>
  new ApiError(400, code, message);
