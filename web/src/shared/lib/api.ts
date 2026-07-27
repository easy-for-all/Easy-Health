import { getAnalyticsContext, getCachedInstallationId } from "./analytics/context";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

// X-Installation-Id lets the backend re-link this installation to the signed-in
// user on any authenticated request (see AppInstallationReconciliation), instead
// of depending on a fire-and-forget register that may never run after login.
// Read from context.ts (not installation.ts) to avoid an import cycle back here.
function installationHeader(): Record<string, string> {
  const installationId = getCachedInstallationId();
  return installationId ? { "X-Installation-Id": installationId } : {};
}

// Correlation headers consumed by Observability::Headers on the backend, where
// they become the platform/version/build dimensions on logs, events and health
// checks. Without them the server cannot tell which build a failure came from.
//
// Every header is omitted when its value is missing: the analytics context is
// not populated on the very first paint, and sending the string "undefined"
// would create a bogus dimension value that survives forever in the data.
function correlationHeaders(): Record<string, string> {
  try {
    const context = getAnalyticsContext();
    const headers: Record<string, string> = {};

    if (context.platform) headers["X-Platform"] = context.platform;
    if (context.app_version) headers["X-App-Version"] = context.app_version;
    if (context.build_number) headers["X-App-Build"] = context.build_number;
    if (context.session_id) headers["X-Session-Id"] = context.session_id;

    return headers;
  } catch {
    // Diagnostics must never break a request.
    return {};
  }
}

function contextHeaders(): Record<string, string> {
  return { ...installationHeader(), ...correlationHeaders() };
}

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
    headers: { "Content-Type": "application/json", ...contextHeaders() },
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
    // No Content-Type here on purpose: the browser must set the multipart boundary.
    headers: contextHeaders(),
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
