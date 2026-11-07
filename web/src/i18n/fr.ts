import type { Dictionary } from "./en";

export const fr: Dictionary = {
  meta: {
    title: "Splitty : répartissez les dépenses, réglez les comptes",
    description:
      "Splitty tient un compte partagé pour les voyages, les colocations et les dîners : qui a payé, qui doit quoi, et le moins de paiements possible pour tout régler. Bientôt sur iPhone.",
  },
  nav: {
    privacy: "Confidentialité",
    terms: "Conditions",
    support: "Assistance",
    language: "Langue",
    home: "Accueil Splitty",
  },
  hero: {
    title: "Répartissez les dépenses, réglez les comptes.",
    lede: "Un compte partagé pour le voyage, la coloc ou le dîner du vendredi. Notez qui a payé, répartissez équitablement et voyez le moins de paiements possible pour que tout le monde soit quitte.",
    store: "Bientôt sur l’App Store",
    platform: "Pour iPhone et iPad. Gratuit.",
  },
  story: {
    steps: [
      {
        title: "Notez-la avant d’oublier",
        body: "Touchez +, tapez le montant et dites à quoi il a servi. Le clavier est déjà ouvert quand vous y arrivez. La dépense arrive dans la chronologie du groupe avec ce que chacun doit.",
      },
      {
        title: "Répartissez comme ça s’est passé",
        body: "À parts égales, selon les montants ou selon les pourcentages. Splitty vérifie que les parts font bien le total avant d’enregistrer.",
      },
      {
        title: "Moins de paiements",
        body: "Splitty compense qui doit quoi à qui dans tout le groupe, et un enchevêtrement de petites dettes devient quelques paiements directs.",
      },
      {
        title: "Réglez les comptes",
        body: "Choisissez qui a payé et à qui. Payer la totalité remplit toute la dette et, une fois quittes, la pièce se ressoude. Chacun des deux peut l’enregistrer. Splitty ne touche jamais à votre argent.",
      },
    ],
  },
  phone: {
    group: "Voyage à Lisbonne",
    today: "Aujourd’hui",
    yesterday: "Hier",
    oweOverall: "Vous devez {amount} au total",
    paid: "{name} a payé {amount}",
    youBorrowed: "vous avez emprunté",
    next: "Suivant",
    cancel: "Annuler",
    save: "Enregistrer",
    done: "Terminé",
    splitTitle: "Répartition",
    paidBy: "Payé par",
    selectAll: "Tous",
    selectNone: "Aucun",
    allAssigned: "Tout est attribué",
    each: "{amount} chacun",
    people: "{count} personnes",
    assignedOf: "{assigned} sur {total}",
    settleUp: "Régler",
    charts: "Graphiques",
    expensesTab: "Dépenses",
    plansTab: "Plans",
    diningOut: "Restaurants",
    groceries: "Courses",
    whatFor: "À quoi correspond cette dépense ?",
    games: "Jeux",
    equally: "À parts égales",
    amounts: "Montants",
    percentages: "Pourcentages",
    splitBetween: "Répartir entre",
    summary: {
      equally: "Payé par Caio et réparti à parts égales",
      amounts: "Payé par Caio et réparti selon les montants",
      percentages: "Payé par Caio et réparti selon les pourcentages",
    },
    you: "Vous",
    balances: "Soldes",
    payments: { before: "6 paiements", after: "3 paiements" },
    youOwePeer: "Vous devez {amount} à {name}",
    peerOwesPeer: "{from} doit {amount} à {to}",
    settleTitle: "Régler",
    whoPaid: "Qui a payé ?",
    toWhom: "À qui ?",
    recordPayment: "Enregistrer le paiement",
    payAll: "Payer la totalité à {amount}",
    payerPaidPayee: "{payer} a payé {payee}",
    settle: "Régler",
    settled: "Tout est réglé pour vous",
    expenses: {
      apartment: "Appartement",
      taxi: "Taxi depuis l’aéroport",
      dinner: "Dîner à la tasca",
    },
  },
  more: {
    title: "Et aussi",
    offline: {
      title: "Fonctionne sans réseau",
      body: "Vos groupes restent sur le téléphone. Ajoutez une dépense dans l’avion, elle part toute seule à l’atterrissage. En attendant, Splitty signale ce qui n’est pas encore parti et indique que le solde est une estimation.",
      banner: "Hors ligne. Les modifications sont envoyées à la reconnexion.",
      waiting: "1 modification en attente d’envoi",
      estimate: "Estimation, inclut des modifications pas encore envoyées",
    },
    currencies: {
      title: "Chaque groupe dans sa devise",
      body: "Des euros pour la coloc, des livres pour le voyage. Les soldes en devises différentes ne sont jamais additionnés, et un nouveau groupe démarre dans la devise de votre région.",
      groupsTitle: "Groupes",
      owedOverall: "On vous doit {amount} au total",
      oweOverall: "Vous devez {amount} au total",
      moreCurrencies: "+2 devises",
      youAreOwed: "On vous doit",
      youOwe: "Vous devez",
      groups: [
        { name: "Coloc", currency: "EUR", net: 86.4 },
        { name: "Week-end à Londres", currency: "GBP", net: -38.2 },
        { name: "Voyage à Rio", currency: "BRL", net: 412.5 },
      ],
    },
    items: [
      {
        title: "Dépenses récurrentes",
        body: "Le loyer, les abonnements et les échéances s’ajoutent tout seuls à la bonne date, et vous voyez où en est chacun.",
      },
      {
        title: "Où est passé l’argent",
        body: "Les dépenses par catégorie et les plus grosses dépenses, de ce mois-ci à tout l’historique, pour le groupe ou seulement votre part.",
      },
      {
        title: "Rejoindre avec un code",
        body: "Partagez un code à six caractères. Aucun lien à transférer, aucun contact à importer.",
      },
      {
        title: "Export CSV",
        body: "Depuis les réglages du groupe, emportez ses dépenses dans un tableur quand vous voulez.",
      },
      {
        title: "Quatre langues",
        body: "English, Português, Español et Français, à changer depuis l’app.",
      },
      {
        title: "Votre compte, votre choix",
        body: "Désactivez-le un temps ou supprimez-le pour de bon, depuis les Réglages.",
      },
    ],
  },
  closing: {
    title: "Tout le monde est quitte.",
    body: "Splitty arrive bientôt sur l’App Store.",
  },
  footer: {
    madeBy: "Fait au Brésil.",
  },
  legal: {
    updated: "Dernière mise à jour : {date}",
    back: "Retour à Splitty",
    privacyTitle: "Politique de confidentialité",
    termsTitle: "Conditions d’utilisation",
  },
  support: {
    title: "Assistance",
    lede: "Écrivez-nous et une personne vous répondra, en général sous deux jours ouvrés.",
    email: "Écrire à l’assistance",
    faqTitle: "Questions fréquentes",
    faq: [
      {
        q: "Comment ajouter quelqu’un à un groupe ?",
        a: "Ouvrez le groupe, puis Réglages du groupe et Inviter des personnes. Envoyez le code à six caractères. La personne le saisit dans Rejoindre avec un code.",
      },
      {
        q: "Splitty envoie-t-il ou reçoit-il de l’argent ?",
        a: "Non. Splitty enregistre ce que chacun a payé et doit. Quand quelqu’un rembourse une autre personne en dehors de l’app, l’un ou l’autre l’enregistre avec Régler et le solde se met à jour.",
      },
      {
        q: "Qui peut modifier une dépense ?",
        a: "Tout membre du groupe peut ajouter, modifier ou supprimer n’importe quelle dépense du groupe. Les groupes reposent sur la confiance entre leurs membres.",
      },
      {
        q: "Comment récupérer mes données ?",
        a: "Ouvrez le groupe, puis Réglages du groupe, puis Exporter les dépenses (CSV). Pour une copie de tout ce que nous détenons sur vous, écrivez-nous.",
      },
      {
        q: "Comment supprimer mon compte ?",
        a: "Réglages, puis Supprimer le compte. Votre nom, votre e-mail et votre photo sont effacés immédiatement. Les dépenses que vous avez partagées restent dans vos groupes sous Membre retiré, pour que les soldes des autres restent justes.",
      },
      {
        q: "Comment changer la langue de l’app ?",
        a: "Réglages, puis Langue. L’app change sans redémarrer.",
      },
    ],
  },
};
