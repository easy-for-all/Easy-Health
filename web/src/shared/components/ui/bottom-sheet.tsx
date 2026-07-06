"use client";

import { AnimatePresence, motion } from "framer-motion";
import "./bottom-sheet.css";

export function BottomSheet({ open, onClose, children, ariaLabel }: {
  open: boolean;
  onClose: () => void;
  children: React.ReactNode;
  ariaLabel: string;
}) {
  return (
    <AnimatePresence>
      {open && (
        <>
          <motion.div
            className="bsheet-scrim"
            onClick={onClose}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.3 }}
          />
          <motion.div
            className="bsheet"
            role="dialog"
            aria-label={ariaLabel}
            initial={{ y: "102%" }}
            animate={{ y: 0 }}
            exit={{ y: "102%" }}
            transition={{ duration: 0.42, ease: [0.22, 1, 0.36, 1] }}
          >
            <div className="bsheet-grabber" />
            <div className="bsheet-body">{children}</div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}
