using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IPushDeviceRepository
{
    /// Registers the token for this sign-in, taking it over from whoever held it, and drops
    /// any other token the same sign-in registered before.
    Task UpsertAsync(PushDevice device);

    /// The user's devices whose sign-in is still live: a revoked or expired family gets nothing.
    Task<List<PushDevice>> GetSignedInAsync(int userId);

    Task DeleteAsync(int id);
}
