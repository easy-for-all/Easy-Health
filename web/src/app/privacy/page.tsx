import type { Metadata } from "next";
import { PublicLayout } from "@/shared/components/public-layout";

export const metadata: Metadata = {
  title: "Política de Privacidade — Easy Health",
  description: "Saiba como a Easy Health coleta, usa e protege seus dados pessoais em conformidade com a LGPD.",
};

export default function PrivacyPage() {
  return (
    <PublicLayout>
      <div className="mx-auto max-w-3xl px-6 py-16">
        <h1 className="text-3xl font-bold text-gray-900">Política de Privacidade</h1>
        <p className="mt-2 text-sm text-gray-500">Última atualização: maio de 2026</p>

        <div className="mt-10 space-y-10 text-gray-700 leading-relaxed">

          <section>
            <h2 className="text-xl font-semibold text-gray-900">1. Quem somos</h2>
            <p className="mt-3">
              A <strong>Easy Health</strong> é uma plataforma de saúde e treino que tem como missão ajudar pessoas a se exercitarem com consistência e a acompanharem sua evolução física. Somos responsáveis pelo tratamento dos dados pessoais coletados nesta plataforma, na condição de controladores, conforme a Lei Geral de Proteção de Dados (Lei nº 13.709/2018 — LGPD).
            </p>
            <p className="mt-3">
              Para falar com nosso encarregado de dados (DPO), entre em contato pelo e-mail: <a href="mailto:privacidade@easyhealth.app" className="text-primary-600 hover:underline">privacidade@easyhealth.app</a>.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">2. Dados que coletamos</h2>
            <p className="mt-3">Coletamos os seguintes dados dos nossos usuários:</p>
            <ul className="mt-3 list-disc pl-6 space-y-2">
              <li><strong>Dados de identificação:</strong> nome completo e endereço de e-mail.</li>
              <li><strong>Dados de perfil de saúde:</strong> data de nascimento, gênero, peso, altura, nível de condicionamento físico e objetivo de treino.</li>
              <li><strong>Dados de treino:</strong> histórico de exercícios, cargas utilizadas, sessões completadas e métricas de desempenho.</li>
              <li><strong>Imagens corporais:</strong> fotos enviadas voluntariamente pelo usuário para acompanhamento físico.</li>
              <li><strong>Documentos de saúde:</strong> exames e laudos médicos enviados voluntariamente pelo usuário.</li>
              <li><strong>Logs técnicos:</strong> endereço IP, tipo de dispositivo, sistema operacional, dados de acesso e navegação na plataforma.</li>
            </ul>
            <p className="mt-3">
              Dados sensíveis — como imagens corporais, exames médicos e métricas físicas detalhadas — são coletados somente mediante consentimento expresso e são tratados com proteção reforçada.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">3. Finalidade do tratamento</h2>
            <p className="mt-3">Utilizamos seus dados para:</p>
            <ul className="mt-3 list-disc pl-6 space-y-2">
              <li>Criar e personalizar seu plano de treino com base no seu perfil e objetivos.</li>
              <li>Registrar e exibir seu histórico de atividades e evolução.</li>
              <li>Permitir o acompanhamento de métricas de saúde ao longo do tempo.</li>
              <li>Melhorar continuamente as funcionalidades da plataforma.</li>
              <li>Garantir a segurança da conta e prevenir fraudes.</li>
              <li>Cumprir obrigações legais e regulatórias.</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">4. Base legal</h2>
            <p className="mt-3">O tratamento dos seus dados está fundamentado nas seguintes bases legais da LGPD:</p>
            <ul className="mt-3 list-disc pl-6 space-y-2">
              <li><strong>Consentimento (Art. 7º, I):</strong> para coleta de imagens, exames e dados sensíveis de saúde.</li>
              <li><strong>Execução de contrato (Art. 7º, V):</strong> para fornecimento dos serviços contratados.</li>
              <li><strong>Legítimo interesse (Art. 7º, IX):</strong> para melhorias de produto e segurança da plataforma.</li>
              <li><strong>Cumprimento de obrigação legal (Art. 7º, II):</strong> quando exigido pela legislação.</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">5. Armazenamento e segurança</h2>
            <p className="mt-3">
              Seus dados são armazenados em servidores em nuvem com proteção de alto nível. Arquivos como fotos e exames são mantidos em serviço de armazenamento compatível com Amazon S3, com controle de acesso restrito e criptografia em trânsito (HTTPS/TLS) e em repouso.
            </p>
            <p className="mt-3">
              Adotamos práticas de segurança da informação, incluindo: autenticação segura, controle de acesso por função, monitoramento de atividades suspeitas e backups regulares.
            </p>
            <p className="mt-3">
              Nenhum método de transmissão ou armazenamento é 100% seguro. Em caso de incidente de segurança que afete seus dados, notificaremos você e a Autoridade Nacional de Proteção de Dados (ANPD) conforme exigido pela LGPD.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">6. Compartilhamento de dados</h2>
            <p className="mt-3">
              Não vendemos seus dados pessoais. Podemos compartilhá-los apenas nas seguintes situações:
            </p>
            <ul className="mt-3 list-disc pl-6 space-y-2">
              <li>Com provedores de infraestrutura e serviços em nuvem que atuam como operadores sob nossas instruções.</li>
              <li>Com autoridades competentes, quando exigido por lei ou ordem judicial.</li>
              <li>Em caso de fusão, aquisição ou transferência de ativos, com notificação prévia ao usuário.</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">7. Retenção de dados</h2>
            <p className="mt-3">
              Mantemos seus dados enquanto sua conta estiver ativa ou conforme necessário para a prestação dos serviços. Após o encerramento da conta, os dados são excluídos ou anonimizados em até 90 dias, exceto quando houver obrigação legal de retenção por prazo maior.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">8. Seus direitos (LGPD)</h2>
            <p className="mt-3">Você tem os seguintes direitos sobre seus dados:</p>
            <ul className="mt-3 list-disc pl-6 space-y-2">
              <li><strong>Acesso:</strong> solicitar confirmação e acesso aos dados que temos sobre você.</li>
              <li><strong>Correção:</strong> corrigir dados incompletos, inexatos ou desatualizados.</li>
              <li><strong>Exclusão:</strong> solicitar a exclusão de dados tratados com base no consentimento.</li>
              <li><strong>Portabilidade:</strong> receber seus dados em formato estruturado e legível.</li>
              <li><strong>Revogação do consentimento:</strong> retirar seu consentimento a qualquer momento.</li>
              <li><strong>Oposição:</strong> opor-se ao tratamento em caso de descumprimento da LGPD.</li>
              <li><strong>Informação:</strong> ser informado sobre com quem seus dados são compartilhados.</li>
            </ul>
            <p className="mt-3">
              Para exercer qualquer desses direitos, entre em contato com <a href="mailto:privacidade@easyhealth.app" className="text-primary-600 hover:underline">privacidade@easyhealth.app</a>. Responderemos em até 15 dias úteis.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">9. Dados de menores</h2>
            <p className="mt-3">
              A plataforma Easy Health não é destinada a menores de 18 anos. Não coletamos intencionalmente dados de crianças ou adolescentes. Se identificarmos tal coleta, excluiremos os dados imediatamente.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">10. Cookies e análise</h2>
            <p className="mt-3">
              Podemos utilizar cookies e tecnologias similares para melhorar a experiência de uso, manter sessões autenticadas e analisar padrões de uso de forma agregada e anonimizada. Você pode configurar seu navegador para bloquear cookies, mas isso pode afetar algumas funcionalidades.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">11. Alterações nesta política</h2>
            <p className="mt-3">
              Podemos atualizar esta Política de Privacidade periodicamente. Quando isso ocorrer, notificaremos você por e-mail ou por aviso na plataforma, e atualizaremos a data de revisão no topo desta página. O uso continuado da plataforma após a notificação constitui aceite das mudanças.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">12. Contato</h2>
            <p className="mt-3">
              Para dúvidas, solicitações ou reclamações relacionadas a esta política ou ao tratamento dos seus dados, entre em contato:
            </p>
            <ul className="mt-3 list-none space-y-1">
              <li><strong>E-mail:</strong> <a href="mailto:privacidade@easyhealth.app" className="text-primary-600 hover:underline">privacidade@easyhealth.app</a></li>
              <li><strong>Encarregado de Dados (DPO):</strong> Easy Health — Encarregado de Proteção de Dados</li>
            </ul>
            <p className="mt-3">
              Você também pode registrar reclamações perante a Autoridade Nacional de Proteção de Dados (ANPD): <a href="https://www.gov.br/anpd" target="_blank" rel="noopener noreferrer" className="text-primary-600 hover:underline">www.gov.br/anpd</a>.
            </p>
          </section>

        </div>
      </div>
    </PublicLayout>
  );
}
