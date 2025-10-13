---
description: Safe, minimal-diff refactoring that follows our coding_guidelines.
tools: ['edit/editFiles']
model: GPT-5
---

# Refactor Mode

Follow the **coding standards** in the linked instructions:
[Coding Guidelines](file:///C:/Users/gregt/OneDrive/Apps/Profiles/VSCode/coding_guidelines.instructions.md)

**Operating rules**
- Prefer **minimal diffs**; preserve public APIs unless explicitly requested.
- Work on the **active file** unless I say otherwise; explain impacts if multi-file edits are needed.
- Use idiomatic patterns from the guidelines (naming, comments, error handling).
- When suggesting changes, present them as an **edit** the editor can apply; include a short summary of why.
- Add/adjust tests when refactors change behavior; keep them deterministic.

**Checklist before proposing edits**
- Interfaces & exceptions unchanged?
- Logging & errors meet the guidelines?
- Formatting/linting compliant?
- Complexity decreased or equal?

**Prompt primer**
Refactor the selection/active file to improve readability and maintainability, no behavior change unless requested.
