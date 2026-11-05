using System.Globalization;
using Splitty.Domain.Entities;

namespace Splitty.Service;

/// <summary>
/// The words of a push notification, in the language the device picked inside the app. iOS
/// would render a <c>loc-key</c> in the system language instead, which is not the app's, so
/// the server writes the text. The title is the group; the body says who did what and the
/// amount that matters to the reader.
///
/// No sentence uses a gendered pronoun or article for a person: a name says nothing about
/// gender. Every amount is written the way its currency writes it, whatever the language, as
/// the app does (ADR 0007).
/// </summary>
public static class PushCopy
{
    public const string DefaultLanguage = "en";

    private const int MaxNameLength = 20;
    private const int MaxDescriptionLength = 30;

    /// The app's language codes, the same strings as its <c>AppLanguage</c> raw values.
    public static IReadOnlyCollection<string> Languages => Copy.Keys;

    /// <param name="names">Display names by user id, for the actor and the peer.</param>
    public static (string Title, string Body) Render(
        Notice notice,
        string language,
        string groupName,
        Currency currency,
        IReadOnlyDictionary<int, string> names)
    {
        var copy = Copy.GetValueOrDefault(language) ?? Copy[DefaultLanguage];

        string Name(int? id) => id is { } known && names.TryGetValue(known, out var name)
            ? (name == User.TombstoneName ? copy.RemovedMember : Shorten(name, MaxNameLength))
            : copy.RemovedMember;

        string Money(decimal? amount) => Format(amount ?? 0, currency);

        var actor = Name(notice.ActorId);
        var description = Shorten(notice.Description ?? string.Empty, MaxDescriptionLength);
        var frequency = notice.Frequency is { } f ? copy.Frequencies[f] : string.Empty;

        object[] args = notice.Message switch
        {
            NoticeMessage.ExpenseAdded or NoticeMessage.ExpenseAddedPaidByYou
                or NoticeMessage.ExpenseIncludedYou or NoticeMessage.ExpenseDeleted
                or NoticeMessage.ExpenseDeletedPaidByYou => [actor, description, Money(notice.Amount)],
            NoticeMessage.RecurringExpenseAdded or NoticeMessage.RecurringExpenseAddedPaidByYou =>
                [actor, description, frequency, Money(notice.Amount)],
            NoticeMessage.ExpenseShareChanged or NoticeMessage.ExpensePaidTotalChanged =>
                [actor, description, Money(notice.Before), Money(notice.Amount)],
            NoticeMessage.ExpenseRemovedYou or NoticeMessage.ExpensePayerChanged => [actor, description],
            NoticeMessage.PaymentReceived or NoticeMessage.PaymentToYouDeletedByPayer
                or NoticeMessage.YourPaymentDeletedByPayee or NoticeMessage.PaymentReminder =>
                [actor, Money(notice.Amount)],
            NoticeMessage.PaymentToYouChangedByPayer or NoticeMessage.YourPaymentChangedByPayee =>
                [actor, Money(notice.Before), Money(notice.Amount)],
            NoticeMessage.PaymentToYouChanged or NoticeMessage.YourPaymentChanged =>
                [actor, Name(notice.PeerId), Money(notice.Before), Money(notice.Amount)],
            NoticeMessage.PaymentToYouDeleted or NoticeMessage.YourPaymentDeleted =>
                [actor, Name(notice.PeerId), Money(notice.Amount)],
            NoticeMessage.InviteAccepted or NoticeMessage.RemovedFromGroup => [actor],
            _ => throw new ArgumentOutOfRangeException(nameof(notice), notice.Message, null)
        };

        return (groupName, string.Format(CultureInfo.InvariantCulture, copy.Messages[notice.Message], args));
    }

    /// <summary>
    /// <c>R$ 1.234,50</c>, <c>1.234,50 €</c>, <c>$1,234.50</c>: symbol, side, spacing and
    /// separators from the currency, matching the iOS client's <c>Currency</c> table.
    /// </summary>
    public static string Format(decimal amount, Currency currency)
    {
        var (symbol, after, spaced, decimalSeparator, groupSeparator) = currency switch
        {
            Currency.USD => ("$", false, false, ".", ","),
            Currency.CAD => ("CA$", false, false, ".", ","),
            Currency.AUD => ("A$", false, false, ".", ","),
            Currency.MXN => ("MX$", false, false, ".", ","),
            Currency.GBP => ("£", false, false, ".", ","),
            Currency.BRL => ("R$", false, true, ",", "."),
            Currency.EUR => ("€", true, true, ",", "."),
            Currency.CHF => ("CHF", false, true, ".", "'"),
            _ => throw new ArgumentOutOfRangeException(nameof(currency), currency, null)
        };

        var number = Math.Abs(amount).ToString("N2", new NumberFormatInfo
        {
            NumberDecimalSeparator = decimalSeparator,
            NumberGroupSeparator = groupSeparator
        });
        var space = spaced ? " " : string.Empty;

        return after ? $"{number}{space}{symbol}" : $"{symbol}{space}{number}";
    }

