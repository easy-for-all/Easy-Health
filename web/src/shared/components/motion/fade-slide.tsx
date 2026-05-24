"use client";

import { AnimatePresence, motion } from "framer-motion";

type Direction = "up" | "down" | "left" | "right";

const offsets: Record<Direction, { x: number; y: number }> = {
  up:    { x: 0,   y: 16  },
  down:  { x: 0,   y: -16 },
  left:  { x: 16,  y: 0   },
  right: { x: -16, y: 0   },
};

type FadeSlideProps = {
  id: string | number;
  direction?: Direction;
  duration?: number;
  children: React.ReactNode;
  className?: string;
};

export function FadeSlide({
  id,
  direction = "up",
  duration = 0.2,
  children,
  className,
}: FadeSlideProps) {
  const { x, y } = offsets[direction];
  return (
    <AnimatePresence mode="wait">
      <motion.div
        key={id}
        initial={{ opacity: 0, x, y }}
        animate={{ opacity: 1, x: 0, y: 0 }}
        exit={{ opacity: 0, x: -x, y: -y }}
        transition={{ duration, ease: "easeOut" }}
        className={className}
      >
        {children}
      </motion.div>
    </AnimatePresence>
  );
}
