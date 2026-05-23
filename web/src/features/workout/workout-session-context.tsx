"use client";

import { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";

const STORAGE_PREFIX = "wk_";
const KEY_START_TS = `${STORAGE_PREFIX}start_ts`;
const KEY_DAY_ID = `${STORAGE_PREFIX}day_id`;
const KEY_REST_END = `${STORAGE_PREFIX}rest_end_ts`;

interface WorkoutSessionState {
  startTime: Date | null;
  activeWorkoutDayId: number | null;
  elapsedSeconds: number;
  beginSession: (dayId: number) => void;
  endSession: () => void;
  saveRestEnd: (timestampMs: number | null) => void;
  getRestEnd: () => number | null;
}

const WorkoutSessionContext = createContext<WorkoutSessionState | null>(null);

function readStoredStartTime(): Date | null {
  try {
    const ts = sessionStorage.getItem(KEY_START_TS);
    if (!ts) return null;
    const d = new Date(ts);
    return isNaN(d.getTime()) ? null : d;
  } catch {
    return null;
  }
}

function readStoredDayId(): number | null {
  try {
    const v = sessionStorage.getItem(KEY_DAY_ID);
    return v ? parseInt(v, 10) : null;
  } catch {
    return null;
  }
}

export function WorkoutSessionProvider({ children }: { children: React.ReactNode }) {
  const [startTime, setStartTime] = useState<Date | null>(null);
  const [activeWorkoutDayId, setActiveWorkoutDayId] = useState<number | null>(null);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const tickRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Restore persisted session on mount
  useEffect(() => {
    const stored = readStoredStartTime();
    const storedDayId = readStoredDayId();
    if (stored) {
      setStartTime(stored);
      setActiveWorkoutDayId(storedDayId);
      setElapsedSeconds(Math.floor((Date.now() - stored.getTime()) / 1000));
    }
  }, []);

  // Drive elapsed timer whenever startTime is set
  useEffect(() => {
    if (tickRef.current) clearInterval(tickRef.current);
    if (!startTime) { setElapsedSeconds(0); return; }

    tickRef.current = setInterval(() => {
      setElapsedSeconds(Math.floor((Date.now() - startTime.getTime()) / 1000));
    }, 1000);

    return () => { if (tickRef.current) clearInterval(tickRef.current); };
  }, [startTime]);

  const beginSession = useCallback((dayId: number) => {
    const now = new Date();
    try {
      sessionStorage.setItem(KEY_START_TS, now.toISOString());
      sessionStorage.setItem(KEY_DAY_ID, String(dayId));
    } catch { /* storage unavailable */ }
    setStartTime(now);
    setActiveWorkoutDayId(dayId);
    setElapsedSeconds(0);
  }, []);

  const endSession = useCallback(() => {
    try {
      sessionStorage.removeItem(KEY_START_TS);
      sessionStorage.removeItem(KEY_DAY_ID);
      sessionStorage.removeItem(KEY_REST_END);
    } catch { /* storage unavailable */ }
    setStartTime(null);
    setActiveWorkoutDayId(null);
    setElapsedSeconds(0);
  }, []);

  const saveRestEnd = useCallback((timestampMs: number | null) => {
    try {
      if (timestampMs === null) {
        sessionStorage.removeItem(KEY_REST_END);
      } else {
        sessionStorage.setItem(KEY_REST_END, String(timestampMs));
      }
    } catch { /* storage unavailable */ }
  }, []);

  const getRestEnd = useCallback((): number | null => {
    try {
      const v = sessionStorage.getItem(KEY_REST_END);
      return v ? parseInt(v, 10) : null;
    } catch { return null; }
  }, []);

  return (
    <WorkoutSessionContext.Provider value={{ startTime, activeWorkoutDayId, elapsedSeconds, beginSession, endSession, saveRestEnd, getRestEnd }}>
      {children}
    </WorkoutSessionContext.Provider>
  );
}

export function useWorkoutSession(): WorkoutSessionState {
  const ctx = useContext(WorkoutSessionContext);
  if (!ctx) throw new Error("useWorkoutSession must be used inside WorkoutSessionProvider");
  return ctx;
}

export function formatElapsed(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}
