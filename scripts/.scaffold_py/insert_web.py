import sys, os

filepath = os.environ['WEB_YML']
name = os.environ['APP_NAME']
source_dir = os.environ['SOURCE_DIR']
port = os.environ['APP_PORT']
name_upper = name.upper()
host_port_var = f"{name_upper}_HOST_PORT"

with open(filepath, 'r') as f:
    content = f.read()

# Insert port entry into x-web-ports
ports_marker = "x-web-ports:"
ports_start = content.find(ports_marker)
if ports_start == -1:
    print("ERROR: Cannot find x-web-ports in web.yml", file=sys.stderr)
    sys.exit(1)

ports_end = content.find("\n\nx-", ports_start + 1)
if ports_end == -1:
    ports_end = content.find("\nservices:", ports_start + 1)

last_port_line = content.rfind('\n  - "', ports_start, ports_end)
if last_port_line == -1:
    last_port_line = ports_end

new_port = f'  - "${{{host_port_var}:-{port}}}:{port}"\n'
content = content[:last_port_line] + '\n' + new_port + content[last_port_line + 1:]

# Insert volume entries into x-web-volumes
volumes_marker = "x-web-volumes:"
volumes_start = content.find(volumes_marker)
if volumes_start == -1:
    print("ERROR: Cannot find x-web-volumes", file=sys.stderr)
    sys.exit(1)

volumes_end = content.find("\n\nservices:", volumes_start + 1)

last_vol_line = content.rfind('\n  - ', volumes_start, volumes_end)
if last_vol_line == -1:
    last_vol_line = volumes_end

new_vols = f"  - {name}_public:/var/www/{source_dir}/public:ro\n  - {name}_storage:/var/www/{source_dir}/storage:ro\n"
content = content[:last_vol_line] + '\n' + new_vols + content[last_vol_line + 1:]

with open(filepath, 'w') as f:
    f.write(content)
print("OK")
