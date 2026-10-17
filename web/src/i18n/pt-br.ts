import type { Dictionary } from "./en";

export const ptBr: Dictionary = {
  meta: {
    title: "Splitty: divida despesas, acerte as contas",
    description:
      "O Splitty mantém uma conta compartilhada para viagens, repúblicas e jantares: quem pagou, quem deve e o menor número de pagamentos para acertar tudo. Em breve no iPhone.",
  },
  nav: {
    privacy: "Privacidade",
    terms: "Termos",
    support: "Suporte",
    language: "Idioma",
    home: "Início do Splitty",
  },
  hero: {
    title: "Divida despesas, acerte as contas.",
    lede: "Uma conta compartilhada para a viagem, a república ou o jantar de sexta. Registre quem pagou, divida de forma justa e veja o menor número de pagamentos para deixar todo mundo em dia.",
    store: "Em breve na App Store",
    platform: "Para iPhone e iPad. Grátis.",
  },
  story: {
    steps: [
      {
        title: "Registre antes de esquecer",
        body: "Digite o valor e escolha quem pagou. A despesa aparece na linha do tempo do grupo para todo mundo, com quanto cada um deve.",
      },
      {
        title: "Divida do jeito que aconteceu",
        body: "Igualmente, por valores ou por porcentagens. O Splitty confere se as partes somam o total antes de salvar.",
      },
      {
        title: "Menos pagamentos",
        body: "O Splitty compensa quem deve a quem no grupo inteiro, e um emaranhado de pequenas dívidas vira poucos pagamentos diretos.",
      },
      {
        title: "Acerte as contas",
        body: "Registre um pagamento e o saldo vai a zero. O Splitty nunca mexe no seu dinheiro. Ele só mantém as contas certas.",
      },
    ],
  },
  phone: {
    group: "Viagem a Lisboa",
    today: "Hoje",
    yesterday: "Ontem",
    oweOverall: "Você deve {amount} no total",
    paid: "{name} pagou {amount}",
    youBorrowed: "você pegou emprestado",
    next: "Próximo",
    cancel: "Cancelar",
    save: "Salvar",
    done: "Concluído",
    splitTitle: "Divisão",
    paidBy: "Pago por",
    selectAll: "Todos",
    selectNone: "Nenhum",
    allAssigned: "Tudo atribuído",
    each: "{amount} cada",
    people: "{count} pessoas",
    assignedOf: "{assigned} de {total}",
    settleUp: "Quitar contas",
    charts: "Gráficos",
    export: "Exportar",
    expensesTab: "Despesas",
    plansTab: "Planos",
    diningOut: "Restaurantes",
    groceries: "Supermercado",
    whatFor: "Para que foi?",
    games: "Jogos",
    equally: "Igualmente",
    amounts: "Valores",
    percentages: "Porcentagens",
    splitBetween: "Dividir entre",
    summary: {
      equally: "Pago por Caio e dividido igualmente",
      amounts: "Pago por Caio e dividido por valores",
      percentages: "Pago por Caio e dividido por porcentagens",
    },
    you: "Você",
    balances: "Saldos",
    payments: { before: "6 pagamentos", after: "3 pagamentos" },
    youOwePeer: "Você deve {amount} a {name}",
    peerOwesPeer: "{from} deve {amount} a {to}",
    pay: "Pagar {amount}",
    settled: "Você quitou todas as suas dívidas",
    expenses: {
      apartment: "Apartamento",
      taxi: "Táxi do aeroporto",
      dinner: "Jantar na tasca",
    },
  },
  more: {
    title: "E mais",
    items: [
      {
        title: "Despesas recorrentes",
        body: "Aluguel, assinaturas e parcelas entram sozinhos na data certa, e dá para ver em que parcela cada um está.",
      },
      {
        title: "Para onde foi o dinheiro",
        body: "Gastos por categoria e as maiores despesas, do mês atual até todo o período, do grupo ou só da sua parte.",
      },
      {
        title: "Entre com um código",
        body: "Compartilhe um código de seis caracteres. Sem links para repassar, sem enviar seus contatos.",
      },
      {
        title: "Exporte para CSV",
        body: "Leve as despesas de um grupo para uma planilha quando quiser.",
      },
      {
        title: "Quatro idiomas",
        body: "English, Português, Español e Français, com troca dentro do app.",
      },
      {
        title: "Sua conta, sua decisão",
        body: "Desative por um tempo ou apague de vez, direto nos Ajustes.",
      },
    ],
  },
  closing: {
    title: "Todo mundo em dia.",
    body: "O Splitty chega à App Store em breve.",
  },
  footer: {
    madeBy: "Feito no Brasil.",
  },
  legal: {
    updated: "Última atualização: {date}",
    back: "Voltar ao Splitty",
    privacyTitle: "Política de Privacidade",
    termsTitle: "Termos de Uso",
  },
  support: {
    title: "Suporte",
    lede: "Escreva para a gente e uma pessoa responde, normalmente em até dois dias úteis.",
    email: "Enviar e-mail ao suporte",
    faqTitle: "Perguntas frequentes",
    faq: [
      {
        q: "Como adiciono alguém a um grupo?",
        a: "Abra o grupo, depois Configurações do grupo e Convidar pessoas. Envie o código de seis caracteres. A pessoa digita o código em Entrar com código.",
      },
      {
        q: "O Splitty envia ou recebe dinheiro?",
        a: "Não. O Splitty registra o que cada um pagou e deve. Quando você pagar alguém fora do app, registre o pagamento em Quitar contas para o saldo ser atualizado.",
      },
      {
        q: "Quem pode editar uma despesa?",
        a: "Qualquer membro do grupo pode adicionar, editar ou apagar qualquer despesa do grupo. Os grupos funcionam com base na confiança entre as pessoas que fazem parte deles.",
      },
      {
        q: "Como pego uma cópia dos meus dados?",
        a: "Abra um grupo e toque em Exportar para salvar as despesas em um arquivo CSV. Para receber uma cópia de tudo o que temos sobre você, mande um e-mail.",
      },
      {
        q: "Como apago minha conta?",
        a: "Ajustes, depois Apagar conta. Seu nome, e-mail e foto são removidos na hora. As despesas que você compartilhou continuam nos grupos como Membro removido, para os saldos dos outros continuarem fechando.",
      },
      {
        q: "Como mudo o idioma do app?",
        a: "Ajustes, depois Idioma. O app troca sem precisar reiniciar.",
      },
    ],
  },
};
