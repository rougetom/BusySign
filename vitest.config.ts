import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.jsonc" },
        miniflare: {
          bindings: {
            STATUS_SECRET: "test-secret",
            TIMEZONE: "America/New_York",
            WORK_START_HOUR: "8",
            WORK_END_HOUR: "18",
            WORK_DAYS: "1,2,3,4,5",
          },
        },
      },
    },
  },
});
