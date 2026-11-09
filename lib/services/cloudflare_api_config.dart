class CloudflareApiConfig {
  static const baseUrl = String.fromEnvironment(
    'SMARTVAULT_API_BASE_URL',
    defaultValue: 'https://cloudflare-backend.smartvaultpro.workers.dev',
  );
}
