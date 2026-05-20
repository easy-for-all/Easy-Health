import type { Metadata } from "next";
import { PublicLayout } from "@/shared/components/public-layout";
import { LandingHero } from "@/shared/components/landing-hero";
import { CTASection } from "@/shared/components/cta-section";

export const metadata: Metadata = {
  title: "Análise de Exames para Treino | EasyHealth",
  description: "Use seus exames de saúde para personalizar ainda mais sua rotina fitness. A EasyHealth considera seus dados para apoiar um treino mais seguro e eficaz.",
};

export default function AnaliseDeExames() {
  return (
    <PublicLayout>
      <LandingHero
        title="Análise de exames para apoiar sua jornada fitness"
        subtitle="Conecte seus dados de saúde ao seu planejamento de treino. A EasyHealth considera suas informações para sugerir uma rotina mais adequada ao seu momento."
        ctaText="Começar agora"
        ctaHref="/sign-up"
        secondaryText="Ver planos"
        secondaryHref="/precos"
      />

      {/* Disclaimer médico */}
      <section className="bg-gray-50 py-12">
        <div className="mx-auto max-w-3xl px-6">
          <p className="rounded-xl border border-amber-200 bg-amber-50 px-5 py-4 text-sm text-amber-800">
            ⚠️ A EasyHealth não substitui avaliação médica, diagnóstico ou acompanhamento profissional de saúde. Use este recurso como apoio à sua rotina fitness, sempre com orientação de um profissional qualificado.
          </p>
        </div>
      </section>

      {/* Como funciona */}
      <section className="py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Como seus dados de saúde ajudam no treino</h2>
          <p className="mt-4 leading-relaxed text-gray-600">
            Informações como glicemia, pressão arterial, histórico de lesões e condições de saúde influenciam diretamente o tipo de treino mais adequado para cada pessoa.
          </p>
          <p className="mt-4 leading-relaxed text-gray-600">
            Com a EasyHealth, você pode inserir essas informações durante o cadastro e a IA leva em consideração ao montar seu planejamento — sugerindo intensidades, exercícios e progressões compatíveis com seu estado de saúde.
          </p>
          <div className="mt-8 space-y-6">
            {[
              { icon: "🩺", title: "Histórico de saúde", text: "Informe condições como hipertensão, diabetes ou histórico de lesões para que o treino seja montado com segurança." },
              { icon: "📊", title: "Dados de exames recentes", text: "Adicione resultados relevantes como glicose, colesterol ou pressão arterial para contextualizar seu momento de saúde." },
              { icon: "🤖", title: "IA considera suas informações", text: "Com base nos seus dados, a IA sugere tipo de esforço, intensidade e exercícios mais adequados ao seu contexto." },
              { icon: "📋", title: "Histórico centralizado", text: "Mantenha suas informações de saúde organizadas dentro do app, acessíveis sempre que precisar." },
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

      {/* O que você pode inserir */}
      <section className="bg-gray-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Informações que você pode compartilhar</h2>
          <div className="mt-6 grid gap-4 sm:grid-cols-2">
            {[
              { label: "Pressão arterial", desc: "Hipertensão ou hipotensão influenciam na intensidade recomendada." },
              { label: "Glicemia e diabetes", desc: "O controle glicêmico é relevante para frequência e tipo de treino." },
              { label: "Histórico de lesões", desc: "Lesões anteriores limitam certos movimentos e exercícios." },
              { label: "Condições cardiovasculares", desc: "Determina limites de esforço e exercícios contraindicados." },
              { label: "Peso e IMC", desc: "Ajuda a calibrar volume, intensidade e tipo de exercício." },
              { label: "Outras condições", desc: "Qualquer informação relevante que o profissional de saúde tenha recomendado levar em conta." },
            ].map((item) => (
              <div key={item.label} className="rounded-xl border border-gray-100 bg-white p-5">
                <p className="font-semibold text-gray-900">{item.label}</p>
                <p className="mt-1 text-sm leading-relaxed text-gray-500">{item.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Benefícios */}
      <section className="bg-primary-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Treino mais seguro e personalizado</h2>
          <ul className="mt-6 space-y-3">
            {[
              "Treino montado considerando seu estado de saúde atual",
              "Intensidade adequada ao seu condicionamento e condições",
              "Histórico de saúde centralizado no app",
              "Alertas e sugestões baseadas no seu perfil",
              "Mais segurança para quem está voltando após pausa ou procedimento",
              "Integração natural com o plano de treino semanal",
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
        title="Treino personalizado com seus dados de saúde"
        subtitle="7 dias grátis. Sem compromisso, sem cartão para começar."
        ctaText="Criar minha conta"
        ctaHref="/sign-up"
      />
    </PublicLayout>
  );
}
