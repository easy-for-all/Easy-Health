"use client";

import Image from "next/image";

interface AvatarProps {
  name: string;
  avatarUrl?: string | null;
  hue?: number;
  size?: number;
  className?: string;
}

function initialsFromName(name: string): string {
  const parts = name.trim().split(/\s+/);
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function hueFromName(name: string): number {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) % 360;
  return h;
}

export function Avatar({ name, avatarUrl, hue, size = 40, className = "" }: AvatarProps) {
  const resolvedHue = hue ?? hueFromName(name);
  const bg = `oklch(0.42 0.13 ${resolvedHue})`;
  const fg = `oklch(0.95 0.04 ${resolvedHue})`;

  const style: React.CSSProperties = {
    width: size,
    height: size,
    borderRadius: "50%",
    flexShrink: 0,
    overflow: "hidden",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    background: bg,
    color: fg,
    fontSize: size * 0.38,
    fontWeight: 700,
    letterSpacing: "-0.01em",
    userSelect: "none",
  };

  if (avatarUrl) {
    const fullUrl = avatarUrl.startsWith("http")
      ? avatarUrl
      : `${process.env.NEXT_PUBLIC_API_URL ?? ""}${avatarUrl}`;
    return (
      <div style={style} className={className}>
        <Image src={fullUrl} alt={name} width={size} height={size} style={{ objectFit: "cover", width: "100%", height: "100%" }} />
      </div>
    );
  }

  return (
    <div style={style} className={className} aria-label={name}>
      {initialsFromName(name)}
    </div>
  );
}
