import Link from "next/link";

export default function BillingCancelPage() {
  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center px-4">
      <div className="max-w-sm w-full bg-white rounded-2xl border border-gray-200 p-8 text-center">
        <div className="w-14 h-14 bg-gray-100 rounded-full flex items-center justify-center mx-auto mb-4">
          <svg className="w-7 h-7 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </div>

        <h1 className="text-xl font-bold text-gray-900 mb-2">Assinatura não concluída</h1>
        <p className="text-gray-500 text-sm mb-6">
          Você pode voltar e escolher um plano quando quiser.
        </p>

        <Link
          href="/pricing"
          className="block w-full bg-gray-900 text-white rounded-xl py-3 text-sm font-medium text-center hover:bg-gray-700 transition"
        >
          Ver planos
        </Link>
      </div>
    </div>
  );
}
