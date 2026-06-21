import Link from "next/link";
import { Avatar } from "../ui/avatar";
import { AdherenceRing } from "../ui/adherence-ring";
import { RiskChip } from "../ui/risk-chip";

type RiskLevel = "high" | "med" | "low";

export interface Student {
  id: number;
  name: string;
  hue?: number;
  avatarUrl?: string | null;
  goal?: string;
  adherencePct: number;
  riskLevel: RiskLevel;
  status?: string;
  daysInactive?: number;
}

interface StudentCardProps {
  student: Student;
}

export function StudentCard({ student }: StudentCardProps) {
  const lastSeen = student.daysInactive != null
    ? student.daysInactive === 0
      ? "Treinou hoje"
      : student.daysInactive === 1
        ? "Treinou ontem"
        : `${student.daysInactive}d sem treinar`
    : undefined;

  return (
    <Link
      href={`/personal/students/${student.id}`}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 12,
        padding: "14px 16px",
        background: "var(--surface)",
        borderRadius: "var(--r-lg)",
        border: "1px solid var(--border)",
        textDecoration: "none",
        transition: "border-color .18s",
      }}
    >
      <Avatar name={student.name} avatarUrl={student.avatarUrl} hue={student.hue} size={44} />

      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 6, flexWrap: "wrap" }}>
          <span style={{ fontWeight: 700, fontSize: 15, color: "var(--text)" }}>
            {student.name}
          </span>
          <RiskChip level={student.riskLevel} />
        </div>
        {student.goal && (
          <p style={{ margin: "2px 0 0", fontSize: 12, color: "var(--text-muted)", lineHeight: 1.3 }}>
            {student.goal}
          </p>
        )}
        {lastSeen && (
          <p style={{ margin: "2px 0 0", fontSize: 11, color: "var(--text-dim)" }}>
            {lastSeen}
          </p>
        )}
      </div>

      <AdherenceRing pct={student.adherencePct} size={52} />
    </Link>
  );
}
