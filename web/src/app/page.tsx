import Link from "next/link";
import { Footer } from "@/shared/components/footer";

export default function LandingPage() {
  return (
    <div className="flex min-h-screen flex-col bg-white">
      {/* Header */}
      <header className="sticky top-0 z-10 border-b border-gray-100 bg-white/90 backdrop-blur">
        <div className="mx-auto flex max-w-5xl items-center justify-between px-6 py-4">
          <div className="flex items-center gap-2">
            <img src="/logo.png" alt="Easy Health" className="h-10 w-auto" />
            <span className="text-xl font-bold text-primary-600">Easy Health</span>
          </div>
          <nav className="flex items-center gap-3">
            <Link href="/login" className="text-sm font-medium text-gray-600 hover:text-gray-900">
              Entrar
            </Link>
            <Link href="/sign-up" className="rounded-lg bg-primary-500 px-4 py-2 text-sm font-semibold text-white hover:bg-primary-600">
              Criar conta
            </Link>
          </nav>
        </div>
      </header>

      <main className="flex-1">
        {/* Hero */}
        <section className="mx-auto max-w-5xl px-6 py-20 text-center">
          <h1 className="text-4xl font-bold leading-tight text-gray-900 sm:text-5xl">
            Treine com consistência.<br />
            <span className="text-primary-500">Evolua de verdade.</span>
          </h1>
          <p className="mx-auto mt-6 max-w-xl text-lg text-gray-500">
            Easy Health simplifica seu plano de treino, acompanha sua evolução e te mantém no caminho — sem complicação.
          </p>
          <div className="mt-8 flex flex-col items-center gap-3 sm:flex-row sm:justify-center">
            <Link href="/sign-up" className="w-full rounded-xl bg-primary-500 px-8 py-4 text-base font-semibold text-white hover:bg-primary-600 sm:w-auto">
              Começar gratuitamente
            </Link>
            <Link href="/login" className="w-full rounded-xl border border-gray-200 px-8 py-4 text-base font-semibold text-gray-700 hover:bg-gray-50 sm:w-auto">
              Já tenho conta
            </Link>
          </div>
        </section>

        {/* Quem somos */}
        <section className="bg-primary-50 py-20">
          <div className="mx-auto max-w-5xl px-6">
            <div className="mx-auto max-w-2xl text-center">
              <h2 className="text-3xl font-bold text-gray-900">Quem somos</h2>
              <p className="mt-4 text-gray-600 leading-relaxed">
                Somos um time apaixonado por saúde e tecnologia. Acreditamos que a consistência nos pequenos hábitos é o que transforma a vida das pessoas — e criamos a Easy Health para tornar isso possível no dia a dia de qualquer pessoa.
              </p>
              <p className="mt-4 text-gray-600 leading-relaxed">
                Nossa plataforma foi pensada para atletas amadores, iniciantes e qualquer pessoa que queira se mover mais, dormir melhor e cuidar do próprio corpo com inteligência.
              </p>
            </div>
          </div>
        </section>

        {/* Propósito */}
        <section className="py-20">
          <div className="mx-auto max-w-5xl px-6">
            <div className="mx-auto max-w-2xl text-center">
              <h2 className="text-3xl font-bold text-gray-900">Nosso propósito</h2>
              <p className="mt-4 text-gray-600 leading-relaxed">
                Saúde não precisa ser complicada. Queremos eliminar a barreira entre a intenção e a ação — oferecendo ferramentas simples, inteligentes e adaptáveis ao ritmo de cada pessoa.
              </p>
              <div className="mt-10 grid gap-6 sm:grid-cols-3">
                <div className="rounded-2xl bg-primary-50 p-6 text-center">
                  <p className="text-3xl">🎯</p>
                  <p className="mt-3 font-semibold text-gray-900">Foco no que importa</p>
                  <p className="mt-2 text-sm text-gray-500">Sem distrações. Só o treino que você precisa fazer hoje.</p>
                </div>
                <div className="rounded-2xl bg-primary-50 p-6 text-center">
                  <p className="text-3xl">📈</p>
                  <p className="mt-3 font-semibold text-gray-900">Evolução visível</p>
                  <p className="mt-2 text-sm text-gray-500">Registre sua carga e veja sua evolução semana a semana.</p>
                </div>
                <div className="rounded-2xl bg-primary-50 p-6 text-center">
                  <p className="text-3xl">🔄</p>
                  <p className="mt-3 font-semibold text-gray-900">Adaptável ao seu ritmo</p>
                  <p className="mt-2 text-sm text-gray-500">Troque exercícios, ajuste cargas e siga no seu ritmo.</p>
                </div>
              </div>
            </div>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}
