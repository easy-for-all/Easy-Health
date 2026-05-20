import type { Metadata } from "next";
import { PublicLayout } from "@/shared/components/public-layout";
import { LandingHero } from "@/shared/components/landing-hero";
import { CTASection } from "@/shared/components/cta-section";

export const metadata: Metadata = {
  title: "Treino Personalizado | EasyHealth",
  description: "Crie uma rotina de treino personalizada com apoio de IA, ajustada ao seu objetivo, disponibilidade e evolução.",
};

export default function TreinoPersonalizado() {
  return (
    <PublicLayout>
      <LandingHero
        title="Treino personalizado para sua rotina, objetivo e nível"
        subtitle="Nada de planilha genérica. A EasyHealth monta um planejamento de treino do seu jeito — com base no que você quer, pode e tem disponível."
        ctaText="Criar meu treino"
        ctaHref="/sign-up"
        secondaryText="Ver planos"
        secondaryHref="/precos"
      />

      {/* Para quem é */}
      <section className="bg-gray-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Para quem é o treino personalizado da EasyHealth?</h2>
          <div className="mt-8 grid gap-4 sm:grid-cols-2">
            {[
              { icon: "🏋️", label: "Quem vai à academia", text: "Músculação, cardio ou treino funcional, com os equipamentos disponíveis onde você treina." },
              { icon: "🏠", label: "Quem treina em casa", text: "Sem equipamentos ou com poucos acessórios — a IA adapta o plano ao seu contexto." },
              { icon: "🟢", label: "Iniciantes", text: "Volume e intensidade progressivos para quem está começando, sem risco de lesão por excesso." },
              { icon: "🔵", label: "Intermediários e avançados", text: "Periodização e progressão de carga para quem já treina e quer continuar evoluindo." },
            ].map((item) => (
              <div key={item.label} className="rounded-xl border border-gray-100 bg-white p-5">
                <p className="text-2xl">{item.icon}</p>
                <p className="mt-3 font-semibold text-gray-900">{item.label}</p>
                <p className="mt-1 text-sm leading-relaxed text-gray-500">{item.text}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Como funciona */}
      <section className="py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Como funciona</h2>
          <div className="mt-8 space-y-6">
            {[
              { step: "1", title: "Conta seu perfil", text: "Você informa seu objetivo, nível de condicionamento, dias disponíveis por semana e onde vai treinar." },
              { step: "2", title: "A IA monta seu plano", text: "Em segundos, você recebe um planejamento semanal completo com exercícios, séries, repetições e descanso." },
              { step: "3", title: "Você treina e registra", text: "A cada treino, registre o peso usado e como se sentiu. Tudo fica salvo no histórico." },
              { step: "4", title: "O plano evolui com você", text: "Conforme você progride, o plano é ajustado para manter o desafio e os resultados." },
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
          <h2 className="text-2xl font-bold text-gray-900">Benefícios do treino personalizado</h2>
          <ul className="mt-6 space-y-3">
            {[
              "Planejamento alinhado com seus objetivos e disponibilidade real",
              "Progressão de carga estruturada para resultados consistentes",
              "Histórico completo de treinos com pesos e repetições",
              "Flexibilidade para trocar exercícios quando necessário",
              "Nada de repetir o mesmo treino por meses sem evolução",
              "Suporte de IA disponível sempre que precisar ajustar",
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
        title="Seu treino personalizado em minutos"
        subtitle="Comece com 7 dias grátis e veja a diferença de um plano feito para você."
        ctaText="Criar meu treino agora"
        ctaHref="/sign-up"
      />
    </PublicLayout>
  );
}
