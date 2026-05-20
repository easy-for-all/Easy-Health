import type { Metadata } from "next";
import Link from "next/link";
import { PublicLayout } from "@/shared/components/public-layout";
import { CTASection } from "@/shared/components/cta-section";

export const metadata: Metadata = {
  title: "Sobre a EasyHealth | EasyHealth",
  description: "Conheça a EasyHealth — tecnologia e inteligência artificial para tornar sua rotina fitness mais simples, inteligente e adaptável.",
};

export default function Sobre() {
  return (
    <PublicLayout>
      {/* Hero */}
      <section className="mx-auto max-w-3xl px-6 py-16">
        <h1 className="text-3xl font-bold text-gray-900 sm:text-4xl">
          Sobre a EasyHealth
        </h1>
        <p className="mt-6 text-lg leading-relaxed text-gray-600">
          A EasyHealth nasceu de uma percepção simples: a maioria das pessoas que quer se exercitar não precisa de mais informação — precisa de clareza sobre o que fazer hoje.
        </p>
        <p className="mt-4 leading-relaxed text-gray-600">
          Planilhas genéricas, vídeos desconexos e apps complicados criam mais fricção do que resultado. Criamos a EasyHealth para resolver isso: um planejamento de treino inteligente, personalizado e fácil de seguir — no celular, pronto para o dia.
        </p>
      </section>

      {/* Missão */}
      <section className="bg-gray-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Nossa missão</h2>
          <p className="mt-4 leading-relaxed text-gray-600">
            Tornar a rotina fitness mais simples, inteligente e adaptável — para que qualquer pessoa, independente de experiência ou equipamento disponível, consiga treinar com consistência e evoluir de verdade.
          </p>
          <div className="mt-8 grid gap-6 sm:grid-cols-3">
            {[
              { icon: "🎯", title: "Clareza", text: "O treino do dia sempre pronto. Sem dúvidas sobre o que fazer." },
              { icon: "📈", title: "Evolução", text: "Registro e acompanhamento de progresso para manter a motivação." },
              { icon: "🔄", title: "Adaptação", text: "Treino que muda com você — objetivo, disponibilidade e local." },
            ].map((item) => (
              <div key={item.title} className="rounded-2xl bg-white p-6 text-center shadow-sm">
                <p className="text-3xl">{item.icon}</p>
                <p className="mt-3 font-semibold text-gray-900">{item.title}</p>
                <p className="mt-2 text-sm text-gray-500">{item.text}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* O que fazemos */}
      <section className="py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">O que a EasyHealth faz</h2>
          <ul className="mt-6 space-y-3">
            {[
              "Cria planos de treino personalizados com inteligência artificial",
              "Adapta o treino ao seu espaço, equipamentos e disponibilidade de tempo",
              "Registra e acompanha sua evolução semana a semana",
              "Sugere substituições de exercícios quando necessário",
              "Considera informações de saúde para montar um treino mais seguro",
              "Funciona no celular, onde e quando você precisar",
            ].map((item) => (
              <li key={item} className="flex items-start gap-3 text-gray-700">
                <span className="mt-0.5 text-primary-500">✓</span>
                {item}
              </li>
            ))}
          </ul>
        </div>
      </section>

      {/* Contato */}
      <section className="bg-primary-50 py-16">
        <div className="mx-auto max-w-3xl px-6">
          <h2 className="text-2xl font-bold text-gray-900">Fale com a gente</h2>
          <p className="mt-4 leading-relaxed text-gray-600">
            Tem dúvidas, sugestões ou quer dar feedback sobre a EasyHealth? Estamos sempre disponíveis.
          </p>
          <p className="mt-4 text-gray-600">
            E-mail:{" "}
            <a href="mailto:contato@easyhealth.art" className="font-medium text-primary-600 hover:underline">
              contato@easyhealth.art
            </a>
          </p>
          <div className="mt-6 flex flex-wrap gap-4">
            <Link href="/precos" className="text-sm font-medium text-primary-600 hover:underline">
              Ver planos →
            </Link>
            <Link href="/privacy" className="text-sm font-medium text-gray-500 hover:underline">
              Política de privacidade
            </Link>
            <Link href="/terms" className="text-sm font-medium text-gray-500 hover:underline">
              Termos de uso
            </Link>
          </div>
        </div>
      </section>

      <CTASection
        title="Comece sua jornada hoje"
        subtitle="7 dias grátis para experimentar tudo. Sem cartão de crédito."
        ctaText="Criar minha conta"
        ctaHref="/sign-up"
      />
    </PublicLayout>
  );
}
