#!/usr/bin/env python3
import sys
import json
import re

def yaml_to_json(yaml_str):
    """Simple YAML to JSON converter for devfile structure"""
    lines = yaml_str.strip().split('\n')
    result = {}
    current_section = None
    section_content = []

    for line in lines:
        # Skip schema version and metadata
        if line.startswith('schemaVersion:') or line.startswith('metadata:'):
            continue
        if line.startswith('  ') and current_section is None:
            continue

        # Detect main sections
        if re.match(r'^(projects|components|commands|events):', line):
            if current_section and section_content:
                result[current_section] = '\n'.join(section_content)
            current_section = line.split(':')[0]
            section_content = [line]
        elif current_section:
            section_content.append(line)

    if current_section and section_content:
        result[current_section] = '\n'.join(section_content)

    # Build template JSON structure
    template = {
        "attributes": {
            "controller.devfile.io/storage-type": "per-workspace",
            "controller.devfile.io/scc": "container-build"
        }
    }

    # Add non-empty sections
    for key in ['projects', 'components', 'commands', 'events']:
        if key in result:
            # This is a simplified approach - just pass the YAML section as-is
            # The DevWorkspace controller can handle YAML in template
            template[key] = result[key]

    return template

if __name__ == '__main__':
    yaml_content = sys.stdin.read()
    template = yaml_to_json(yaml_content)
    print(json.dumps(template, indent=2))
