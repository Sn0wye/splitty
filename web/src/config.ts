/**
 * Facts the legal pages and the footer state. One place, so a change here reaches all four
 * languages at once.
 */
export const operator = {
  name: "Gabriel Trzimajewski",
  country: "Brazil",
};

// TODO: replace with real mailboxes once the domain exists.
export const contact = {
  privacy: "privacy@splitty.app",
  support: "support@splitty.app",
};

/** Date the privacy policy and terms last changed. Bump both texts together. */
export const legalUpdated = "2026-10-16";

export const minimumAge = 13;

/** How long server logs are kept before deletion. Must match the Seq retention policy. */
export const logRetentionDays = 30;

/** Days a refresh token lives without use. Mirrors `Jwt:RefreshTokenDays` in the API. */
export const refreshTokenDays = 90;
