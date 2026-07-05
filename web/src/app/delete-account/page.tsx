import type { Metadata } from "next";
import Link from "next/link";
import { PublicLayout } from "@/shared/components/public-layout";

export const metadata: Metadata = {
  title: "Exclusão de Conta - EasyHealth",
  description: "Saiba como excluir permanentemente sua conta EasyHealth e quais dados são removidos.",
};

export default function DeleteAccountPage() {
  return (
    <PublicLayout>
      <div className="mx-auto max-w-3xl px-6 py-16">
        <h1 className="text-3xl font-bold text-gray-900">Exclusão de Conta</h1>

        <div className="mt-10 space-y-10 text-gray-700 leading-relaxed">

          <section>
            <p>
              O <strong>EasyHealth</strong> permite que você exclua permanentemente sua conta a qualquer momento. A exclusão é irreversível e remove todos os dados associados à sua conta.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">Como excluir sua conta pelo aplicativo</h2>
            <ol className="mt-3 list-decimal pl-6 space-y-2">
              <li>Acesse o aplicativo EasyHealth.</li>
              <li>Faça login na sua conta.</li>
              <li>Vá até <strong>Perfil</strong>.</li>
              <li>Toque em <strong>Excluir Conta</strong>.</li>
              <li>Confirme a exclusão definitiva.</li>
            </ol>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">O que será excluído</h2>
            <p className="mt-3">Ao excluir sua conta, os seguintes dados são removidos permanentemente:</p>
            <ul className="mt-3 list-disc pl-6 space-y-2">
              <li>Perfil do usuário</li>
              <li>Dados físicos informados</li>
              <li>Treinos criados</li>
              <li>Histórico de treinos</li>
              <li>Fotos de evolução corporal</li>
              <li>Exames enviados</li>
              <li>Preferências e configurações</li>
              <li>Dados usados para personalização por IA</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">O que poderá ser mantido</h2>
            <p className="mt-3">
              Alguns registros relacionados a pagamentos, assinaturas, transações, suporte, segurança, prevenção a fraudes ou obrigações legais poderão ser mantidos pelo período exigido pela legislação aplicável. Após a exclusão, o e-mail (e a conta Google associada, se houver) usado na conta não poderá ser utilizado para criar uma nova conta no EasyHealth.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">Prazo</h2>
            <p className="mt-3">
              A exclusão da conta é iniciada imediatamente após a confirmação no aplicativo. Em alguns casos, backups e registros técnicos podem levar até <strong>15 dias úteis</strong> para serem removidos ou anonimizados.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">Contato</h2>
            <p className="mt-3">
              Em caso de dúvidas, entre em contato pelo e-mail:{" "}
              <a href="mailto:suporte@easyhealth.art" className="text-primary-600 hover:underline">
                suporte@easyhealth.art
              </a>
            </p>
          </section>

          <section className="border-t border-gray-200 pt-8">
            <p className="text-gray-600">
              Deseja apenas solicitar a exclusão de dados pessoais sem encerrar sua conta?
            </p>
            <Link
              href="/delete-data"
              className="mt-4 inline-block rounded-full bg-primary-500 px-6 py-3 text-sm font-semibold text-white hover:bg-primary-600 transition-colors no-underline"
            >
              Solicitar exclusão de dados pessoais
            </Link>
          </section>

        </div>
      </div>
    </PublicLayout>
  );
}
