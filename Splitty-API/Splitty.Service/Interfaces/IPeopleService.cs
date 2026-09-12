using Splitty.DTO.Response;

namespace Splitty.Service.Interfaces;

public interface IPeopleService
{
    Task<PeopleResponse> GetPeopleAsync(int userId);
}
