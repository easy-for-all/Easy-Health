const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

const DEFAULT_TIMEOUT_MS = 15_000;

type HttpMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

export interface RequestOptions {
  timeout?: number;
}

export class ApiError extends Error {
  status: number;
  errorCode?: string;
  requestId?: string;

  constructor(message: string, status: number, errorCode?: string, requestId?: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.errorCode = errorCode;
    this.requestId = requestId;
  }
}

export const TRIAL_EXPIRED_EVENT = "app:trial_expired";

function errorDetails(data: Record<string, unknown>, statusText: string) {
  const nested = typeof data?.error === "object" && data.error !== null
    ? data.error as Record<string, unknown>
    : null;
  const errorCode =
    (typeof nested?.code === "string" ? nested.code : undefined) ??
    (typeof data?.error_code === "string" ? data.error_code : undefined) ??
    (typeof data?.error === "string" ? data.error : undefined);
  const requestId =
    (typeof nested?.request_id === "string" ? nested.request_id : undefined) ??
    (typeof data?.request_id === "string" ? data.request_id : undefined);
  const message =
    (typeof nested?.message === "string" ? nested.message : undefined) ??
    (typeof data?.message === "string" ? data.message : undefined) ??
    (typeof data?.error === "string" ? data.error : undefined) ??
    (Array.isArray(data?.errors) ? data.errors.join(", ") : undefined) ??
    statusText ??
    "Request failed";

  return { errorCode, message, requestId };
}

async function request<T>(method: HttpMethod, path: string, body?: unknown, options?: RequestOptions): Promise<T> {
  const timeoutMs = options?.timeout ?? DEFAULT_TIMEOUT_MS;
  const res = await fetch(`${API_URL}${path}`, {
    method,
    credentials: "include",
    headers: { "Content-Type": "application/json" },
    body: body !== undefined ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(timeoutMs),
  });

  const data = await res.json().catch(() => ({}));

  if (!res.ok) {
    const { errorCode, message, requestId } = errorDetails(data, res.statusText);
    const err = new ApiError(message, res.status, errorCode, requestId);
    if (res.status === 402 && errorCode === "trial_expired" && typeof window !== "undefined") {
      window.dispatchEvent(new CustomEvent(TRIAL_EXPIRED_EVENT));
    }
    throw err;
  }

  return data as T;
}

async function upload<T>(method: HttpMethod, path: string, formData: FormData): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    method,
    credentials: "include",
    body: formData,
  });

  const data = await res.json().catch(() => ({}));

  if (!res.ok) {
    const { errorCode, message, requestId } = errorDetails(data, res.statusText);
    if (res.status === 402 && errorCode === "trial_expired" && typeof window !== "undefined") {
      window.dispatchEvent(new CustomEvent(TRIAL_EXPIRED_EVENT));
    }
    throw new ApiError(message, res.status, errorCode, requestId);
  }

  return data as T;
}

export const api = {
  get: <T>(path: string, options?: RequestOptions) => request<T>("GET", path, undefined, options),
  post: <T>(path: string, body: unknown, options?: RequestOptions) => request<T>("POST", path, body, options),
  patch: <T>(path: string, body: unknown, options?: RequestOptions) => request<T>("PATCH", path, body, options),
  delete: <T>(path: string, body?: unknown, options?: RequestOptions) => request<T>("DELETE", path, body, options),
  upload: <T>(path: string, formData: FormData) => upload<T>("PATCH", path, formData),
  uploadPost: <T>(path: string, formData: FormData) => upload<T>("POST", path, formData),
};
