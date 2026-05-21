const SUPPORT_EMAIL = "suporte@easyhealth.com.br";

export const FALLBACK_MESSAGE =
  `Não consegui resolver sua dúvida por aqui. Por favor, envie um e-mail para ${SUPPORT_EMAIL} que vamos te ajudar.`;

type KbEntry = {
  keywords: string[];
  answer: string;
};

export const KNOWLEDGE_BASE: KbEntry[] = [
  {
    keywords: ["o que é", "como funciona", "easyhealth", "easy health", "plataforma", "aplicativo", "app"],
    answer:
      "A EasyHealth é uma plataforma de saúde e treino que simplifica sua rotina de exercícios. Você recebe um plano de treino personalizado, registra seus treinos, acompanha sua evolução e pode enviar fotos e exames para análise.",
  },
  {
    keywords: ["treino", "exercício", "exercicios", "plano", "dia de treino", "criar treino", "plano de treino"],
    answer:
      "Você pode criar um plano de treino semanal no menu 'Plano'. Cada dia pode ter exercícios diferentes. Na tela de treino do dia, você executa os exercícios um por um, com cronômetro de descanso e registro de carga.",
  },
  {
    keywords: ["histórico", "historico", "sessão", "sessoes", "sessões", "registrar treino", "log"],
    answer:
      "Todos os treinos realizados ficam salvos no histórico. Você pode acessá-lo pelo menu principal. As sessões mostram duração, data, exercícios realizados e nível de fadiga registrado.",
  },
  {
    keywords: ["trocar exercício", "trocar exercicio", "substituir", "swap", "alternativo"],
    answer:
      "Durante o treino, você pode trocar qualquer exercício tocando no botão 'Trocar'. A IA sugere exercícios similares disponíveis com base no seu equipamento e músculos trabalhados.",
  },
  {
    keywords: ["plano", "assinatura", "assinar", "preço", "preco", "mensalidade", "anual", "pro", "pagar", "pagamento"],
    answer:
      "A EasyHealth oferece planos mensais e anuais (Pro). Com o plano Pro você tem acesso ilimitado a todos os recursos: geração de planos com IA, análise de exames, e muito mais. Veja os preços em easyhealth.com.br/precos.",
  },
  {
    keywords: ["trial", "teste grátis", "gratis", "free", "7 dias", "período de teste"],
    answer:
      "Novos usuários têm 7 dias de trial gratuito com acesso a todos os recursos Pro. Após o período, é necessário assinar um plano para continuar usando.",
  },
  {
    keywords: ["foto", "fotos", "imagem", "progresso corporal", "evolução", "before", "depois"],
    answer:
      "Você pode enviar fotos corporais pelo seu perfil. As imagens são processadas com detecção automática de rosto (borrado por privacidade) e análise de composição corporal pela IA. Ficam armazenadas de forma segura.",
  },
  {
    keywords: ["exame", "exames", "laboratório", "resultado", "pdf", "análise de exames"],
    answer:
      "Envie resultados de exames (foto ou PDF) pelo seu perfil na aba Exames. A IA extrai automaticamente os principais indicadores (glicose, colesterol, etc.) para monitoramento ao longo do tempo.",
  },
  {
    keywords: ["cancelar", "cancelamento", "cancelar assinatura", "trocar plano", "mudar plano"],
    answer:
      "Você pode gerenciar sua assinatura no menu 'Assinatura': trocar entre plano mensal e anual, cancelar (acesso se mantém até o fim do período pago) ou reativar. Acesse pelo app ou envie um e-mail para suporte@easyhealth.com.br.",
  },
  {
    keywords: ["excluir conta", "deletar conta", "apagar conta", "remover conta", "lgpd", "dados pessoais"],
    answer:
      "Você pode excluir sua conta nas configurações do perfil, em 'Conta > Excluir Conta'. Esta ação é irreversível e remove seus dados pessoais. Registros mínimos de pagamento podem ser mantidos para fins legais.",
  },
  {
    keywords: ["limpar dados", "apagar dados", "remover dados", "histórico apagar"],
    answer:
      "Na seção 'Conta' do perfil, você pode usar 'Limpar Meus Dados' para apagar categorias específicas (treinos, fotos, exames, etc.) sem excluir sua conta.",
  },
  {
    keywords: ["suporte", "ajuda", "problema", "bug", "erro", "contato", "fale conosco", "email", "e-mail"],
    answer:
      `Para suporte técnico ou dúvidas, envie um e-mail para ${SUPPORT_EMAIL}. Nossa equipe responde em até 2 dias úteis.`,
  },
  {
    keywords: ["senha", "recuperar senha", "esqueci senha", "login", "entrar", "acesso"],
    answer:
      "Para recuperar sua senha, acesse a tela de login e clique em 'Esqueci minha senha'. Você receberá um link no e-mail cadastrado.",
  },
];

export function findAnswer(query: string): string {
  const normalized = query.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");

  let bestEntry: KbEntry | null = null;
  let bestCount = 0;

  for (const entry of KNOWLEDGE_BASE) {
    const count = entry.keywords.filter((kw) => {
      const normKw = kw.normalize("NFD").replace(/[̀-ͯ]/g, "");
      return normalized.includes(normKw);
    }).length;

    if (count > bestCount) {
      bestCount = count;
      bestEntry = entry;
    }
  }

  return bestCount > 0 && bestEntry ? bestEntry.answer : FALLBACK_MESSAGE;
}
