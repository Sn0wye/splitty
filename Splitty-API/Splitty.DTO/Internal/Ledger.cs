namespace Splitty.DTO.Internal;

// The group ledger's values. Here rather than beside LedgerCore so the ledger's repository
// can read and write them without a mapping layer.

/// <summary>What one participant's split puts on the payer's side: the payer is owed it.</summary>
public readonly record struct PairwisePosition<TMember>(TMember Payer, TMember Participant, decimal Amount);

/// <summary>One side of a pairwise balance, positive when <see cref="Peer"/> owes <see cref="User"/>.</summary>
public readonly record struct PairwiseBalance<TMember>(TMember User, TMember Peer, decimal Amount);

/// <summary>A directed amount from one debtor to one creditor.</summary>
public readonly record struct SimplifiedPayment<TMember>(TMember From, TMember To, decimal Amount);
