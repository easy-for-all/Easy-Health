import type { Metadata } from "next";
import { PublicLayout } from "@/shared/components/public-layout";
import { LandingHero } from "@/shared/components/landing-hero";
import { CTASection } from "@/shared/components/cta-section";

export const metadata: Metadata = {
  title: "Treino para Emagrecimento | EasyHealth",
  description: "Monte uma rotina de treino inteligente para emagrecimento, com acompanhamento de evolução e apoio de IA.",
};

export default function Emagrecimento() {
  return (
    <PublicLayout>
      <LandingHero
        title="Treino para emagrecimento com foco em constância e evolução"
        subtitle="Organizar uma rotina de treino é o primeiro passo para resultados reais. A EasyHealth ajuda você a criar e manter um planejamento de treino focado nos seus objetivos."
        ctaText="Começar minha rotina"
        ctaHref="/sign-up"
        secondaryText="Ver planos"
        secondaryHref="/precos"
      />

      {/* O que faz diferença */}
      <section className="bg-gray-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">O que realmente faz diferença no processo de emagrecimento</h2>
          <p className="mt-4 leading-relaxed text-gray-600">
            Pesquisas mostram que consistência é mais importante do que intensidade. Treinar de forma regular, registrar evoluções e ajustar o plano ao longo do tempo são os fatores que mais contribuem para resultados sustentáveis.
          </p>
          <p className="mt-4 leading-relaxed text-gray-600">
            A EasyHealth foca exatamente nisso: ajudar você a criar uma rotina de treino que caiba na sua vida e que você consiga manter.
          </p>
          <p className="mt-6 rounded-xl border border-amber-200 bg-amber-50 px-5 py-4 text-sm text-amber-800">
            ⚠️ A EasyHealth não promete resultados específicos nem substituição de orientação nutricional. Para objetivos de composição corporal, combine o treino com acompanhamento profissional adequado.
          </p>
        </div>
      </section>

      {/* Como a EasyHealth ajuda */}
      <section className="py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Como a EasyHealth apoia sua rotina</h2>
          <div className="mt-8 space-y-6">
            {[
              { icon: "📋", title: "Plano de treino estruturado", text: "A IA monta um planejamento semanal com exercícios adequados ao seu objetivo, nível e disponibilidade de tempo." },
              { icon: "📈", title: "Acompanhamento de evolução", text: "Registre pesos e repetições a cada sessão e acompanhe sua evolução semana a semana." },
              { icon: "🔄", title: "Variedade e progressão", text: "O plano é ajustado conforme você evolui, mantendo o corpo em adaptação constante." },
              { icon: "⏱️", title: "Consistência facilitada", text: "Com o treino do dia sempre pronto no app, você reduz a fricção para começar e manter a rotina." },
            ].map((item) => (
              <div key={item.title} className="flex gap-4">
                <span className="flex-shrink-0 text-2xl">{item.icon}</span>
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
          <h2 className="text-2xl font-bold text-gray-900">O que você ganha com a EasyHealth</h2>
          <ul className="mt-6 space-y-3">
            {[
              "Treino estruturado e alinhado com seu objetivo",
              "Histórico de sessões para acompanhar o progresso",
              "Adaptação do plano conforme sua evolução",
              "Exercícios para academia, casa ou espaço ao ar livre",
              "Sugestões de substituição de exercício quando necessário",
              "Menos decisões, mais ação",
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
        title="Comece sua rotina hoje"
        subtitle="7 dias grátis para testar tudo. Sem compromisso, sem cartão de crédito para começar."
        ctaText="Criar minha conta"
        ctaHref="/sign-up"
      />
    </PublicLayout>
  );
}
