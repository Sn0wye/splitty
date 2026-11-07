/**
 * English copy, and the shape every other language must match. Strings marked "app" are the
 * iOS catalog's own wording (`Localizable.xcstrings`), so the drawn phone says what the real
 * one says.
 */
export const en = {
  meta: {
    title: "Splitty: split expenses, settle up",
    description:
      "Splitty keeps a shared tab for trips, flats and dinners: who paid, who owes, and the fewest payments to settle it. Coming to iPhone.",
  },
  nav: {
    privacy: "Privacy",
    terms: "Terms",
    support: "Support",
    language: "Language",
    home: "Splitty home",
  },
  hero: {
    // app: login.tagline
    title: "Split expenses, settle up.",
    lede: "One shared tab for the trip, the flat or Friday dinner. Log who paid, split it fairly, and see the fewest payments that make everyone square.",
    store: "Coming soon to the App Store",
    platform: "For iPhone and iPad. Free.",
  },
  story: {
    steps: [
      {
        title: "Log it before you forget",
        body: "Tap +, type the amount and say what it was for. The keyboard is already up when you get there. The expense lands in the group's timeline with what each person owes.",
      },
      {
        title: "Split it the way it happened",
        body: "Equally, by amounts or by percentages. Splitty checks that the shares add up to the total before it saves.",
      },
      {
        title: "Fewer payments",
        body: "Splitty nets out who owes whom across the whole group, so a tangle of small debts turns into a few direct payments.",
      },
      {
        title: "Settle up",
        body: "Pick who paid and who got it. Pay all fills in the whole debt, and when you're square the coin comes back together. Either side can record it. Splitty never touches your money.",
      },
    ],
  },
  phone: {
    group: "Lisbon trip",
    // app: common.today / common.yesterday
    today: "Today",
    yesterday: "Yesterday",
    // app: balances.owe_overall_amount
    oweOverall: "You owe {amount} overall",
    // app: group.payer_paid_amount
    paid: "{name} paid {amount}",
    // app: group.you_borrowed
    youBorrowed: "you borrowed",
    // app: common.next
    next: "Next",
    // app: common.cancel / common.save / common.done, split.title / split.paid_by /
    // split.select_all / split.select_none / split.all_assigned / split.each /
    // split.people (plural "other") / split.assigned_of, group.settle_up / group.charts,
    // plans.expenses / plans.title, category.dining_out / category.groceries /
    // category.games, expense.what_for
    cancel: "Cancel",
    save: "Save",
    done: "Done",
    splitTitle: "Split",
    paidBy: "Paid by",
    selectAll: "All",
    selectNone: "None",
    allAssigned: "All assigned",
    each: "{amount} each",
    people: "{count} people",
    assignedOf: "{assigned} of {total}",
    settleUp: "Settle up",
    charts: "Charts",
    expensesTab: "Expenses",
    plansTab: "Plans",
    diningOut: "Dining out",
    groceries: "Groceries",
    whatFor: "What was it for?",
    games: "Games",
    // app: split.equally / split.amounts / split.percentages
    equally: "Equally",
    amounts: "Amounts",
    percentages: "Percentages",
    // app: split.between
    splitBetween: "Split between",
    // app: split.summary_* (paid by Caio)
    summary: {
      equally: "Paid by Caio and split equally",
      amounts: "Paid by Caio and split by amounts",
      percentages: "Paid by Caio and split by percentages",
    },
    you: "You",
    // app: balances.title
    balances: "Balances",
    payments: { before: "6 payments", after: "3 payments" },
    // app: balances.you_owe_peer
    youOwePeer: "You owe {name} {amount}",
    // app: balances.peer_owes_peer
    peerOwesPeer: "{from} owes {to} {amount}",
    // app: settlement.settle_up / settlement.who_paid / settlement.paid_to_whom /
    // settlement.record / settlement.pay_all / group.payer_paid_payee / balances.settle
    settleTitle: "Settle up",
    whoPaid: "Who paid?",
    toWhom: "To whom?",
    recordPayment: "Record payment",
    payAll: "Pay all {amount}",
    payerPaidPayee: "{payer} paid {payee}",
    settle: "Settle",
    // app: balances.all_settled
    settled: "You are all settled up",
    expenses: {
      apartment: "Apartment",
      taxi: "Taxi from the airport",
      dinner: "Dinner at the tasca",
    },
  },
  more: {
    title: "Also in Splitty",
    offline: {
      title: "Works with no signal",
      body: "Your groups stay on the phone. Add an expense on the plane and it sends itself when you land. Until then Splitty marks what hasn't gone out, and says the balance is an estimate.",
      // app: sync.offline / sync.waiting (one)
      banner: "Offline. Changes are sent when you reconnect.",
      waiting: "1 change waiting to send",
      // app: sync.estimate
      estimate: "Estimate, includes changes not sent yet",
    },
    currencies: {
      title: "Each group in its own currency",
      body: "Dollars for the roommates, euros for the trip. Balances in different currencies are never added together, and a new group starts in your region's.",
      // app: groups.title / balances.owed_overall_amount / balances.owe_overall_amount /
      // groups.more_currencies / groups.you_are_owed / groups.you_owe
      groupsTitle: "Groups",
      owedOverall: "You are owed {amount} overall",
      oweOverall: "You owe {amount} overall",
      moreCurrencies: "+2 currencies",
      youAreOwed: "You are owed",
      youOwe: "You owe",
      groups: [
        { name: "Roommates", currency: "USD", net: 86.4 },
        { name: "Lisbon trip", currency: "EUR", net: -165 },
        { name: "London weekend", currency: "GBP", net: 38.2 },
      ],
    },
    items: [
      {
        title: "Recurring expenses",
        body: "Rent, subscriptions and installments add themselves on schedule, and you can see how far along each one is.",
      },
      {
        title: "Where it went",
        body: "Spending by category and the biggest expenses, from this month to all time, for the group or only your share.",
      },
      {
        title: "Join with a code",
        body: "Share a six-character code. No links to forward, no contacts to upload.",
      },
      {
        title: "Export to CSV",
        body: "From the group's settings, take its expenses into a spreadsheet whenever you want.",
      },
      {
        title: "Four languages",
        body: "English, Português, Español and Français, switchable inside the app.",
      },
      {
        title: "Your account, your call",
        body: "Deactivate it for a while, or delete it for good, from Settings.",
      },
    ],
  },
  closing: {
    title: "Everyone square.",
    body: "Splitty is coming to the App Store soon.",
  },
  footer: {
    madeBy: "Made in Brazil.",
  },
  legal: {
    updated: "Last updated {date}",
    back: "Back to Splitty",
    privacyTitle: "Privacy Policy",
    termsTitle: "Terms of Use",
  },
  support: {
    title: "Support",
    lede: "Write to us and a person will reply, usually within two working days.",
    email: "Email support",
    faqTitle: "Common questions",
    faq: [
      {
        q: "How do I add someone to a group?",
        a: "Open the group, then Group settings, then Invite people. Send them the six-character code. They enter it under Join with code.",
      },
      {
        q: "Does Splitty send or receive money?",
        a: "No. Splitty records what people paid and owe. When someone pays someone back outside the app, either of them records it with Settle up and the balance updates.",
      },
      {
        q: "Who can edit an expense?",
        a: "Any member of the group can add, edit or delete any expense in it. Groups work on trust between the people in them.",
      },
      {
        q: "How do I get my data out?",
        a: "Open the group, then Group settings, then Export expenses (CSV). For a copy of everything we hold about you, email us.",
      },
      {
        q: "How do I delete my account?",
        a: "Settings, then Delete account. Your name, email and photo are removed right away. Expenses you shared stay in your groups as Removed member, so other people's balances still add up.",
      },
      {
        q: "How do I change the app's language?",
        a: "Settings, then Language. The app switches without restarting.",
      },
    ],
  },
};

export type Dictionary = typeof en;
