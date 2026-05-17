import Link from "next/link";

export default function BillingSuccessPage() {
  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center px-4">
      <div className="max-w-sm w-full bg-white rounded-2xl border border-gray-200 p-8 text-center">
        <div className="w-14 h-14 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
          <svg className="w-7 h-7 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
          </svg>
        </div>

        <h1 className="text-xl font-bold text-gray-900 mb-2">Assinatura iniciada!</h1>
        <p className="text-gray-500 text-sm mb-1">
          Seu pagamento foi processado com sucesso.
        </p>
        <p className="text-gray-400 text-xs mb-6">
          O status do plano pode levar alguns segundos para atualizar.
        </p>

        <Link
          href="/billing"
          className="block w-full bg-gray-900 text-white rounded-xl py-3 text-sm font-medium text-center"
        >
          Ver minha assinatura
        </Link>

        <Link
          href="/dashboard"
          className="block mt-3 text-sm text-gray-500 underline underline-offset-2"
        >
          Ir para o dashboard
        </Link>
      </div>
    </div>
  );
}
