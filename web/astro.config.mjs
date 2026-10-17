// @ts-check
import { defineConfig } from "astro/config";

// https://astro.build/config
export default defineConfig({
  // TODO: set to the production origin once the domain exists; it turns on canonical and
  // hreflang links.
  site: process.env.SITE_URL,
  devToolbar: { enabled: false },
});
