"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import type { TrainerMood } from "./ai-trainer-avatar";

type Props = {
  message: string;
  mood?: TrainerMood;
  show?: boolean;
  side?: "right" | "left";
  className?: string;
};

export function AITrainerBubble({
  message,
  mood = "speaking",
  show = true,
  side = "right",
  className = "",
}: Props) {
  const [displayText, setDisplayText] = useState("");
  const [isTyping, setIsTyping] = useState(true);

  useEffect(() => {
    if (!show || !message) {
      setDisplayText("");
      setIsTyping(false);
      return;
    }

    setDisplayText("");
    setIsTyping(true);

    let i = 0;
    const speed = Math.max(18, Math.min(40, Math.floor(1400 / message.length)));
    const timer = setInterval(() => {
      i++;
      setDisplayText(message.slice(0, i));
      if (i >= message.length) {
        clearInterval(timer);
        setIsTyping(false);
      }
    }, speed);

    return () => clearInterval(timer);
  }, [message, show]);

  return (
    <AnimatePresence>
      {show && (
        <motion.div
          initial={{ opacity: 0, scale: 0.85, y: 6 }}
          animate={{ opacity: 1, scale: 1, y: 0 }}
          exit={{ opacity: 0, scale: 0.85, y: 6 }}
          transition={{ duration: 0.2, ease: "easeOut" }}
          className={`relative max-w-xs ${className}`}
        >
          {/* Tail */}
          <div
            className={`absolute top-3 w-0 h-0 ${
              side === "right"
                ? "-left-2 border-t-[6px] border-t-transparent border-r-[8px] border-r-primary-100 border-b-[6px] border-b-transparent dark:border-r-primary-900"
                : "-right-2 border-t-[6px] border-t-transparent border-l-[8px] border-l-primary-100 border-b-[6px] border-b-transparent dark:border-l-primary-900"
            }`}
          />

          <div className="rounded-2xl border border-primary-100 bg-primary-50 px-3 py-2.5 shadow-sm dark:border-primary-800 dark:bg-primary-950">
            {isTyping && displayText.length === 0 ? (
              <div className="flex items-center gap-1 py-0.5">
                {[0, 1, 2].map((i) => (
                  <motion.span
                    key={i}
                    className="block h-1.5 w-1.5 rounded-full bg-primary-400"
                    animate={{ opacity: [0.3, 1, 0.3], y: [0, -3, 0] }}
                    transition={{ duration: 0.8, repeat: Infinity, delay: i * 0.15 }}
                  />
                ))}
              </div>
            ) : (
              <p className="text-xs leading-relaxed text-gray-700 dark:text-gray-200">
                {displayText}
                {isTyping && (
                  <motion.span
                    className="ml-0.5 inline-block h-3 w-0.5 bg-primary-400 align-middle"
                    animate={{ opacity: [1, 0] }}
                    transition={{ duration: 0.5, repeat: Infinity }}
                  />
                )}
              </p>
            )}
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
