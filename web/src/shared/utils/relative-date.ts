/**
 * Calendar-day-aware relative date formatting (uses local timezone).
 * Compares by calendar day, NOT by 24-hour intervals.
 * "Yesterday" means calendar-day before today, even if only 1 hour has passed.
 */

function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function daysDiff(from: Date, to: Date): number {
  const fromDay = startOfDay(from).getTime();
  const toDay = startOfDay(to).getTime();
  return Math.round((toDay - fromDay) / 86400000);
}

/**
 * Returns a phrase like "feito hoje", "feito ontem", "há 3 dias", "há mais de 7 dias".
 * Use in exercise history cards where the "feito" prefix makes sense.
 */
export function relativeDate(dateStr: string | null | undefined): string {
  if (!dateStr) return "";
  const date = new Date(dateStr);
  if (isNaN(date.getTime())) return "";
  const diff = daysDiff(date, new Date());
  if (diff === 0) return "feito hoje";
  if (diff === 1) return "feito ontem";
  if (diff < 7) return `há ${diff} dias`;
  return "há mais de 7 dias";
}

/**
 * Returns a short label like "hoje", "ontem", "há 3 dias", "há mais de 7 dias".
 * Use in cards and labels where the "feito" prefix would be redundant.
 */
export function relativeDayLabel(dateStr: string | null | undefined): string {
  if (!dateStr) return "";
  const date = new Date(dateStr);
  if (isNaN(date.getTime())) return "";
  const diff = daysDiff(date, new Date());
  if (diff === 0) return "hoje";
  if (diff === 1) return "ontem";
  if (diff < 7) return `há ${diff} dias`;
  return "há mais de 7 dias";
}

/**
 * Returns true if the given date is today (by calendar day, local timezone).
 */
export function isToday(dateStr: string | null | undefined): boolean {
  if (!dateStr) return false;
  const date = new Date(dateStr);
  if (isNaN(date.getTime())) return false;
  return daysDiff(date, new Date()) === 0;
}
