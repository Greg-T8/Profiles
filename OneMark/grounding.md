Paste the following into Codex as project/conversation context:

````markdown
# OneMark Theme Customization — Project Handoff

## Objective

I am customizing the themes used by **OneMark**, a OneNote add-in that renders Markdown and uses **Highlight.js** for syntax highlighting.

I have now placed my OneMark theme files into this Git repository so they can be source controlled. Please inspect the actual files in the repository before making changes rather than relying only on the snippets below.

I want to continue refining the theme with these primary goals:

1. Make rendered Markdown visually native to OneNote.
2. Use **Calibri** for normal Markdown text.
3. Use **Cascadia Mono** for code.
4. Use a **Tomorrow Night Blue-style code background**:
   - `#002451`
5. Use approximately the same neutral gray foreground I use in my terminal:
   - `#AAAAAA`
6. Avoid colorful syntax highlighting for terminal captures.
7. Work around Highlight.js incorrectly interpreting mixed PowerShell + JSON output.
8. Keep the implementation simple and maintainable in Git.

---

# Environment

Application:

- Microsoft OneNote desktop
- OneMark add-in
- OneMark themes stored under the user's roaming OneMark theme directory
- I have copied/added the relevant theme files to this Git repository for source control.

OneMark uses Highlight.js for code highlighting, but it does **not necessarily behave like a normal browser CSS renderer**. OneMark appears to parse/translate CSS into formatting OneNote can represent.

That distinction is important when changing CSS.

---

# Normal Text Font

OneMark initially rendered normal Markdown using:

```text
Microsoft YaHei
````

I first changed this in `settings.config`:

```xml
<Font>Calibri</Font>
```

Example:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <userSettings>
    <Roaming>
      <Neux.OneMark.Properties.Settings>
        <LiveMode>False</LiveMode>
        <PageWidth>540</PageWidth>
        <AutoLiveModeSwitch>False</AutoLiveModeSwitch>
        <Font>Calibri</Font>
        <Dev>False</Dev>
      </Neux.OneMark.Properties.Settings>
    </Roaming>
    <PC_GT-100821>
      <Neux.OneMark.Properties.Settings>
        <Theme>C:\Users\gregt\AppData\Roaming\OneMark\themes\custom.css?134139284287358509</Theme>
      </Neux.OneMark.Properties.Settings>
    </PC_GT-100821>
  </userSettings>
</configuration>
```

However, after OneMark rerendered the Markdown with F5, it changed back to Microsoft YaHei.

The effective solution was to override the OneMark CSS variable in `__global.css`:

```css
:root {
    --font-family: 'Calibri';
}
```

This is therefore the setting that matters for rendered Markdown.

---

# Code Font

I want code to use:

```text
Cascadia Mono
```

This is currently controlled in `__global.css` using:

```css
:root {
    --font-family: 'Calibri';
    --monospace: "Cascadia Mono";
}
```

This appears to be the correct OneMark mechanism for selecting the monospace/code font.

---

# Original Highlight.js Theme

I started from the Highlight.js theme:

```text
tomorrow-night-blue.css
```

from the Highlight.js repository:

```text
highlight.js/src/styles/tomorrow-night-blue.css
```

The original theme contained rules similar to:

```css
/* Tomorrow Comment */
.hljs-comment,
.hljs-quote {
  color: #7285b7;
}

/* Tomorrow Red */
.hljs-variable,
.hljs-template-variable,
.hljs-tag,
.hljs-name,
.hljs-selector-id,
.hljs-selector-class,
.hljs-regexp,
.hljs-deletion {
  color: #ff9da4;
}

/* Tomorrow Orange */
.hljs-number,
.hljs-built_in,
.hljs-literal,
.hljs-type,
.hljs-params,
.hljs-meta,
.hljs-link {
  color: #ffc58f;
}

/* Tomorrow Yellow */
.hljs-attribute {
  color: #ffeead;
}

/* Tomorrow Green */
.hljs-string,
.hljs-symbol,
.hljs-bullet,
.hljs-addition {
  color: #d1f1a9;
}

/* Tomorrow Blue */
.hljs-title,
.hljs-section {
  color: #bbdaff;
}

/* Tomorrow Purple */
.hljs-keyword,
.hljs-selector-tag {
  color: #ebbbff;
}

.hljs {
  background: #002451;
  color: white;
}

.hljs-emphasis {
  font-style: italic;
}

.hljs-strong {
  font-weight: bold;
}
```

I like the background very much:

```css
background: #002451;
```

The syntax colors are the part I want to eliminate.

---

# The Main Highlight.js Problem

My common use case is pasting terminal sessions into OneMark.

A typical block looks like this:

```text
╭─( [az:bart] ~
╰╴> az vmware authorization show -g rg-dr-avs-wus2 --private-cloud avs-dr-wus2 --name auth-vwan-hub-wus2
{
  "expressRouteAuthorizationId": "/subscriptions/...",
  "expressRouteAuthorizationKey": "6734292f-78e1-466f-8e3b-7512021175f7",
  "expressRouteId": "/subscriptions/...",
  "id": "/subscriptions/...",
  "name": "auth-vwan-hub-wus2",
  "provisioningState": "Succeeded",
  "resourceGroup": "rg-dr-avs-wus2",
  "type": "Microsoft.AVS/privateClouds/authorizations"
}
```

