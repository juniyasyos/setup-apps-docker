  # ── {{APP_UPPER}} ──────────────────────────────────────────
  {{APP_NAME}}_public:
    external: true
    name: {{PUBLIC_VOLUME_NAME}}

  {{APP_NAME}}_storage:
    external: true
    name: {{STORAGE_VOLUME_NAME}}

  {{APP_NAME}}_bootstrap_cache:
    name: {{BOOTSTRAP_CACHE_VOLUME_NAME}}