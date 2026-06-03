"use client";

import { useState, useEffect, useCallback } from "react";
import { api } from "@/shared/lib/api";
import type { ClientSummary, ClientDetail, PersonalDashboard, InvitationResult } from "@/shared/types/personal";

export function usePersonalDashboard() {
  const [dashboard, setDashboard] = useState<PersonalDashboard | null>(null);
  const [clients, setClients] = useState<ClientSummary[]>([]);
  const [loading, setLoading] = useState(true);

  const fetch = useCallback(async () => {
    try {
      const data = await api.get<{ dashboard: PersonalDashboard; clients: ClientSummary[] }>("/api/v1/personal/dashboard");
      setDashboard(data.dashboard);
      setClients(data.clients);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetch(); }, [fetch]);

  return { dashboard, clients, loading, refetch: fetch };
}

export function usePersonalClients() {
  const [clients, setClients] = useState<ClientSummary[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api.get<{ clients: ClientSummary[] }>("/api/v1/personal/clients")
      .then((data) => setClients(data.clients))
      .finally(() => setLoading(false));
  }, []);

  return { clients, loading };
}

export function usePersonalClient(clientId: string) {
  const [client, setClient] = useState<ClientDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  useEffect(() => {
    api.get<{ client: ClientDetail }>(`/api/v1/personal/clients/${clientId}`)
      .then((data) => setClient(data.client))
      .catch(() => setNotFound(true))
      .finally(() => setLoading(false));
  }, [clientId]);

  return { client, loading, notFound };
}

export function useCreateInvitation() {
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<InvitationResult | null>(null);

  const create = useCallback(async () => {
    setLoading(true);
    try {
      const data = await api.post<InvitationResult>("/api/v1/personal/invitations", {});
      setResult(data);
      return data;
    } finally {
      setLoading(false);
    }
  }, []);

  return { create, loading, result };
}
