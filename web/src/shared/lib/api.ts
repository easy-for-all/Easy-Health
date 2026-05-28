import { captureException } from "@/shared/lib/sentry";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

type HttpMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

export class ApiError extends Error {
  status: number;

  constructor(message: string, status: number) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

async function request<T>(method: HttpMethod, path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    method,
    credentials: "include",
    headers: { "Content-Type": "application/json" },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });

  const data = await res.json().catch(() => ({}));

  if (!res.ok) {
    const message = data?.error ?? data?.errors?.join(", ") ?? res.statusText ?? "Request failed";
    const err = new ApiError(message, res.status);
    if (res.status >= 500) {
      captureException(err, { path, method, status: res.status });
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
    const message = data?.error ?? data?.errors?.join(", ") ?? res.statusText ?? "Request failed";
    throw new ApiError(message, res.status);
  }

  return data as T;
}

export const api = {
  get: <T>(path: string) => request<T>("GET", path),
  post: <T>(path: string, body: unknown) => request<T>("POST", path, body),
  patch: <T>(path: string, body: unknown) => request<T>("PATCH", path, body),
  delete: <T>(path: string, body?: unknown) => request<T>("DELETE", path, body),
  upload: <T>(path: string, formData: FormData) => upload<T>("PATCH", path, formData),
  uploadPost: <T>(path: string, formData: FormData) => upload<T>("POST", path, formData),
};
