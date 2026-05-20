import type { Metadata } from "next";
import { PublicLayout } from "@/shared/components/public-layout";
import { LandingHero } from "@/shared/components/landing-hero";
import { CTASection } from "@/shared/components/cta-section";

export const metadata: Metadata = {
  title: "Treino em Casa | EasyHealth",
  description: "Crie treinos em casa adaptados à sua rotina, nível e equipamentos disponíveis. IA que monta o plano certo para o seu contexto.",
};

export default function TreinoEmCasa() {
  return (
    <PublicLayout>
      <LandingHero
        title="Treino em casa com apoio de IA"
        subtitle="Sem academia, sem desculpa. A EasyHealth monta treinos adaptados ao seu espaço, equipamentos e rotina — direto no seu celular."
        ctaText="Montar meu treino"
        ctaHref="/sign-up"
        secondaryText="Ver planos"
        secondaryHref="/precos"
      />

      {/* Cenários */}
      <section className="bg-gray-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Treino em casa funciona para vários contextos</h2>
          <div className="mt-8 grid gap-4 sm:grid-cols-2">
            {[
              { icon: "🏠", label: "Sem nenhum equipamento", text: "Treinos com peso corporal — polichinelo, agachamento, flexão, abdominais e muito mais." },
              { icon: "🏋️", label: "Com halteres ou elásticos", text: "A IA inclui os equipamentos que você tem e monta um treino completo com eles." },
              { icon: "⏰", label: "Pouco tempo disponível", text: "Treinos de 20 a 45 minutos, adaptados ao tempo que você tem no dia." },
              { icon: "🌍", label: "Viagem ou fora da academia", text: "Treinos adaptáveis para hotel, parque ou qualquer espaço disponível." },
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
          <h2 className="text-2xl font-bold text-gray-900">Como a EasyHealth adapta o treino ao seu espaço</h2>
          <div className="mt-8 space-y-6">
            {[
              { step: "1", title: "Informe onde você treina", text: "Durante o cadastro, você indica se treina em casa, academia, ao ar livre ou em uma combinação." },
              { step: "2", title: "Diga o que você tem disponível", text: "Nenhum equipamento, halteres, elástico, barra — a IA usa o que você tem." },
              { step: "3", title: "Receba seu plano adaptado", text: "A IA monta um plano completo usando apenas os recursos do seu contexto, sem deixar grupos musculares de fora." },
              { step: "4", title: "Troque exercícios quando precisar", text: "Não tem o aparelho certo? Tire uma foto e a IA sugere um substituto equivalente." },
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
          <h2 className="text-2xl font-bold text-gray-900">Vantagens do treino em casa com a EasyHealth</h2>
          <ul className="mt-6 space-y-3">
            {[
              "Treino montado para o seu espaço e equipamentos disponíveis",
              "Sem deslocamento e sem horários fixos",
              "Exercícios com instruções claras de execução",
              "Progressão de carga e dificuldade ao longo do tempo",
              "Registro e histórico de todas as sessões",
              "Funciona offline no mobile",
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
        title="Comece a treinar em casa hoje"
        subtitle="7 dias grátis. Sem academia, sem complicação."
        ctaText="Criar meu treino em casa"
        ctaHref="/sign-up"
      />
    </PublicLayout>
  );
}
