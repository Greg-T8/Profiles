---
applyTo: "**/*.sh"
description: "This file contains the shell scripting standards and guidelines for Copilot."
---

# Generating Shell Scripts with Proper Style (Linux/POSIX)

Refactor the shell script so that it adheres to the following style guidelines:

## Formatting Shell Commands for Revision

When providing a shell command that is longer than one line, follow these guidelines to ensure proper style and readability:

### Line Breaking Guidelines

1. **Break long one-liners across multiple lines** to improve readability
2. **Prioritize using the pipe (`|`) for line breaks** - place each pipe segment on its own line
3. **Use the backslash (`\`) character for line continuation** when breaking lines that don't naturally break at a pipe
4. **Indent continuation lines** to show logical grouping and hierarchy (typically 4 spaces or 1 tab)
5. **Place operators at the end of lines** when breaking (e.g., `\`, `|`, `&&`, `||`)
6. **Keep related options together** when breaking command arguments

### Formatting Examples

#### Example 1: Long Command with Pipes

**Before:**
```bash
ps aux | grep -v grep | grep python | awk '{print $2, $11}' | sort -k2
```

**After:**
```bash
ps aux |
    grep -v grep |
    grep python |
    awk '{print $2, $11}' |
    sort -k2
```

#### Example 2: Command with Many Arguments

**Before:**
```bash
docker run -d --name myapp -p 8080:8080 -e NODE_ENV=production -e DB_HOST=localhost -e DB_PORT=5432 -v /data:/app/data --restart unless-stopped myapp:latest
```

**After:**
```bash
docker run -d \
    --name myapp \
    -p 8080:8080 \
    -e NODE_ENV=production \
    -e DB_HOST=localhost \
    -e DB_PORT=5432 \
    -v /data:/app/data \
    --restart unless-stopped \
    myapp:latest
```

#### Example 3: Complex Find Command

**Before:**
```bash
find /var/log -type f -name "*.log" -mtime +30 -exec gzip {} \; -exec mv {}.gz /archive/ \;
```

**After:**
```bash
find /var/log \
    -type f \
    -name "*.log" \
    -mtime +30 \
    -exec gzip {} \; \
    -exec mv {}.gz /archive/ \;
```

#### Example 4: Multiline String with Here-Document

**Before:**
```bash
cat > config.yaml << EOF
server:
  host: localhost
  port: 8080
database:
  host: db.example.com
  port: 5432
EOF
```

**After (when inline):**
```bash
cat > config.yaml << 'EOF'
server:
  host: localhost
  port: 8080
database:
  host: db.example.com
  port: 5432
EOF
```

#### Example 5: Conditional Logic

**Before:**
```bash
if [ -f /etc/config ]; then source /etc/config && validate_config && start_service || exit 1; fi
```

**After:**
```bash
if [ -f /etc/config ]; then
    source /etc/config && \
        validate_config && \
        start_service || exit 1
fi
```

#### Example 6: Git Command with Multiple Options

**Before:**
```bash
git log --pretty=format:"%h %ad | %s%d [%an]" --graph --date=short --since="2 weeks ago" --author="John" --no-merges
```

**After:**
```bash
git log \
    --pretty=format:"%h %ad | %s%d [%an]" \
    --graph \
    --date=short \
    --since="2 weeks ago" \
    --author="John" \
    --no-merges
```

### Key Improvements to Apply

- **Group related options together:**
  - Keep short flags grouped when appropriate: `-rf` instead of `-r \n -f`
  - Separate long options: `--verbose --dry-run`

- **Use consistent indentation** (4 spaces recommended)

- **Align similar elements** for visual clarity when beneficial:
  ```bash
  -e VAR1=value1 \
  -e VAR2=value2 \
  -e VAR3=value3
  ```

- **Keep logical operators visible:**
  - Place `&&`, `||`, `|` at the end of lines before the backslash
  - Example: `command1 && \`

- **Use here-documents for multi-line strings** instead of multiple echo commands

- **Quote variables** to prevent word splitting: `"$variable"` instead of `$variable`

## General Program Structure

```bash
#!/usr/bin/env bash

# -------------------------------------------------------------------------
# Program: script-name.sh
# Description: Brief description of what the script does
# Context: Context information (e.g., project, course, etc.)
# Author: Greg Tate
# -------------------------------------------------------------------------

set -euo pipefail  # Exit on error, undefined variable, pipe failure

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Main function
main() {
    # Main logic that includes a small number of high-level function calls
    # Intention is for the reader to quickly understand what the script does

    get_data
    process_data
    save_results
}

# Helper functions
get_data() {
    # Function to retrieve data from a source
    # Implementation details go here
    :
}

process_data() {
    # Function to process the retrieved data
    # Implementation details go here
    :
}

save_results() {
    # Function to save the processed results
    # Implementation details go here
    :
}

# Entry point
main "$@"
```

### Notes on General Structure

* The `main()` function should be defined early (place it near the top) and called at the end
* Use `set -euo pipefail` for safer script execution
* Define constants with `readonly` at the top
* Use lowercase with underscores for function names (following POSIX convention)
* The `"$@"` passes all script arguments to the main function
* Use `:` (null command) as a placeholder in empty functions

## Other Requirements

* **Use descriptive function names** with verbs (e.g., `get_`, `process_`, `validate_`, `check_`)
* **Keep function names in lowercase** with underscores separating words
* **Use meaningful variable names** - avoid single letters except for loop counters
* **Quote all variables** unless you specifically need word splitting
* **Check command success** before proceeding: `command || handle_error`
* **Provide usage/help** for scripts that accept arguments
* **Use `local` keyword** for variables inside functions
* **Prefer `[[ ]]` over `[ ]`** for conditional tests in bash (more features, safer)
* **Use `$()` instead of backticks** for command substitution

### Common Verb Mapping

* Check/Validate → `check_` or `validate_`
* Display/Print → `show_` or `print_`
* Create/Make → `create_` or `make_`
* Delete/Remove → `remove_` or `delete_`
* Update/Modify → `update_` or `modify_`

````
