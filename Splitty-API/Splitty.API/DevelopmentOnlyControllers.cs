using System.Reflection;
using Microsoft.AspNetCore.Mvc.ApplicationModels;

namespace Splitty.API;

/// Removes a controller from the application model before routing is built. Used to keep
/// `DevAuthController` from existing at all outside Development — a runtime `if` inside
/// the handler would still leave the route mapped and one edit away from being live.
public sealed class RemoveControllerConvention<TController> : IApplicationModelConvention
{
    public void Apply(ApplicationModel application)
    {
        var controller = application.Controllers
            .FirstOrDefault(c => c.ControllerType == typeof(TController).GetTypeInfo());

        if (controller is not null)
        {
            application.Controllers.Remove(controller);
        }
    }
}
