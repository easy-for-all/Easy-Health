"use client";

import { useEffect, useRef } from "react";
import { useMotionValue, useSpring, useTransform, motion } from "framer-motion";

type AnimatedCounterProps = {
  value: number;
  format?: (v: number) => string;
  className?: string;
};

export function AnimatedCounter({
  value,
  format = (v) => Math.round(v).toString(),
  className,
}: AnimatedCounterProps) {
  const motionValue = useMotionValue(value);
  const spring = useSpring(motionValue, { stiffness: 100, damping: 20 });
  const display = useTransform(spring, format);
  const prevRef = useRef(value);

  useEffect(() => {
    if (prevRef.current !== value) {
      motionValue.set(value);
      prevRef.current = value;
    }
  }, [value, motionValue]);

  return <motion.span className={className}>{display}</motion.span>;
}
