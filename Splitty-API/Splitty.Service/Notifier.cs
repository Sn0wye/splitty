using System.Threading.Channels;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

public sealed class Notifier(ChannelWriter<Notice> queue) : INotifier
{
    public void Notify(IEnumerable<Notice> notices)
    {
        foreach (var notice in notices)
        {
            // Unbounded, so this never fails while the host runs.
            queue.TryWrite(notice);
        }
    }
}