This is effectively:

```text
PowerShell terminal prompt
        +
Azure CLI command
        +
JSON output
```

The overall code block is being interpreted/highlighted as PowerShell.

Highlight.js therefore does not understand that the lower portion is JSON.

---

# Confirmed Highlight.js Classification Behavior

Initially I noticed something odd:

```text
"expressRouteAuthorizationId"
```

was white, while most other JSON property names and values were green/yellow depending on the theme.

We tested Highlight.js token classification by changing:

```css
.hljs-string {
    color: #ff0000;
}
```

After reloading OneMark and rerendering the block, almost the entire JSON body became red.

That confirmed that Highlight.js was treating BOTH:

```text
"resourceGroup"
```

and:

```text
"rg-dr-avs-wus2"
```

as:

```text
.hljs-string
```

because the containing block is being parsed as PowerShell.

For example:

```json
"resourceGroup": "rg-dr-avs-wus2"
```

does not effectively become:

```text
property -> .hljs-attr
value    -> .hljs-string
```

as it would under the JSON grammar.

Instead, PowerShell parsing causes much of it to become something equivalent to:

```text
property -> .hljs-string
value    -> .hljs-string
```

There was also an interesting exception:

```text
"expressRouteAuthorizationId"
```

remained white during the `.hljs-string { color: red; }` test.

That appears to be a Highlight.js parser boundary/grammar quirk at the transition from the PowerShell command into its JSON output.

Do not spend significant effort trying to make JSON property names and JSON values different colors while the whole block is parsed as PowerShell. That is not my objective anymore.

---

# Current Strategy: Monocolor Code

Rather than trying to correct Highlight.js classification, I want to make all syntax tokens the same foreground color.

My target is approximately:

```text
#AAAAAA
```

This is based on the neutral gray foreground used in my terminal.

The visual goal is roughly:

```text
background: #002451
foreground: #AAAAAA
font: Cascadia Mono
```

with Highlight.js syntax classifications having no visible effect on text color.

---

# Important OneMark CSS Limitation Discovered

We attempted a normal CSS universal-descendant override:

```css
.hljs {
    background: #002451;
    color: #AAAAAA;
}

.hljs * {
    color: #AAAAAA;
}
```

In a normal HTML/browser environment this would generally force descendant Highlight.js spans to inherit/use the same foreground color.

In OneMark, this **did not produce the expected monocolor result**.

Therefore:

> Do not assume that arbitrary CSS selectors, the complete CSS cascade, or universal selectors behave normally in OneMark.

OneMark appears to interpret CSS and translate it into OneNote formatting, so only some selectors/properties may work.

This is one of the next things I want you to investigate from the actual theme files and, if useful, OneMark implementation/documentation.

---

# `!important` Is Not Supported Correctly

We also tested:

```css
.hljs-string {
    color: red !important;
}
```

OneMark produced this error:

```text
[error] load theme error
Error: Unable to parse color from string: rgb(255, 0, 0) !important
```

This tells us two useful things:

1. OneMark definitely loaded and parsed the modified stylesheet.
2. OneMark's color parser cannot handle `!important` appended to the color.

Therefore:

```css
!important
```

should NOT be used for these theme color rules.

---

# OneMark Theme Reload Workflow

When testing CSS changes, I have generally been doing:

1. Save the CSS file.
2. Reload themes in OneMark.
3. Reselect the custom theme when necessary.
4. Press F5 in the OneMark-rendered page to rerender/re-highlight it.

A complete OneNote restart has also been used when necessary.

Keep this workflow in mind when proposing experiments.

---

# Last Proposed Monocolor Approach

Because:

```css
.hljs *
```

did not work as expected, the next proposed approach was to explicitly list Highlight.js token classes.

Something like:

```css
.hljs,
.hljs-subst,
.hljs-comment,
.hljs-quote,
.hljs-keyword,
.hljs-built_in,
.hljs-type,
.hljs-literal,
.hljs-number,
.hljs-operator,
.hljs-punctuation,
.hljs-property,
.hljs-regexp,
.hljs-string,
.hljs-symbol,
.hljs-variable,
.hljs-title,
.hljs-params,
.hljs-doctag,
.hljs-meta,
.hljs-section,
.hljs-tag,
.hljs-name,
.hljs-attr,
.hljs-attribute,
.hljs-bullet,
.hljs-code,
.hljs-emphasis,
.hljs-strong,
.hljs-formula,
.hljs-link,
.hljs-selector-tag,
.hljs-selector-id,
.hljs-selector-class,
.hljs-selector-attr,
.hljs-selector-pseudo,
.hljs-template-tag,
.hljs-template-variable,
.hljs-addition,
.hljs-deletion {
    color: #AAAAAA;
}

.hljs {
    background: #002451;
}
```

