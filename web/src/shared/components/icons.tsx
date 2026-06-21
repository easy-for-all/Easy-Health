// Shared icon components — stroke-based SVG, 24×24 viewBox, strokeWidth 1.8
// Usage: <IconUsers className="w-5 h-5" />

interface IconProps {
  className?: string;
  style?: React.CSSProperties;
}

const SVG_PROPS = {
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.8,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

export function IconUsers({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <circle cx="8" cy="8" r="3.5" />
      <path d="M1 21c0-3.8 3-7 7-7" />
      <circle cx="16" cy="8" r="3.5" />
      <path d="M23 21c0-3.8-3-7-7-7" />
      <path d="M9 14.3c1-.3 2.1-.3 3.4-.1" />
    </svg>
  );
}

export function IconUserPlus({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <circle cx="10" cy="8" r="4" />
      <path d="M2 21c0-4 3.6-7 8-7" />
      <line x1="18" y1="13" x2="18" y2="21" />
      <line x1="14" y1="17" x2="22" y2="17" />
    </svg>
  );
}

export function IconUserCheck({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <circle cx="10" cy="8" r="4" />
      <path d="M2 21c0-4 3.6-7 8-7" />
      <polyline points="14 17 16.5 19.5 21 15" />
    </svg>
  );
}

export function IconBell({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
      <path d="M13.73 21a2 2 0 0 1-3.46 0" />
    </svg>
  );
}

export function IconShare({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <circle cx="18" cy="5" r="3" />
      <circle cx="6" cy="12" r="3" />
      <circle cx="18" cy="19" r="3" />
      <line x1="8.59" y1="13.51" x2="15.42" y2="17.49" />
      <line x1="15.41" y1="6.51" x2="8.59" y2="10.49" />
    </svg>
  );
}

export function IconLink({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
      <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
    </svg>
  );
}

export function IconMedal({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <circle cx="12" cy="15" r="6" />
      <path d="M8.5 8.5L7 3h10l-1.5 5.5" />
      <line x1="12" y1="9" x2="12" y2="12" />
    </svg>
  );
}

export function IconTrophy({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <path d="M6 9H4a2 2 0 0 1 0-4h2" />
      <path d="M18 9h2a2 2 0 0 0 0-4h-2" />
      <path d="M6 2h12v7a6 6 0 0 1-6 6 6 6 0 0 1-6-6V2z" />
      <line x1="12" y1="15" x2="12" y2="20" />
      <line x1="8" y1="20" x2="16" y2="20" />
    </svg>
  );
}

export function IconLock({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <rect x="3" y="11" width="18" height="11" rx="2" />
      <path d="M7 11V7a5 5 0 0 1 10 0v4" />
    </svg>
  );
}

export function IconLockOpen({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <rect x="3" y="11" width="18" height="11" rx="2" />
      <path d="M7 11V7a5 5 0 0 1 9.9-1" />
    </svg>
  );
}

export function IconEye({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}

export function IconEyeOff({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94" />
      <path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19" />
      <path d="M14.12 14.12a3 3 0 1 1-4.24-4.24" />
      <line x1="1" y1="1" x2="23" y2="23" />
    </svg>
  );
}

export function IconAlertTri({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
      <line x1="12" y1="9" x2="12" y2="13" />
      <line x1="12" y1="17" x2="12.01" y2="17" />
    </svg>
  );
}

export function IconMessage({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
    </svg>
  );
}

export function IconSend({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <line x1="22" y1="2" x2="11" y2="13" />
      <polygon points="22 2 15 22 11 13 2 9 22 2" />
    </svg>
  );
}

export function IconGift({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <polyline points="20 12 20 22 4 22 4 12" />
      <rect x="2" y="7" width="20" height="5" />
      <line x1="12" y1="22" x2="12" y2="7" />
      <path d="M12 7H7.5a2.5 2.5 0 0 1 0-5C11 2 12 7 12 7z" />
      <path d="M12 7h4.5a2.5 2.5 0 0 0 0-5C13 2 12 7 12 7z" />
    </svg>
  );
}

export function IconTrendUp2({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <polyline points="23 6 13.5 15.5 8.5 10.5 1 18" />
      <polyline points="17 6 23 6 23 12" />
    </svg>
  );
}

export function IconPause({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <rect x="6" y="4" width="4" height="16" rx="1" />
      <rect x="14" y="4" width="4" height="16" rx="1" />
    </svg>
  );
}

export function IconWhistle({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <circle cx="9" cy="13" r="5" />
      <path d="M14 13h7l1-5H9" />
      <circle cx="9" cy="13" r="2" fill="currentColor" stroke="none" />
    </svg>
  );
}

export function IconFlag({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z" />
      <line x1="4" y1="22" x2="4" y2="15" />
    </svg>
  );
}

export function IconBan({ className = "w-6 h-6", style }: IconProps) {
  return (
    <svg {...SVG_PROPS} className={className} style={style}>
      <circle cx="12" cy="12" r="10" />
      <line x1="4.93" y1="4.93" x2="19.07" y2="19.07" />
    </svg>
  );
}
