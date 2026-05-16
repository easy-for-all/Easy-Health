import type { Metadata } from "next";
import { PublicLayout } from "@/shared/components/public-layout";

export const metadata: Metadata = {
  title: "Termos de Uso — Easy Health",
  description: "Leia os Termos de Uso da plataforma Easy Health antes de criar sua conta.",
};

export default function TermsPage() {
  return (
    <PublicLayout>
      <div className="mx-auto max-w-3xl px-6 py-16">
        <h1 className="text-3xl font-bold text-gray-900">Termos de Uso</h1>
        <p className="mt-2 text-sm text-gray-500">Última atualização: maio de 2026</p>

        <div className="mt-10 space-y-10 text-gray-700 leading-relaxed">

          <section>
            <h2 className="text-xl font-semibold text-gray-900">1. Aceitação dos termos</h2>
            <p className="mt-3">
              Ao criar uma conta ou utilizar a plataforma <strong>Easy Health</strong>, você concorda com estes Termos de Uso. Se não concordar com alguma cláusula, não utilize a plataforma.
            </p>
            <p className="mt-3">
              Estes termos constituem um acordo legal entre você (usuário) e a Easy Health. O uso continuado da plataforma após alterações nos termos implica aceite das novas condições.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">2. Sobre a plataforma</h2>
            <p className="mt-3">
              A Easy Health é uma plataforma digital de apoio ao treino físico e acompanhamento de hábitos de saúde. A plataforma oferece:
            </p>
            <ul className="mt-3 list-disc pl-6 space-y-2">
              <li>Criação personalizada de planos de treino;</li>
              <li>Registro de sessões de exercício e histórico de atividades;</li>
              <li>Acompanhamento de métricas físicas;</li>
              <li>Ferramentas para personalização e troca de exercícios.</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">3. Não substitui orientação médica ou profissional</h2>
            <p className="mt-3">
              <strong>A Easy Health não é um serviço médico.</strong> O conteúdo da plataforma — incluindo planos de treino, sugestões de exercícios e informações de saúde — tem caráter informativo e de apoio ao usuário, e não substitui a orientação de médicos, educadores físicos, nutricionistas ou outros profissionais de saúde.
            </p>
            <p className="mt-3">
              Antes de iniciar qualquer programa de exercícios, especialmente se você tiver condições de saúde preexistentes, consulte um profissional qualificado. A Easy Health não se responsabiliza por lesões, danos à saúde ou quaisquer consequências decorrentes do uso das informações da plataforma.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">4. Conta de usuário</h2>
            <p className="mt-3">
              Para utilizar a plataforma, você deve criar uma conta com informações verídicas. Você é responsável por:
            </p>
            <ul className="mt-3 list-disc pl-6 space-y-2">
              <li>Manter a confidencialidade da sua senha;</li>
              <li>Todas as atividades realizadas com sua conta;</li>
              <li>Notificar imediatamente a Easy Health em caso de acesso não autorizado.</li>
            </ul>
            <p className="mt-3">
              É proibido criar contas com informações falsas, usar a conta de outra pessoa ou criar múltiplas contas para burlar restrições da plataforma.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">5. Uso adequado</h2>
            <p className="mt-3">Você concorda em utilizar a plataforma de forma ética e lícita. É expressamente proibido:</p>
            <ul className="mt-3 list-disc pl-6 space-y-2">
              <li>Usar a plataforma para fins ilegais ou fraudulentos;</li>
              <li>Tentar acessar sistemas ou dados de outros usuários;</li>
              <li>Realizar engenharia reversa, descompilar ou modificar a plataforma;</li>
              <li>Transmitir vírus, malware ou qualquer código malicioso;</li>
              <li>Sobrecarregar deliberadamente a infraestrutura da plataforma;</li>
              <li>Enviar conteúdo ilegal, ofensivo, discriminatório ou que viole direitos de terceiros.</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">6. Conteúdo do usuário</h2>
            <p className="mt-3">
              Ao enviar fotos, exames ou qualquer outro conteúdo para a plataforma, você declara que possui os direitos necessários sobre esse conteúdo e que ele não viola direitos de terceiros nem a legislação vigente.
            </p>
            <p className="mt-3">
              A Easy Health não reivindica propriedade sobre o conteúdo que você envia. Usamos esse conteúdo apenas para prestar os serviços descritos nestes termos e na nossa Política de Privacidade.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">7. Propriedade intelectual</h2>
            <p className="mt-3">
              Todo o conteúdo da plataforma — incluindo textos, imagens, logotipos, código-fonte, design e funcionalidades — é de propriedade da Easy Health ou de seus licenciadores, e está protegido pela legislação de propriedade intelectual.
            </p>
            <p className="mt-3">
              Você recebe uma licença limitada, não exclusiva e intransferível para usar a plataforma para fins pessoais. É proibida qualquer reprodução, distribuição ou uso comercial sem autorização prévia e por escrito.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">8. Suspensão e encerramento de conta</h2>
            <p className="mt-3">
              A Easy Health reserva-se o direito de suspender ou encerrar sua conta, sem aviso prévio, nos seguintes casos:
            </p>
            <ul className="mt-3 list-disc pl-6 space-y-2">
              <li>Violação destes Termos de Uso;</li>
              <li>Uso fraudulento ou abusivo da plataforma;</li>
              <li>Solicitação das autoridades competentes;</li>
              <li>Inatividade prolongada.</li>
            </ul>
            <p className="mt-3">
              Você pode encerrar sua conta a qualquer momento acessando as configurações do perfil ou entrando em contato com o suporte.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">9. Limitação de responsabilidade</h2>
            <p className="mt-3">
              Na máxima extensão permitida pela legislação, a Easy Health não se responsabiliza por:
            </p>
            <ul className="mt-3 list-disc pl-6 space-y-2">
              <li>Danos diretos, indiretos, incidentais ou consequentes decorrentes do uso da plataforma;</li>
              <li>Interrupções temporárias no serviço por manutenção ou problemas técnicos;</li>
              <li>Perda de dados por circunstâncias fora do nosso controle;</li>
              <li>Resultados de saúde ou condicionamento físico obtidos ou não obtidos pelo usuário.</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">10. Alterações nos termos</h2>
            <p className="mt-3">
              Podemos atualizar estes Termos de Uso a qualquer momento. Quando isso ocorrer, notificaremos você por e-mail ou por aviso na plataforma. O uso continuado após a notificação constitui aceite das novas condições.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">11. Lei aplicável e foro</h2>
            <p className="mt-3">
              Estes Termos de Uso são regidos pelas leis da República Federativa do Brasil. Para a resolução de disputas, fica eleito o foro da comarca onde a Easy Health está sediada, com renúncia expressa a qualquer outro, por mais privilegiado que seja.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900">12. Contato</h2>
            <p className="mt-3">
              Dúvidas sobre estes Termos de Uso? Entre em contato pelo e-mail: <a href="mailto:suporte@easyhealth.app" className="text-primary-600 hover:underline">suporte@easyhealth.app</a>.
            </p>
          </section>

        </div>
      </div>
    </PublicLayout>
  );
}
