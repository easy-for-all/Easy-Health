"use client";

import { motion } from "framer-motion";
import "@/shared/components/ui/ui.css";

export function GeneratingView({ step, steps, offsetParent = false }: { step: number; steps: string[]; offsetParent?: boolean }) {
  const allDone = step >= steps.length - 1;

  return (
    <div className="gen-stage" style={{ margin: offsetParent ? "-52px -20px 0" : 0, minHeight: "100svh" }}>
      <div className="ai-orb-lg">
        <svg viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"
          style={{ width: 40, height: 40, position: "relative", zIndex: 1 }}>
          <path d="M12 3l1.6 4.4L18 9l-4.4 1.6L12 15l-1.6-4.4L6 9l4.4-1.6L12 3z" />
          <path d="M19 14l.7 1.9L21.6 17l-1.9.7L19 19.6l-.7-1.9L16.4 17l1.9-.7L19 14z" />
        </svg>
      </div>

      <div>
        <h2 style={{ fontFamily: "var(--font-display)", fontSize: 22, fontWeight: 700, margin: "0 0 6px", letterSpacing: "-0.015em" }}>
          Criando seu plano...
        </h2>
        <p style={{ fontSize: 14, color: "var(--text-muted)", margin: 0 }}>
          {allDone ? "A IA está refinando seu plano, aguarde..." : (steps[step] ?? "Finalizando...")}
        </p>
      </div>

      <div className="gen-steps">
        {steps.map((msg, idx) => {
          const cls = idx < step ? "gen-ln complete" : idx === step ? "gen-ln active" : "gen-ln";
          return (
            <motion.div
              key={idx}
              className={cls}
              initial={{ opacity: 0, x: -8 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: idx * 0.08, duration: 0.25 }}
            >
              <span className="gck" />
              {msg}
            </motion.div>
          );
        })}
        {allDone && (
          <motion.div
            className="gen-ln active"
            initial={{ opacity: 0 }}
            animate={{ opacity: [0.4, 1, 0.4] }}
            transition={{ duration: 1.4, repeat: Infinity }}
          >
            <span className="gck" />
            Aguardando resposta da IA...
          </motion.div>
        )}
      </div>
    </div>
  );
}
