using Splitty.Domain.Entities;
using Splitty.Service;

namespace Splitty.API.Tests;

/// The words a push notification shows, in each app language and currency.
public sealed class PushCopyTests
{
    private static readonly Dictionary<int, string> Names = new() { [1] = "Ana", [2] = "Bruno" };

    private static string Body(Notice notice, string language = "pt-BR", Currency currency = Currency.BRL) =>
        PushCopy.Render(notice, language, "Viagem", currency, Names).Body;

    [Theory]
    [InlineData(Currency.BRL, "R$ 1.234,50")]
    [InlineData(Currency.EUR, "1.234,50 €")]
    [InlineData(Currency.USD, "$1,234.50")]
    [InlineData(Currency.CHF, "CHF 1'234.50")]
    [InlineData(Currency.CAD, "CA$1,234.50")]
    public void Amounts_are_written_the_way_their_currency_writes_them(Currency currency, string expected) =>
        Assert.Equal(expected, PushCopy.Format(1234.5m, currency));

    [Fact]
    public void The_title_is_the_group_and_the_body_says_who_did_what_and_your_share()
    {
        var notice = new Notice(9, NoticeMessage.ExpenseAdded, 5, 1) { Description = "Jantar", Amount = 42m };

        var (title, body) = PushCopy.Render(notice, "pt-BR", "Viagem", Currency.BRL, Names);

        Assert.Equal("Viagem", title);
        Assert.Equal("Ana adicionou Jantar. Sua parte: R$ 42,00", body);
    }

    [Fact]
    public void A_change_shows_the_amount_before_and_after() =>
        Assert.Equal("Ana mudou Jantar. Sua parte: R$ 42,00 → R$ 50,00",
            Body(new Notice(9, NoticeMessage.ExpenseShareChanged, 5, 1)
            {
                Description = "Jantar", Before = 42m, Amount = 50m
            }));

    [Fact]
    public void A_recurring_expense_says_how_often_it_repeats() =>
        Assert.Equal("Ana added Rent, every month. Your share: $800.00",
            Body(new Notice(9, NoticeMessage.RecurringExpenseAdded, 5, 1)
            {
                Description = "Rent", Amount = 800m, Frequency = RepeatFrequency.Monthly
            }, "en", Currency.USD));

    [Fact]
    public void A_payment_names_the_other_person_when_the_actor_is_someone_else() =>
        Assert.Equal("Ana apagou o pagamento de R$ 50,00 de Bruno",
            Body(new Notice(9, NoticeMessage.PaymentToYouDeleted, 5, 1) { PeerId = 2, Amount = 50m }));

    [Fact]
    public void A_deleted_user_is_named_removed_member_in_the_reader_s_language()
    {
        var names = new Dictionary<int, string> { [1] = User.TombstoneName };
        var notice = new Notice(9, NoticeMessage.PaymentReminder, 5, 1) { Amount = 10m };

        Assert.Equal("Membro removido pediu o pagamento de R$ 10,00",
            PushCopy.Render(notice, "pt-BR", "Viagem", Currency.BRL, names).Body);
    }

    [Fact]
    public void Long_names_and_descriptions_are_cut_so_the_sentence_fits()
    {
        var names = new Dictionary<int, string> { [1] = "Maximiliano Bartolomeu de Albuquerque" };
        var notice = new Notice(9, NoticeMessage.ExpenseDeleted, 5, 1)
        {
            Description = "Jantar de aniversário no restaurante italiano", Amount = 1m
        };

        Assert.Equal("Maximiliano Bartolo… apagou Jantar de aniversário no rest…. Sua parte era R$ 1,00",
            PushCopy.Render(notice, "pt-BR", "Viagem", Currency.BRL, names).Body);
    }

    [Fact]
    public void An_unknown_language_falls_back_to_english() =>
        Assert.Equal("Ana paid you $5.00",
            Body(new Notice(9, NoticeMessage.PaymentReceived, 5, 1) { Amount = 5m }, "de", Currency.USD));

    /// Every message renders in every language, so a new message cannot ship half translated.
    [Fact]
    public void Every_message_renders_in_every_language()
    {
        foreach (var language in PushCopy.Languages)
        {
            foreach (var message in Enum.GetValues<NoticeMessage>())
            {
                var notice = new Notice(9, message, 5, 1)
                {
                    Description = "Jantar", Amount = 1m, Before = 2m, PeerId = 2, Frequency = RepeatFrequency.Weekly
                };

                var body = PushCopy.Render(notice, language, "Viagem", Currency.EUR, Names).Body;

                Assert.StartsWith("Ana", body);
                Assert.DoesNotContain("{", body);
                _ = notice.Kind;
            }
        }

        Assert.Equal(["en", "pt-BR", "es", "fr"], PushCopy.Languages);
    }
}
