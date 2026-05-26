"use client";

import { useRef, useState } from "react";
import { toPng } from "html-to-image";
import { motion, AnimatePresence } from "framer-motion";
import { ShareCard } from "./share-card";
import { PressButton } from "../motion";

type ShareButtonProps = {
  workoutName: string;
  durationMinutes: number;
  volumeKg: number;
  exerciseCount: number;
  muscles: string[];
  hasPR?: boolean;
  caloriesEstimated?: number;
};

export function ShareButton({ workoutName, durationMinutes, volumeKg, exerciseCount, muscles, hasPR, caloriesEstimated }: ShareButtonProps) {
  const cardRef = useRef<HTMLDivElement>(null);
  const [showCard, setShowCard] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);

  async function handleShare() {
    if (!cardRef.current) return;
    setExporting(true);
    setExportError(null);
    try {
      const dataUrl = await toPng(cardRef.current, { pixelRatio: 2, skipAutoScale: true });
      const blob = await (await fetch(dataUrl)).blob();
      const file = new File([blob], "easyhealth-treino.png", { type: "image/png" });

      if (navigator.share && navigator.canShare?.({ files: [file] })) {
        await navigator.share({ files: [file], title: "Meu treino no EasyHealth" });
      } else {
        const link = document.createElement("a");
        link.href = dataUrl;
        link.download = "easyhealth-treino.png";
        link.click();
      }
    } catch {
      setExportError("Não foi possível gerar a imagem. Tente novamente.");
    } finally {
      setExporting(false);
    }
  }

  return (
    <div className="w-full">
      <PressButton
        onClick={() => setShowCard((v) => !v)}
        className="w-full rounded-2xl border border-gray-200 py-3.5 text-sm font-semibold text-gray-700"
      >
        {showCard ? "Fechar prévia" : "🎯 Compartilhar treino"}
      </PressButton>

      <AnimatePresence>
        {showCard && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            className="overflow-hidden"
          >
            <div className="mt-4 flex flex-col items-center gap-4">
              <ShareCard
                ref={cardRef}
                workoutName={workoutName}
                durationMinutes={durationMinutes}
                volumeKg={volumeKg}
                exerciseCount={exerciseCount}
                muscles={muscles}
                hasPR={hasPR}
                caloriesEstimated={caloriesEstimated}
              />
              {exportError && (
                <p className="w-full max-w-[360px] rounded-lg bg-red-50 px-3 py-2 text-xs text-red-600">{exportError}</p>
              )}
              <PressButton
                onClick={handleShare}
                disabled={exporting}
                className="w-full max-w-[360px] rounded-2xl bg-gray-900 py-3.5 text-sm font-semibold text-white disabled:opacity-50"
              >
                {exporting ? "Gerando..." : "Baixar / Compartilhar"}
              </PressButton>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
