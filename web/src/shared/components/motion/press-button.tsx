"use client";

import { motion, HTMLMotionProps } from "framer-motion";
import { forwardRef } from "react";

type PressButtonProps = HTMLMotionProps<"button"> & {
  children: React.ReactNode;
};

export const PressButton = forwardRef<HTMLButtonElement, PressButtonProps>(
  ({ children, ...props }, ref) => (
    <motion.button
      ref={ref}
      whileTap={{ scale: 0.97 }}
      transition={{ duration: 0.12, ease: "easeOut" }}
      {...props}
    >
      {children}
    </motion.button>
  )
);

PressButton.displayName = "PressButton";
