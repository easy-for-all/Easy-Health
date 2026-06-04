/* ============================================================
   EasyHealth Pro — painel de Tweaks (ilha React)
   Ajusta os tokens CSS que comandam o sistema Lumen inteiro.
   ============================================================ */
const { useEffect } = React;

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "accent": "#6a78ee",
  "displayFont": "Bricolage",
  "corners": "padrão",
  "neonGlow": true,
  "uiScale": 100
}/*EDITMODE-END*/;

// presets de acento → matiz/croma em oklch (texto branco sempre legível)
const ACCENTS = {
  "#6a78ee": { h: 258, c: 0.17 }, // azul (padrão)
  "#9b73e8": { h: 286, c: 0.16 }, // índigo
  "#d264c4": { h: 328, c: 0.15 }, // magenta
  "#39a7d6": { h: 222, c: 0.115 } // azul-petróleo
};
const FONTS = {
  "Bricolage": '"Bricolage Grotesque", system-ui, sans-serif',
  "Hanken": '"Hanken Grotesk", system-ui, sans-serif',
  "Space": '"Space Grotesk", system-ui, sans-serif',
  "Archivo": '"Archivo", system-ui, sans-serif'
};
const CORNERS = { "reto": 0.65, "padrão": 1, "redondo": 1.35 };

function ProTweaks() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);

  useEffect(() => {
    const r = document.documentElement.style;
    const a = ACCENTS[t.accent] || ACCENTS["#6a78ee"];
    r.setProperty("--accent-h", a.h);
    r.setProperty("--accent-c", a.c);
    r.setProperty("--font-display", FONTS[t.displayFont] || FONTS.Bricolage);
    r.setProperty("--radius-scale", CORNERS[t.corners] != null ? CORNERS[t.corners] : 1);
    r.setProperty("--glow-strength", t.neonGlow ? 1 : 0.25);
    // escala do device (não mexe nos tokens, só no frame)
    const dev = document.querySelector(".device");
    if (dev) dev.style.zoom = (t.uiScale || 100) / 100;
  }, [t]);

  return (
    <TweaksPanel title="Tweaks">
      <TweakSection label="Identidade" />
      <TweakColor label="Acento" value={t.accent}
        options={Object.keys(ACCENTS)}
        onChange={(v) => setTweak("accent", v)} />
      <TweakSelect label="Fonte de título" value={t.displayFont}
        options={Object.keys(FONTS)}
        onChange={(v) => setTweak("displayFont", v)} />

      <TweakSection label="Forma & efeito" />
      <TweakRadio label="Cantos" value={t.corners}
        options={Object.keys(CORNERS)}
        onChange={(v) => setTweak("corners", v)} />
      <TweakToggle label="Brilho neon" value={t.neonGlow}
        onChange={(v) => setTweak("neonGlow", v)} />

      <TweakSection label="Visualização" />
      <TweakSlider label="Escala do app" value={t.uiScale} min={80} max={120} step={5} unit="%"
        onChange={(v) => setTweak("uiScale", v)} />
    </TweaksPanel>
  );
}

ReactDOM.createRoot(document.getElementById("eh-tweaks-root")).render(<ProTweaks />);
