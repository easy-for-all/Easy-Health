import type { Metadata } from "next";
import { PublicLayout } from "@/shared/components/public-layout";
import { LandingHero } from "@/shared/components/landing-hero";
import { CTASection } from "@/shared/components/cta-section";

export const metadata: Metadata = {
  title: "IA para Treino | EasyHealth",
  description: "Use inteligência artificial para criar treinos personalizados, acompanhar sua evolução e manter constância na sua rotina fitness.",
};

export default function IaParaTreino() {
  return (
    <PublicLayout>
      <LandingHero
        title="IA para treino: personalize sua rotina fitness com inteligência artificial"
        subtitle="Chega de treinos genéricos que não respeitam sua evolução. A EasyHealth usa IA para criar e ajustar seu planejamento de treino de forma inteligente."
        ctaText="Começar gratuitamente"
        ctaHref="/sign-up"
        secondaryText="Ver planos"
        secondaryHref="/precos"
      />

      {/* Problema */}
      <section className="bg-gray-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Treinos genéricos não acompanham sua evolução</h2>
          <p className="mt-4 leading-relaxed text-gray-600">
            Planilhas fixas, vídeos do YouTube e treinos copiados da internet têm um problema em comum: eles não sabem quem você é. Não sabem seu nível, sua frequência, seus pontos fracos nem o quanto você evoluiu.
          </p>
          <p className="mt-4 leading-relaxed text-gray-600">
            O resultado? Treinos fáceis demais quando você já poderia progredir. Ou treinos difíceis que geram lesão ou abandono. A IA da EasyHealth resolve isso.
          </p>
        </div>
      </section>

      {/* Como ajuda */}
      <section className="py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Como a EasyHealth usa IA no seu treino</h2>
          <div className="mt-8 space-y-6">
            {[
              { step: "1", title: "Análise do seu perfil", text: "A IA considera seu objetivo (hipertrofia, emagrecimento, saúde), nível de condicionamento, dias disponíveis e local de treino." },
              { step: "2", title: "Criação do plano personalizado", text: "Com base no seu perfil, a IA monta um planejamento semanal com exercícios, séries, repetições e tempos de descanso adequados para você." },
              { step: "3", title: "Ajustes contínuos", text: "Ao longo dos treinos, você registra pesos e sensações. A IA usa esses dados para manter o plano sempre alinhado com sua evolução real." },
              { step: "4", title: "Substituição inteligente", text: "Não tem um aparelho? Tirou foto do equipamento disponível e a IA sugere o exercício equivalente para não perder o treino." },
            ].map((item) => (
              <div key={item.step} className="flex gap-4">
                <span className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full bg-primary-100 text-sm font-bold text-primary-700">
                  {item.step}
                </span>
                <div>
                  <p className="font-semibold text-gray-900">{item.title}</p>
                  <p className="mt-1 text-sm leading-relaxed text-gray-500">{item.text}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Benefícios */}
      <section className="bg-primary-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Benefícios do treino com IA</h2>
          <ul className="mt-6 space-y-3">
            {[
              "Treino ajustado ao seu objetivo real, não ao de outra pessoa",
              "Acompanhamento de evolução semana a semana",
              "Histórico completo de treinos com cargas e repetições",
              "Sugestões inteligentes de substituição de exercícios",
              "Menos tempo decidindo, mais tempo treinando",
              "Progresso visível que mantém a motivação",
            ].map((item) => (
              <li key={item} className="flex items-start gap-3 text-gray-700">
                <span className="mt-0.5 text-primary-500">✓</span>
                {item}
              </li>
            ))}
          </ul>
        </div>
      </section>

      <CTASection
        title="Experimente 7 dias grátis"
        subtitle="Crie sua conta agora e veja como a IA monta um treino feito para você."
        ctaText="Começar agora"
        ctaHref="/sign-up"
      />
    </PublicLayout>
  );
}
