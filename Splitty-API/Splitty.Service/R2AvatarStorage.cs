using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Options;
using Splitty.Service.Interfaces;

namespace Splitty.Service;

/// <summary>
/// R2 through its S3-compatible API. The AWS SDK is here to sign requests — hand-rolling
/// SigV4 reimplements a solved problem.
/// </summary>
public class R2AvatarStorage(IAmazonS3 s3, IOptions<R2Options> r2Options) : IAvatarStorage
{
    private readonly R2Options options = r2Options.Value;

    public string ContentType => "image/jpeg";

    public long MaxBytes => options.MaxAvatarBytes;

    public async Task<PresignedAvatarUpload> CreateUploadAsync(
        int userId,
        CancellationToken cancellationToken = default)
    {
        // A fresh UUID per upload: keys are never reused, so a committed URL is
        // permanently cacheable and there is no invalidation story.
        var key = $"avatars/{userId}/{Guid.NewGuid():N}.jpg";
        var expiresAt = DateTime.UtcNow.Add(options.UploadUrlLifetime);

        var url = await s3.GetPreSignedURLAsync(new GetPreSignedUrlRequest
        {
            BucketName = options.BucketName,
            Key = key,
            Verb = HttpVerb.PUT,
            Expires = expiresAt,
            // Signed, so the URL is not an open upload slot: a PUT declaring anything else
            // fails the signature check at R2.
            ContentType = ContentType
        });

        return new PresignedAvatarUpload(key, url, ContentType, expiresAt);
    }

    public async Task<StoredAvatar?> HeadAsync(string key, CancellationToken cancellationToken = default)
    {
        try
        {
            var metadata = await s3.GetObjectMetadataAsync(options.BucketName, key, cancellationToken);

            return new StoredAvatar(metadata.ContentLength, metadata.Headers.ContentType ?? string.Empty);
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public Task DeleteAsync(string key, CancellationToken cancellationToken = default) =>
        s3.DeleteObjectAsync(options.BucketName, key, cancellationToken);

    /// <summary>
    /// Lists by prefix and deletes each page in one batch. R2 implements both
    /// `ListObjectsV2` and `DeleteObjects`; a page holds at most 1,000 keys, which is also
    /// the batch limit.
    /// </summary>
    public async Task DeleteUserObjectsAsync(int userId, CancellationToken cancellationToken = default)
    {
        var request = new ListObjectsV2Request
        {
            BucketName = options.BucketName,
            Prefix = $"avatars/{userId}/"
        };

        ListObjectsV2Response page;

        do
        {
            page = await s3.ListObjectsV2Async(request, cancellationToken);

            // SDK v4 leaves an empty page's collection null rather than empty.
            var keys = page.S3Objects?.Select(o => new KeyVersion { Key = o.Key }).ToList() ?? [];

            if (keys.Count > 0)
            {
                var result = await s3.DeleteObjectsAsync(new DeleteObjectsRequest
                {
                    BucketName = options.BucketName,
                    Objects = keys
                }, cancellationToken);

                // A batch delete reports per-key failures in the body, not as an exception.
                if (result.DeleteErrors is { Count: > 0 } errors)
                {
                    throw new InvalidOperationException(
                        $"Failed to delete {errors.Count} avatar object(s), first {errors[0].Key}: {errors[0].Message}");
                }
            }

            request.ContinuationToken = page.NextContinuationToken;
        } while (page.IsTruncated == true);
    }

    public string PublicUrl(string key) => $"{options.PublicBaseUrl.TrimEnd('/')}/{key}";

    /// <summary>
    /// R2 has one endpoint for every bucket and no regions, so the region is the literal
    /// `auto` SigV4 expects and addressing must be path style.
    /// </summary>
    public static IAmazonS3 CreateClient(R2Options options) =>
        new AmazonS3Client(options.AccessKeyId, options.SecretAccessKey, new AmazonS3Config
        {
            ServiceURL = $"https://{options.AccountId}.r2.cloudflarestorage.com",
            AuthenticationRegion = "auto",
            ForcePathStyle = true,
            // SDK v4 sends a trailing CRC checksum by default; R2 rejects the request.
            RequestChecksumCalculation = Amazon.Runtime.RequestChecksumCalculation.WHEN_REQUIRED,
            ResponseChecksumValidation = Amazon.Runtime.ResponseChecksumValidation.WHEN_REQUIRED
        });
}
