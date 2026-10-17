import type { Dictionary } from "./en";

export const es: Dictionary = {
  meta: {
    title: "Splitty: divide los gastos, salda las cuentas",
    description:
      "Splitty lleva una cuenta compartida para viajes, pisos y cenas: quién pagó, quién debe y los pagos mínimos para saldarlo todo. Pronto en iPhone.",
  },
  nav: {
    privacy: "Privacidad",
    terms: "Términos",
    support: "Soporte",
    language: "Idioma",
    home: "Inicio de Splitty",
  },
  hero: {
    title: "Divide los gastos, salda las cuentas.",
    lede: "Una cuenta compartida para el viaje, el piso o la cena del viernes. Anota quién pagó, divide con justicia y mira los pagos mínimos para que todos queden al día.",
    store: "Pronto en el App Store",
    platform: "Para iPhone y iPad. Gratis.",
  },
  story: {
    steps: [
      {
        title: "Anótalo antes de olvidarlo",
        body: "Escribe el importe y elige quién pagó. El gasto aparece en la cronología del grupo para todos, con lo que debe cada uno.",
      },
      {
        title: "Divídelo como fue",
        body: "A partes iguales, por importes o por porcentajes. Splitty comprueba que las partes sumen el total antes de guardar.",
      },
      {
        title: "Menos pagos",
        body: "Splitty compensa quién le debe a quién en todo el grupo, y un enredo de pequeñas deudas se queda en unos pocos pagos directos.",
      },
      {
        title: "Salda las cuentas",
        body: "Registra un pago y el saldo queda en cero. Splitty nunca toca tu dinero. Solo mantiene las cuentas claras.",
      },
    ],
  },
  phone: {
    group: "Viaje a Lisboa",
    today: "Hoy",
    yesterday: "Ayer",
    oweOverall: "Debes {amount} en total",
    paid: "{name} ha pagado {amount}",
    youBorrowed: "has pedido prestado",
    next: "Siguiente",
    cancel: "Cancelar",
    save: "Guardar",
    done: "Listo",
    splitTitle: "Dividir",
    paidBy: "Pagado por",
    selectAll: "Todos",
    selectNone: "Ninguno",
    allAssigned: "Todo asignado",
    each: "{amount} cada uno",
    people: "{count} personas",
    assignedOf: "{assigned} de {total}",
    settleUp: "Saldar",
    charts: "Gráficos",
    export: "Exportar",
    expensesTab: "Gastos",
    plansTab: "Planes",
    diningOut: "Comer fuera",
    groceries: "Supermercado",
    whatFor: "¿En qué se ha gastado?",
    games: "Juegos",
    equally: "A partes iguales",
    amounts: "Importes",
    percentages: "Porcentajes",
    splitBetween: "Dividir entre",
    summary: {
      equally: "Pagado por Caio y dividido a partes iguales",
      amounts: "Pagado por Caio y dividido por importes",
      percentages: "Pagado por Caio y dividido por porcentajes",
    },
    you: "Tú",
    balances: "Saldos",
    payments: { before: "6 pagos", after: "3 pagos" },
    youOwePeer: "Debes {amount} a {name}",
    peerOwesPeer: "{from} debe {amount} a {to}",
    pay: "Pagar {amount}",
    settled: "Estás al día",
    expenses: {
      apartment: "Apartamento",
      taxi: "Taxi desde el aeropuerto",
      dinner: "Cena en la tasca",
    },
  },
  more: {
    title: "Y además",
    items: [
      {
        title: "Gastos recurrentes",
        body: "El alquiler, las suscripciones y las cuotas se añaden solos en su fecha, y puedes ver por qué cuota va cada uno.",
      },
      {
        title: "En qué se fue",
        body: "Gasto por categoría y los gastos más grandes, desde este mes hasta todo el historial, del grupo o solo de tu parte.",
      },
      {
        title: "Únete con un código",
        body: "Comparte un código de seis caracteres. Sin enlaces que reenviar ni contactos que subir.",
      },
      {
        title: "Exporta a CSV",
        body: "Lleva los gastos de un grupo a una hoja de cálculo cuando quieras.",
      },
      {
        title: "Cuatro idiomas",
        body: "English, Português, Español y Français, y se cambian dentro de la app.",
      },
      {
        title: "Tu cuenta, tu decisión",
        body: "Desactívala un tiempo o elimínala para siempre desde Ajustes.",
      },
    ],
  },
  closing: {
    title: "Todos al día.",
    body: "Splitty llega pronto al App Store.",
  },
  footer: {
    madeBy: "Hecho en Brasil.",
  },
  legal: {
    updated: "Última actualización: {date}",
    back: "Volver a Splitty",
    privacyTitle: "Política de privacidad",
    termsTitle: "Términos de uso",
  },
  support: {
    title: "Soporte",
    lede: "Escríbenos y te responderá una persona, normalmente en dos días laborables.",
    email: "Escribir a soporte",
    faqTitle: "Preguntas frecuentes",
    faq: [
      {
        q: "¿Cómo añado a alguien a un grupo?",
        a: "Abre el grupo, luego Ajustes del grupo e Invitar a personas. Envíale el código de seis caracteres. Lo introduce en Unirse con código.",
      },
      {
        q: "¿Splitty envía o recibe dinero?",
        a: "No. Splitty registra lo que cada uno pagó y debe. Cuando le pagues a alguien fuera de la app, registra el pago con Saldar para que el saldo se actualice.",
      },
      {
        q: "¿Quién puede editar un gasto?",
        a: "Cualquier miembro del grupo puede añadir, editar o eliminar cualquier gasto del grupo. Los grupos funcionan sobre la confianza entre sus miembros.",
      },
      {
        q: "¿Cómo obtengo mis datos?",
        a: "Abre un grupo y toca Exportar para guardar sus gastos en un archivo CSV. Para recibir una copia de todo lo que tenemos sobre ti, escríbenos.",
      },
      {
        q: "¿Cómo elimino mi cuenta?",
        a: "Ajustes y luego Eliminar cuenta. Tu nombre, correo y foto se borran al momento. Los gastos que compartiste siguen en tus grupos como Miembro eliminado, para que los saldos de los demás sigan cuadrando.",
      },
      {
        q: "¿Cómo cambio el idioma de la app?",
        a: "Ajustes y luego Idioma. La app cambia sin reiniciarse.",
      },
    ],
  },
};
