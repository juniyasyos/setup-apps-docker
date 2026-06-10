import sys, os

filepath = os.environ['COMPOSE_YML']
name = os.environ['APP_NAME']
source_dir = os.environ['SOURCE_DIR']
desc = os.environ['APP_DESC']
has_queue = os.environ.get('HAS_QUEUE', 'true') == 'true'
has_scheduler = os.environ.get('HAS_SCHEDULER', 'true') == 'true'

with open(filepath, 'r') as f:
    content = f.read()

volumes_header = "# Named Volumes"
volumes_idx = content.find(volumes_header)
if volumes_idx == -1:
    print("ERROR: Cannot find Named Volumes section", file=sys.stderr)
    sys.exit(1)

svc_block = f"""
  # {desc}
  # Image: juniyasyos/{name}:VERSION
  app-{name}:
    extends:
      file: compose/apps/{name}.yml
      service: app
"""

if has_queue:
    svc_block += f"""
  queue-{name}:
    extends:
      file: compose/apps/{name}.yml
      service: queue
"""

if has_scheduler:
    svc_block += f"""
  scheduler-{name}:
    extends:
      file: compose/apps/{name}.yml
      service: scheduler
"""

insert_pos = content.rfind('\n', 0, volumes_idx - 1)
content = content[:insert_pos] + svc_block + content[insert_pos:]

vol_block = f"""
  # ── {name.upper()} ──────────────────────────────────────────
  {name}_public:
    driver: local
  {name}_storage:
    driver: local
  {name}_bootstrap_cache:
    driver: local
"""

networks_idx = content.find('\nnetworks:')
volumes_section_end = content.rfind('\n\n', 0, networks_idx)
content = content[:volumes_section_end] + vol_block + content[volumes_section_end:]

with open(filepath, 'w') as f:
    f.write(content)
print("OK")