Potentially also:

```css
.hljs-emphasis,
.hljs-strong {
    font-style: normal;
    font-weight: normal;
}
```

if I want completely uniform terminal rendering.

**This explicit-selector approach has not yet been fully validated.**

Do not simply assume this is the final answer. Inspect the repository and determine the smallest correct implementation for OneMark.

---

# Current Desired Base Configuration

Conceptually, I want the global theme configuration to contain:

```css
:root {
    --font-family: 'Calibri';
    --monospace: "Cascadia Mono";
}
```

And the code highlighting to achieve:

```text
Background     #002451
Foreground     #AAAAAA
Font           Cascadia Mono
Syntax colors  disabled / visually monocolor
```

Normal Markdown should remain:

```text
Calibri
```

---

# Separation Between `__global.css` and Theme CSS

One open question is where the Highlight.js customization should live.

I currently understand the likely model to be:

### `__global.css`

Good candidate for user-wide preferences such as:

```css
:root {
    --font-family: 'Calibri';
    --monospace: "Cascadia Mono";
}
```

### `custom.css`

Potentially the better location for theme-specific Highlight.js/code styling.

However, please inspect how my actual theme files are structured before deciding.

Avoid duplicating identical rules across `__global.css` and `custom.css` unless there is a clear reason.

---

# What I Want You to Do Next

Please start by inspecting the OneMark theme files in this repository.

Then:

1. Identify which file currently controls:

   * body/Markdown font
   * monospace font
   * code-block background
   * Highlight.js token colors

2. Find any existing `.hljs*` rules that could conflict with the monocolor override.

3. Determine whether the theme itself imports/includes another stylesheet that may override our settings.

4. Simplify the Highlight.js customization as much as possible.

5. Determine the best OneMark-compatible way to make **all Highlight.js syntax tokens `#AAAAAA`**.

6. Preserve:

   ```css
   background: #002451;
   ```

7. Preserve:

   ```text
   Cascadia Mono
   ```

   for code.

8. Preserve:

   ```text
   Calibri
   ```

   for normal Markdown.

9. Do not use:

   ```css
   !important
   ```

   because OneMark's parser errors on it.

10. Be conservative with CSS features. OneMark does not appear to support full browser CSS behavior.

11. Prefer incremental changes that I can test easily with F5.

12. Explain each change before or alongside modifying the file so I understand why it is necessary.

---

# Useful Test Case

Use this as the representative test content:

```text
╭─( [az:bart] ~
╰╴> az vmware authorization show -g rg-dr-avs-wus2 --private-cloud avs-dr-wus2 --name auth-vwan-hub-wus2
{
  "expressRouteAuthorizationId": "/subscriptions/0fb9cca8-1dc8-4fab-8710-4be82c3b2d97/resourceGroups/tnt13-cust-p03-westus2/providers/Microsoft.Network/expressRouteCircuits/tnt13-cust-p03-westus2-er/authorizations/avs_resource_auth-vwan-hub-wus2",
  "expressRouteAuthorizationKey": "6734292f-78e1-466f-8e3b-7512021175f7",
  "expressRouteId": "/subscriptions/0fb9cca8-1dc8-4fab-8710-4be82c3b2d97/resourceGroups/tnt13-cust-p03-westus2/providers/Microsoft.Network/expressRouteCircuits/tnt13-cust-p03-westus2-er",
  "id": "/subscriptions/4de94e63-a484-4c7a-8e6c-603824354b77/resourceGroups/rg-dr-avs-wus2/providers/Microsoft.AVS/privateClouds/avs-dr-wus2/authorizations/auth-vwan-hub-wus2",
  "name": "auth-vwan-hub-wus2",
  "provisioningState": "Succeeded",
  "resourceGroup": "rg-dr-avs-wus2",
  "type": "Microsoft.AVS/privateClouds/authorizations"
}
```

The desired visual result is:

* terminal-style blue background
* all ordinary command/output text the same neutral gray
* no JSON property/value color inconsistencies
* no differences caused by Highlight.js incorrectly treating JSON as PowerShell strings
* Cascadia Mono throughout the code block

The PowerShell prompt itself may contain special formatting generated before Highlight.js/OneMark processing. Do not assume every character in the prompt is controlled by Highlight.js without verifying it.

---

# Development Preference

These files are now source controlled.

Please:

* make focused changes
* show diffs
* avoid unnecessary rewrites
* preserve comments when useful
* remove obsolete experimental CSS once we establish the correct solution
* keep the resulting theme easy to understand
* treat the Git repository as the source of truth

Before changing anything, inspect what is actually in the repo and tell me what you find.

```

The most important state for Codex is that the `.hljs-string` experiment **proved the inconsistent JSON appearance originates in Highlight.js's PowerShell classification**, while the `.hljs *` experiment showed that **OneMark cannot be treated as a conventional browser CSS renderer**. The next work should therefore focus on what OneMark's theme parser actually supports rather than trying to improve the language grammar.
```
