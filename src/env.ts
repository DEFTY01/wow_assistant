export interface Env {
  DB: D1Database;
  REGION: string;
  GAME_NAMESPACE_SUFFIX: string;
  CHARACTER_SLUG: string;
  LOCALE: string;
  RULESET_ID: string;
  AUCTION_HOUSE_ID: string;
  BLIZZARD_CLIENT_ID: string;
  BLIZZARD_CLIENT_SECRET: string;
  /** Optional: when set, the addon uploader must send it as a Bearer token. */
  UPLOAD_TOKEN?: string;
  /** Cloudflare Access team domain, e.g. "myteam.cloudflareaccess.com", and the application AUD tag. */
  ACCESS_TEAM_DOMAIN?: string;
  ACCESS_AUD?: string;
  /** Set to "1" only by the local dev script; never present in production. */
  LOCAL_DEV?: string;
}
