using Splitty.Domain.Entities;

namespace Splitty.Repository.Interfaces;

public interface IGroupRepository
{
    Task CreateAsync(Group group);
    Task RenameAsync(int groupId, string? name, string? description, Currency? currency);
    Task DeleteAsync(int groupId);
}