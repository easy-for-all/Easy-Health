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

async function captureCard(el: HTMLElement): Promise<string> {
  const opts = {
    pixelRatio: 2,
    skipAutoScale: true,
    cacheBust: true,
    skipFonts: false,
    includeQueryParams: true,
  };
  // html-to-image sometimes needs a warm-up pass to load embedded resources
  await toPng(el, { ...opts, pixelRatio: 1 }).catch(() => null);
  return toPng(el, opts);
}

function dataUrlToBlob(dataUrl: string): Blob {
  const [header, base64] = dataUrl.split(",");
  const mime = header.match(/:(.*?);/)?.[1] ?? "image/png";
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new Blob([bytes], { type: mime });
}

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
      const dataUrl = await captureCard(cardRef.current);
      const blob = dataUrlToBlob(dataUrl);
      const file = new File([blob], "easyhealth-treino.png", { type: "image/png" });

      if (navigator.share && navigator.canShare?.({ files: [file] })) {
        await navigator.share({ files: [file], title: "Meu treino no EasyHealth" });
      } else {
        const link = document.createElement("a");
        link.href = URL.createObjectURL(blob);
        link.download = "easyhealth-treino.png";
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        setTimeout(() => URL.revokeObjectURL(link.href), 5000);
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
        className="w-full rounded-2xl border border-gray-200 py-3.5 text-sm font-semibold text-gray-700 dark:border-gray-700 dark:text-gray-300"
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
                {exporting ? "Gerando imagem..." : "Baixar / Compartilhar"}
              </PressButton>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