    /// Cut by grapheme, so an emoji in a name is never split in half.
    private static string Shorten(string text, int max)
    {
        var trimmed = text.Trim();
        var info = new StringInfo(trimmed);

        return info.LengthInTextElements <= max
            ? trimmed
            : info.SubstringByTextElements(0, max - 1).TrimEnd() + "…";
    }

    private sealed record Language(
        string RemovedMember,
        IReadOnlyDictionary<RepeatFrequency, string> Frequencies,
        IReadOnlyDictionary<NoticeMessage, string> Messages);

    private static readonly Dictionary<string, Language> Copy = new()
    {
        ["en"] = new Language(
            "Removed member",
            new Dictionary<RepeatFrequency, string>
            {
                [RepeatFrequency.Weekly] = "every week",
                [RepeatFrequency.Fortnightly] = "every 2 weeks",
                [RepeatFrequency.Monthly] = "every month",
                [RepeatFrequency.Yearly] = "every year",
            },
            new Dictionary<NoticeMessage, string>
            {
                [NoticeMessage.ExpenseAdded] = "{0} added {1}. Your share: {2}",
                [NoticeMessage.ExpenseAddedPaidByYou] = "{0} added {1}, paid by you: {2}",
                [NoticeMessage.RecurringExpenseAdded] = "{0} added {1}, {2}. Your share: {3}",
                [NoticeMessage.RecurringExpenseAddedPaidByYou] = "{0} added {1}, {2}, paid by you: {3}",
                [NoticeMessage.ExpenseShareChanged] = "{0} changed {1}. Your share: {2} → {3}",
                [NoticeMessage.ExpenseIncludedYou] = "{0} added you to {1}. Your share: {2}",
                [NoticeMessage.ExpenseRemovedYou] = "{0} removed you from {1}",
                [NoticeMessage.ExpensePaidTotalChanged] = "{0} changed {1}, paid by you: {2} → {3}",
                [NoticeMessage.ExpensePayerChanged] = "{0} changed who paid {1}",
                [NoticeMessage.ExpenseDeleted] = "{0} deleted {1}. Your share was {2}",
                [NoticeMessage.ExpenseDeletedPaidByYou] = "{0} deleted {1}, paid by you: {2}",
                [NoticeMessage.PaymentReceived] = "{0} paid you {1}",
                [NoticeMessage.PaymentToYouChangedByPayer] = "{0} changed their payment to you: {1} → {2}",
                [NoticeMessage.PaymentToYouChanged] = "{0} changed {1}'s payment to you: {2} → {3}",
                [NoticeMessage.YourPaymentChangedByPayee] = "{0} changed your payment: {1} → {2}",
                [NoticeMessage.YourPaymentChanged] = "{0} changed your payment to {1}: {2} → {3}",
                [NoticeMessage.PaymentToYouDeletedByPayer] = "{0} deleted their payment of {1} to you",
                [NoticeMessage.PaymentToYouDeleted] = "{0} deleted {1}'s payment of {2} to you",
                [NoticeMessage.YourPaymentDeletedByPayee] = "{0} deleted your payment of {1}",
                [NoticeMessage.YourPaymentDeleted] = "{0} deleted your payment of {2} to {1}",
                [NoticeMessage.PaymentReminder] = "{0} asked you to pay {1}",
                [NoticeMessage.InviteAccepted] = "{0} joined the group with your invite",
                [NoticeMessage.RemovedFromGroup] = "{0} removed you from the group",
            }),
        ["pt-BR"] = new Language(
            "Membro removido",
            new Dictionary<RepeatFrequency, string>
            {
                [RepeatFrequency.Weekly] = "toda semana",
                [RepeatFrequency.Fortnightly] = "a cada 2 semanas",
                [RepeatFrequency.Monthly] = "todo mês",
                [RepeatFrequency.Yearly] = "todo ano",
            },
            new Dictionary<NoticeMessage, string>
            {
                [NoticeMessage.ExpenseAdded] = "{0} adicionou {1}. Sua parte: {2}",
                [NoticeMessage.ExpenseAddedPaidByYou] = "{0} adicionou {1}, pago por você: {2}",
                [NoticeMessage.RecurringExpenseAdded] = "{0} adicionou {1}, {2}. Sua parte: {3}",
                [NoticeMessage.RecurringExpenseAddedPaidByYou] = "{0} adicionou {1}, {2}, pago por você: {3}",
                [NoticeMessage.ExpenseShareChanged] = "{0} mudou {1}. Sua parte: {2} → {3}",
                [NoticeMessage.ExpenseIncludedYou] = "{0} incluiu você em {1}. Sua parte: {2}",
                [NoticeMessage.ExpenseRemovedYou] = "{0} tirou você de {1}",
                [NoticeMessage.ExpensePaidTotalChanged] = "{0} mudou {1}, pago por você: {2} → {3}",
                [NoticeMessage.ExpensePayerChanged] = "{0} mudou quem pagou {1}",
                [NoticeMessage.ExpenseDeleted] = "{0} apagou {1}. Sua parte era {2}",
                [NoticeMessage.ExpenseDeletedPaidByYou] = "{0} apagou {1}, pago por você: {2}",
                [NoticeMessage.PaymentReceived] = "{0} pagou {1} para você",
                [NoticeMessage.PaymentToYouChangedByPayer] = "{0} mudou o pagamento para você: {1} → {2}",
                [NoticeMessage.PaymentToYouChanged] = "{0} mudou o pagamento de {1}: {2} → {3}",
                [NoticeMessage.YourPaymentChangedByPayee] = "{0} mudou seu pagamento: {1} → {2}",
                [NoticeMessage.YourPaymentChanged] = "{0} mudou seu pagamento para {1}: {2} → {3}",
                [NoticeMessage.PaymentToYouDeletedByPayer] = "{0} apagou o pagamento de {1} para você",
                [NoticeMessage.PaymentToYouDeleted] = "{0} apagou o pagamento de {2} de {1}",
                [NoticeMessage.YourPaymentDeletedByPayee] = "{0} apagou seu pagamento de {1}",
                [NoticeMessage.YourPaymentDeleted] = "{0} apagou seu pagamento de {2} para {1}",
                [NoticeMessage.PaymentReminder] = "{0} pediu o pagamento de {1}",
                [NoticeMessage.InviteAccepted] = "{0} entrou no grupo pelo seu convite",
                [NoticeMessage.RemovedFromGroup] = "{0} removeu você do grupo",
            }),
        ["es"] = new Language(
            "Miembro eliminado",
            new Dictionary<RepeatFrequency, string>
            {
                [RepeatFrequency.Weekly] = "cada semana",
                [RepeatFrequency.Fortnightly] = "cada 2 semanas",
                [RepeatFrequency.Monthly] = "cada mes",
                [RepeatFrequency.Yearly] = "cada año",
            },
            new Dictionary<NoticeMessage, string>
            {
                [NoticeMessage.ExpenseAdded] = "{0} ha añadido {1}. Tu parte: {2}",
                [NoticeMessage.ExpenseAddedPaidByYou] = "{0} ha añadido {1}, pagado por ti: {2}",
                [NoticeMessage.RecurringExpenseAdded] = "{0} ha añadido {1}, {2}. Tu parte: {3}",
                [NoticeMessage.RecurringExpenseAddedPaidByYou] = "{0} ha añadido {1}, {2}, pagado por ti: {3}",
                [NoticeMessage.ExpenseShareChanged] = "{0} ha cambiado {1}. Tu parte: {2} → {3}",
                [NoticeMessage.ExpenseIncludedYou] = "{0} te ha incluido en {1}. Tu parte: {2}",
                [NoticeMessage.ExpenseRemovedYou] = "{0} te ha quitado de {1}",
                [NoticeMessage.ExpensePaidTotalChanged] = "{0} ha cambiado {1}, pagado por ti: {2} → {3}",
                [NoticeMessage.ExpensePayerChanged] = "{0} ha cambiado quién pagó {1}",
                [NoticeMessage.ExpenseDeleted] = "{0} ha eliminado {1}. Tu parte era {2}",
                [NoticeMessage.ExpenseDeletedPaidByYou] = "{0} ha eliminado {1}, pagado por ti: {2}",
                [NoticeMessage.PaymentReceived] = "{0} te ha pagado {1}",
                [NoticeMessage.PaymentToYouChangedByPayer] = "{0} ha cambiado su pago para ti: {1} → {2}",
                [NoticeMessage.PaymentToYouChanged] = "{0} ha cambiado el pago de {1}: {2} → {3}",
                [NoticeMessage.YourPaymentChangedByPayee] = "{0} ha cambiado tu pago: {1} → {2}",
                [NoticeMessage.YourPaymentChanged] = "{0} ha cambiado tu pago a {1}: {2} → {3}",
                [NoticeMessage.PaymentToYouDeletedByPayer] = "{0} ha eliminado su pago de {1} para ti",
                [NoticeMessage.PaymentToYouDeleted] = "{0} ha eliminado el pago de {2} de {1}",
                [NoticeMessage.YourPaymentDeletedByPayee] = "{0} ha eliminado tu pago de {1}",
                [NoticeMessage.YourPaymentDeleted] = "{0} ha eliminado tu pago de {2} a {1}",
                [NoticeMessage.PaymentReminder] = "{0} te ha pedido el pago de {1}",
                [NoticeMessage.InviteAccepted] = "{0} se ha unido al grupo con tu invitación",
                [NoticeMessage.RemovedFromGroup] = "{0} te ha quitado del grupo",
            }),
        // "Vous" with a past participle agreeing with it would have to guess a gender, so the
        // French sentences put "votre part" or "votre participation" where the others say "you".
        ["fr"] = new Language(
            "Membre retiré",
            new Dictionary<RepeatFrequency, string>
            {
                [RepeatFrequency.Weekly] = "chaque semaine",
                [RepeatFrequency.Fortnightly] = "toutes les 2 semaines",
                [RepeatFrequency.Monthly] = "chaque mois",
                [RepeatFrequency.Yearly] = "chaque année",
            },
            new Dictionary<NoticeMessage, string>
            {
                [NoticeMessage.ExpenseAdded] = "{0} a ajouté {1}. Votre part : {2}",
                [NoticeMessage.ExpenseAddedPaidByYou] = "{0} a ajouté {1}, payé par vous : {2}",
                [NoticeMessage.RecurringExpenseAdded] = "{0} a ajouté {1}, {2}. Votre part : {3}",
                [NoticeMessage.RecurringExpenseAddedPaidByYou] = "{0} a ajouté {1}, {2}, payé par vous : {3}",
                [NoticeMessage.ExpenseShareChanged] = "{0} a modifié {1}. Votre part : {2} → {3}",
                [NoticeMessage.ExpenseIncludedYou] = "{0} a ajouté votre part à {1} : {2}",
                [NoticeMessage.ExpenseRemovedYou] = "{0} a retiré votre part de {1}",
                [NoticeMessage.ExpensePaidTotalChanged] = "{0} a modifié {1}, payé par vous : {2} → {3}",
                [NoticeMessage.ExpensePayerChanged] = "{0} a changé le payeur de {1}",
                [NoticeMessage.ExpenseDeleted] = "{0} a supprimé {1}. Votre part était de {2}",
                [NoticeMessage.ExpenseDeletedPaidByYou] = "{0} a supprimé {1}, payé par vous : {2}",
                [NoticeMessage.PaymentReceived] = "{0} vous a payé {1}",
                [NoticeMessage.PaymentToYouChangedByPayer] = "{0} a modifié son paiement pour vous : {1} → {2}",
                [NoticeMessage.PaymentToYouChanged] = "{0} a modifié le paiement de {1} : {2} → {3}",
                [NoticeMessage.YourPaymentChangedByPayee] = "{0} a modifié votre paiement : {1} → {2}",
                [NoticeMessage.YourPaymentChanged] = "{0} a modifié votre paiement à {1} : {2} → {3}",
                [NoticeMessage.PaymentToYouDeletedByPayer] = "{0} a supprimé son paiement de {1} pour vous",
                [NoticeMessage.PaymentToYouDeleted] = "{0} a supprimé le paiement de {2} de {1}",
                [NoticeMessage.YourPaymentDeletedByPayee] = "{0} a supprimé votre paiement de {1}",
                [NoticeMessage.YourPaymentDeleted] = "{0} a supprimé votre paiement de {2} à {1}",
                [NoticeMessage.PaymentReminder] = "{0} vous demande le paiement de {1}",
                [NoticeMessage.InviteAccepted] = "{0} a rejoint le groupe avec votre invitation",
                [NoticeMessage.RemovedFromGroup] = "{0} a mis fin à votre participation au groupe",
            }),
    };
}
