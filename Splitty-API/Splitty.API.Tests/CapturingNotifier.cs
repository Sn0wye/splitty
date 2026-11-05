using System.Collections.Concurrent;
using System.Threading.Channels;
using Splitty.Service;
using Splitty.Service.Interfaces;

namespace Splitty.API.Tests;

/// <summary>
/// Records every notice a write hands over, then queues it as the real notifier does. A write
/// decides its notices before it answers, so a test reads them right after the request,
/// with no worker to wait for.
/// </summary>
public sealed class CapturingNotifier(ChannelWriter<Notice> queue) : INotifier
{
    private readonly Notifier _inner = new(queue);
    private readonly ConcurrentQueue<Notice> _notices = new();

    public void Notify(IEnumerable<Notice> notices)
    {
        var list = notices.ToList();

        foreach (var notice in list)
        {
            _notices.Enqueue(notice);
        }

        _inner.Notify(list);
    }

    public List<Notice> InGroup(int groupId) => _notices.Where(n => n.GroupId == groupId).ToList();

    public List<Notice> For(int recipientId) => _notices.Where(n => n.RecipientId == recipientId).ToList();
}
