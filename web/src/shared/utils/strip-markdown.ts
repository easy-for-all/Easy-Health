export function stripMarkdown(text: string): string {
  if (!text) return text;
  return text
    .replace(/\*\*(.+?)\*\*/gs, "$1")
    .replace(/__(.+?)__/gs, "$1")
    .replace(/\*(.+?)\*/gs, "$1")
    .replace(/_(.+?)_/gs, "$1")
    .replace(/`(.+?)`/gs, "$1")
    .replace(/#{1,6}\s+/g, "")
    .replace(/<[^>]+>/g, "")
    .replace(/^\s*[-*+]\s/gm, "")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .trim();
}
