---
applyTo: "**"
description: "This file contains the coding standards and guidelines for Copilot."
---

# General Coding Standards

## Comment Header Section
1. Always include a comment section at the top that describes the program.
2. Update the context field to reflect its context from the book.
3. Include my display name (Greg Tate).
4. If a date is present, do not alter it.

## Header Format

Use the following format for the header comment section:

```Example
# -------------------------------------------------------------------------
# Program: DeleteUsersAzCli.ps1
# Description: Delete (and optionally purge) Azure AD users listed in a JSON file
# Context: AZ-104 lab - setup identity baseline (Microsoft Azure Administrator)
# Author: Greg Tate
# ------------------------------------------------------------------------
```


## Commenting Rules
1. You **must** add comments to all code blocks if and only if there is a blank line immediately above it.
	- A “code block” is any of:
		- A group of declarations/initializations separated by a blank line.
		- A single significant assignment separated by a blank line.
		- Each loop (`for`, `while`), `if` / `else if` / `else` body.
	- The comment must describe the intent of the code block.

2. Do not alter program behavior. You may add comments and whitespace only.
