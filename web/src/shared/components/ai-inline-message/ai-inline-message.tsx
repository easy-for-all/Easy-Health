import { AgentOrb } from "@/shared/components/agent-orb";
import "./ai-inline-message.css";

type AIInlineMessageProps = {
  message: string;
  title?: string;
  variant?: "default" | "tip" | "warn" | "hot";
  showOrb?: boolean;
  /** Only use with trusted/sanitized server-generated content. */
  htmlContent?: boolean;
  className?: string;
};

export function AIInlineMessage({
  message,
  title = "Coach EasyHealth",
  variant = "default",
  showOrb = true,
  htmlContent = false,
  className = "",
}: AIInlineMessageProps) {
  return (
    <div
      className={`ai-inline-msg ${className}`}
      data-variant={variant}
      role="note"
    >
      <div className="aim-head">
        {showOrb && <AgentOrb size="card" glyph />}
        <b>{title}</b>
        <span className="aim-tag" aria-hidden="true">IA</span>
      </div>
      {htmlContent ? (
        <p dangerouslySetInnerHTML={{ __html: message }} />
      ) : (
        <p>{message}</p>
      )}
    </div>
  );
}
