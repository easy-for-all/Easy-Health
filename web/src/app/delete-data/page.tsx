import type { Metadata } from "next";
import Link from "next/link";
import { PublicLayout } from "@/shared/components/public-layout";

export const metadata: Metadata = {
  title: "Exclusão de Dados Pessoais - EasyHealth",
  description: "Solicite a exclusão dos seus dados pessoais no EasyHealth conforme a LGPD.",
};

export default function DeleteDataPage() {
  return (
    <PublicLayout>
      <div className="mx-auto max-w-3xl px-6 py-16">
        <h1 className="text-3xl font-bold text-gray-900">Solicitação de Exclusão de Dados Pessoais</h1>

        <div className="mt-10 space-y-10 text-gray-700 leading-relaxed">

          <section>
            <p>
              O <strong>EasyHealth</strong> respeita a privacidade dos usuários e permite que você solicite a exclusão dos seus dados pessoais, conforme a <strong>Lei Geral de Proteção de Dados (LGPD — Lei nº 13.709/2018)</strong>.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">Como solicitar</h2>
            <p className="mt-3">
              Envie um e-mail para{" "}
              <a href="mailto:suporte@easyhealth.art" className="text-primary-600 hover:underline">
                suporte@easyhealth.art
              </a>{" "}
              com as seguintes informações:
            </p>
            <ul className="mt-3 list-disc pl-6 space-y-2">
              <li><strong>Nome completo</strong></li>
              <li><strong>E-mail cadastrado</strong> no EasyHealth</li>
              <li>
                <strong>Tipo de solicitação:</strong>
                <ul className="mt-1 list-disc pl-6 space-y-1">
                  <li>Exclusão de dados pessoais</li>
                  <li>Exclusão da conta</li>
                  <li>Exclusão da conta e dos dados</li>
                </ul>
              </li>
              <li><strong>Observações adicionais</strong>, se desejar</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">Quais dados podem ser excluídos</h2>
            <ul className="mt-3 list-disc pl-6 space-y-2">
              <li>Dados de cadastro</li>
              <li>Dados físicos informados</li>
              <li>Fotos de evolução corporal</li>
              <li>Exames enviados</li>
              <li>Treinos criados</li>
              <li>Histórico de treinos</li>
              <li>Preferências e configurações</li>
              <li>Dados usados para personalização por IA</li>
              <li>Dados de uso associados à conta, quando aplicável</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">O que poderá ser mantido</h2>
            <p className="mt-3">
              Algumas informações poderão ser mantidas quando houver obrigação legal, regulatória, fiscal, contábil, necessidade de segurança, prevenção a fraudes, defesa de direitos ou cumprimento de contrato.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">Prazo</h2>
            <p className="mt-3">
              As solicitações serão analisadas e respondidas em até <strong>15 dias úteis</strong> após o recebimento do e-mail.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">Contato</h2>
            <p className="mt-3">
              <a href="mailto:suporte@easyhealth.art" className="text-primary-600 hover:underline">
                suporte@easyhealth.art
              </a>
            </p>
          </section>

          <section className="border-t border-gray-200 pt-8">
            <p className="text-gray-600">
              Prefere excluir sua conta diretamente pelo aplicativo?
            </p>
            <Link
              href="/delete-account"
              className="mt-4 inline-block rounded-full bg-primary-500 px-6 py-3 text-sm font-semibold text-white hover:bg-primary-600 transition-colors no-underline"
            >
              Excluir minha conta pelo aplicativo
            </Link>
          </section>

        </div>
      </div>
    </PublicLayout>
  );
}
