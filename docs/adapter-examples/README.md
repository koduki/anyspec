# External Adapter Examples

This directory contains example YAML adapter definitions for extending anyspec without recompiling.

## Best Practice

**For production and CI use**: Keep adapter definitions in a version-controlled directory in the same repository as your spec YAML files, and pass `--adapters-dir` or set `ANYSPEC_ADAPTERS_DIR` to load them. This ensures adapter definitions are part of the 「動く設計書」and tracked alongside your expectations.

```bash
# Recommended: version-controlled adapter definitions
anyspec check specs/ --adapters-dir ./adapters

# Or via environment variable
export ANYSPEC_ADAPTERS_DIR=./adapters
anyspec check specs/
```

The home directory (`~/.anyspec/adapters/`) and project-local (`.anyspec/adapters/`) paths are fallbacks for personal experimentation only—they are not the canonical source for team-shared definitions.

## File Format

One file can define multiple adapter types. Prefer a single `adapters.yml` (or similar) over many small files:

```yaml
schema_version: "1.0"

adapters:
  - type: vcn_security_list
    locators:
      - subcommand: network security-list get
        required_fields: [security_list_id]
        flag_mappings:
          security_list_id: --security-list-id
        extract_fields:
          - id
          - display_name
          - lifecycle_state

  - type: network_security_group
    locators:
      - subcommand: network nsg get
        required_fields: [nsg_id]
        flag_mappings:
          nsg_id: --nsg-id
        extract_fields:
          - id
          - display_name
```

## Definition Fields

| Field | Required | Description |
|-------|----------|-------------|
| `schema_version` | Recommended | Adapter schema version (e.g., "1.0") |
| `adapters` | For multi-type | Array of adapter definitions |
| `type` | Yes | Unique adapter type name |
| `locators` | Yes | Array of locator configurations |

### Locator Fields

| Field | Required | Description |
|-------|----------|-------------|
| `subcommand` | Yes | OCI CLI subcommand (space-separated string or array) |
| `required_fields` | Yes | Spec fields that must be present to use this locator |
| `flag_mappings` | No | Map spec fields to CLI flags |
| `static_flags` | No | Always-added flags (array of strings or `{flag: value}`) |
| `extract_fields` | No | Fields to extract from JSON response |
| `list_filter_field` | No | JSON field to match for list filtering |
| `list_filter_spec_field` | No | Spec field to match against list results |

## Overriding Built-in Adapters

External definitions can override built-in adapters. The override is logged at runtime:

```
Loaded external adapters from: ./adapters/adapters.yml
  Note: Built-in 'audit_configuration' overridden by ./adapters/adapters.yml
```

## Scope of External Adapters

External YAML adapters are designed for simple get/list operations with field extraction.

**What you CAN do:**
- Single resource get by ID
- List filtering by name (simple list + filter)
- Flag mappings to build OCI CLI arguments
- Field extraction from JSON response

**What REQUIRES a Ruby adapter (rebuild):**
- Nested matching logic
- Multi-resource operations (e.g., VCN + Subnet)
- Custom JSON processing
- Pagination beyond simple lists
- Non-OCI clouds

## Security

YAML definitions are loaded with `YAML.safe_load`:
- Permitted classes: `Symbol` only (`Date`, `Time` are disallowed)
- Shell injection patterns (`` `...` ``, `$(...)`) are blocked
- Each type is processed by a single `GenericCli` class—no dynamic class generation (`Class.new`, `define_method`) per type
- Empty list results or unmatched filters raise `Anyspec::Error` (no silent fallback to `items.first`)

## Version Information in Reports

Execution reports (JSON/Markdown) include:
- Loaded adapter definition files
- Externally defined types
- Built-in adapter overrides
- Version info (anyspec version, adapter schema version, oci CLI version)
