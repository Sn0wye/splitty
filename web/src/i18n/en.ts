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
        body: "Type the amount and pick who paid. The expense shows up in the group's timeline for everyone, with what each person owes.",
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
        body: "Record a payment and the balance goes to zero. Splitty never touches your money. It keeps the record straight.",
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
    // split.people (plural "other") / split.assigned_of, group.settle_up / group.charts /
    // group.export, plans.expenses / plans.title, category.dining_out / category.groceries /
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
    export: "Export",
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
    // app: settlement.pay
    pay: "Pay {amount}",
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
        body: "Take a group's expenses into a spreadsheet whenever you want.",
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
        a: "No. Splitty records what people paid and owe. When you pay someone back outside the app, record the payment with Settle up so the balance updates.",
      },
      {
        q: "Who can edit an expense?",
        a: "Any member of the group can add, edit or delete any expense in it. Groups work on trust between the people in them.",
      },
      {
        q: "How do I get my data out?",
        a: "Open a group and tap Export to save its expenses as a CSV file. For a copy of everything we hold about you, email us.",
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
