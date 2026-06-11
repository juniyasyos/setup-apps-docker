  # {{APP_DESC}}
  # Image: {{IMAGE_NAME}}:{{IMAGE_VERSION}}
  app-{{APP_NAME}}:
    extends:
      file: compose/apps/{{APP_NAME}}.yml
      service: app
    networks:
      - default

  queue-{{APP_NAME}}:
    extends:
      file: compose/apps/{{APP_NAME}}.yml
      service: queue
    networks:
      - default

  scheduler-{{APP_NAME}}:
    extends:
      file: compose/apps/{{APP_NAME}}.yml
      service: scheduler
    networks:
      - default