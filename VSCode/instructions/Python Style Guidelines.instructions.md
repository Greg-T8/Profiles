---
applyTo: "**/*.py"
description: "This file contains the Python scripting standards and guidelines for Copilot."
---

# Generating a Python Script with Proper Style

Refactor the Python script so that it adheres to the following style guidelines:

## Formatting Python Code for Revision

When providing Python code that is longer than one line, follow these guidelines to ensure proper style and readability:

### Line Breaking Guidelines

1. **Break long one-liners across multiple lines** to improve readability
2. **Use parentheses for implicit line continuation** - Python allows line breaks inside parentheses, brackets, and braces
3. **Use backslash (`\`) for line continuation** only when parentheses are not available
4. **Indent continuation lines** to show logical grouping and hierarchy (typically 4 spaces)
5. **Follow PEP 8 naming conventions** - snake_case for functions and variables, PascalCase for classes
6. **Keep line length under 88 characters** (Black formatter standard) or 79 characters (PEP 8 strict)

### Formatting Examples

#### Example 1: Function Call with Multiple Arguments

**Before:**
```python
result = some_function(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
```

**After:**
```python
result = some_function(
    arg1,
    arg2,
    arg3,
    arg4,
    arg5,
    arg6,
    arg7,
    arg8
)
```

#### Example 2: Dictionary Definition

**Before:**
```python
config = {'location': 'eastus', 'vm_size': 'Standard_D2s_v3', 'admin_username': 'azureuser', 'enable_monitoring': True}
```

**After:**
```python
config = {
    'location': 'eastus',
    'vm_size': 'Standard_D2s_v3',
    'admin_username': 'azureuser',
    'enable_monitoring': True
}
```

#### Example 3: Method Chaining

**Before:**
```python
df = pd.read_csv('data.csv').dropna().groupby('category').agg({'value': 'sum'}).reset_index()
```

**After:**
```python
df = (
    pd.read_csv('data.csv')
    .dropna()
    .groupby('category')
    .agg({'value': 'sum'})
    .reset_index()
)
```

#### Example 4: List Comprehension

**Before:**
```python
results = [process_item(item, param1=value1, param2=value2, param3=value3) for item in items if item.is_valid()]
```

**After:**
```python
results = [
    process_item(
        item,
        param1=value1,
        param2=value2,
        param3=value3
    )
    for item in items
    if item.is_valid()
]
```

### Key Improvements to Apply

- **Use snake_case for function and variable names**: `get_data()`, `user_name`
- **Use PascalCase for class names**: `DataProcessor`, `UserAccount`
- **Use UPPER_CASE for constants**: `MAX_RETRIES`, `DEFAULT_TIMEOUT`
- **Align dictionary keys and values** for visual clarity
- **Use meaningful indentation** (4 spaces per level)
- **Place opening parentheses/brackets on the same line** and closing ones aligned with the opening construct
- **Use trailing commas** in multi-line collections for cleaner diffs



## General Program Structure

```python
def main() -> None:
    """
    Main function that includes a small number of high-level commands.

    Each command should be a call to a function defined elsewhere in the script.
    Intention is for the reader to quickly understand what the script does in this block.
    """
    data = get_data()
    processed = process_data(data)
    save_results(processed)


# Helper Functions
# -------------------------------------------------------------------------

def get_data() -> dict:
    """
    Retrieve data from a source.

    Returns:
        dict: Retrieved data
    """
    # Implementation details go here
    pass


def process_data(data: dict) -> dict:
    """
    Process the retrieved data.

    Args:
        data: Input data to process

    Returns:
        dict: Processed data
    """
    # Implementation details go here
    pass


def save_results(results: dict) -> None:
    """
    Save the processed results to a destination.

    Args:
        results: Processed results to save
    """
    # Implementation details go here
    pass


# -------------------------------------------------------------------------
# Script Entry Point
# -------------------------------------------------------------------------

if __name__ == "__main__":
    main()
```

### Notes on general structure

* The `main()` function always comes first before the helper functions.
* Helper functions are defined after the main function.
* The script execution happens at the bottom using `if __name__ == "__main__":`.
* Each function should have a docstring describing its purpose, parameters, and return values.
* Use type hints for function parameters and return types where applicable.

## Other requirements

* Use descriptive function names with clear verb-noun structure (e.g., `get_data`, `process_file`, `validate_input`).
* Keep function names in snake_case with the noun part singular (e.g., use `get_item` instead of `get_items`).
	* Common verb mappings:
		* retrieve/fetch → `get_`
		* validate/check → `validate_` or `check_`
		* display/output → `show_` or `display_`
		* create/build → `create_` or `build_`
		* update/modify → `update_` or `modify_`
		* delete/remove → `delete_` or `remove_`
* When displaying output, use the verb `show` or `display` instead of `format`.
* Prefer explicit imports over wildcard imports (`from module import *` is discouraged).
* Group imports in the following order:
  1. Standard library imports
  2. Third-party imports
  3. Local application imports
* Add blank lines to separate these import groups.
