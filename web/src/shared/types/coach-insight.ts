export interface CoachInsight {
  id: number;
  insight_type: string;
  title: string;
  message: string;
  severity: "info" | "warning" | "success";
  source: string;
  read_at: string | null;
  created_at: string;
}
