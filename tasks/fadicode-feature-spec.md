# Fadicode v2 Feature Spec — Gap Analysis & Implementation Plan

## Overview

This document maps every original fadicode feature to what CMUX already provides, identifies gaps, and specs out how to implement each missing feature using CMUX's architecture.

**Legend:**

- HAVE = CMUX already has this (no work needed)
- PARTIAL = CMUX has something similar but fadicode's version is better/different
- MISSING = Not in CMUX, needs to be built
- SKIP = Not worth porting (CMUX's approach is better)
- DONE = Implemented in Sessions 1-7

---

## 1. Tab / Workspace Color System

| Feature                                                        | Status  | Notes                                                                              |
| -------------------------------------------------------------- | ------- | ---------------------------------------------------------------------------------- |
| Preset color palette (9 colors)                                | HAVE    | CMUX has `WorkspaceTabColorSettings` with 16 colors                                |
| Custom color picker (HSB gradient)                             | HAVE    | CMUX has custom color support in workspace settings                                |
| Right-click terminal → color picker                            | DONE    | 9-color swatch submenu in terminal right-click context menu                        |
| Auto-assign color per project directory                        | DONE    | `autoColorIfNeeded()` in Workspace.swift, gated by settings toggle                 |
| Saved custom colors (up to 10)                                 | PARTIAL | CMUX has custom colors but not a "saved colors" shelf                              |
| Tab bar color dot indicator                                    | DONE    | Bonsplit tabs show workspace color via `tabColor` API (top indicator strip)        |
| Ghostty accent color push (`ghostty_surface_set_accent_color`) | DONE    | Added to Ghostty fork: HSL hue remap of Claude orange (#da7756) to workspace color |

---

## 2. Project Badges

| Feature                                              | Status | Notes                                                         |
| ---------------------------------------------------- | ------ | ------------------------------------------------------------- |
| Colored project name badge (top-left of terminal)    | DONE   | `ProjectBadgeView.swift` in `FadiCodeOverlayHost`             |
| Flood-fill same-color grouping (one badge per group) | SKIP   | Complexity vs value — each pane shows its own badge           |
| Badge visibility settings (Always / Hover / Never)   | DONE   | `@AppStorage("FadicodeBadgeVisibility")` with hover animation |

---

## 3. Project Picker Overlay

| Feature                                    | Status | Notes                                             |
| ------------------------------------------ | ------ | ------------------------------------------------- |
| Full-screen project picker on new terminal | DONE   | `ProjectPickerOverlay.swift` with breadcrumb nav  |
| Breadcrumb navigation                      | DONE   | Clickable path segments in overlay                |
| Search/filter field                        | DONE   | Type to filter folders                            |
| Sorted by modification date                | DONE   | Most recent projects first                        |
| Auto-cd + launch on selection              | DONE   | `cd <path> && clear` on project selection         |
| Double-click to drill into subfolders      | DONE   | Single-click selects at root, double-click drills |

---

## 4. Split Layout Presets

| Feature                         | Status | Notes                                   |
| ------------------------------- | ------ | --------------------------------------- |
| "2 Top, 1 Bottom" preset        | HAVE   | `applyLayout2Top1Bottom` in AppDelegate |
| "1 Left, 2 Right" preset        | HAVE   | `applyLayout1Left2Right` in AppDelegate |
| "Grid 2×2" preset               | HAVE   | `applyLayoutGrid2x2` in AppDelegate     |
| Menu bar access (View → Layout) | HAVE   | Fadicode menu → Layout submenu          |

---

## 5. Terminal Right-Click Context Menu

| Feature                        | Status | Notes                                              |
| ------------------------------ | ------ | -------------------------------------------------- |
| Copy / Paste                   | HAVE   | Standard terminal context menu                     |
| Split Right / Left / Down / Up | HAVE   | All 4 directions in context menu                   |
| Reset Terminal                 | HAVE   | Via terminal commands                              |
| Toggle Terminal Inspector      | DONE   | Right-click → "Terminal Inspector" shows slide-out |
| Terminal Read-only toggle      | DONE   | Right-click → "Read-Only" with checkmark state     |
| New Clean Terminal             | HAVE   | New surface from context menu                      |
| New Web Panel                  | HAVE   | Browser panel splits                               |
| Close Panel                    | HAVE   | Standard close                                     |
| Change Tab Title               | HAVE   | Workspace rename                                   |
| Inline Color Palette           | DONE   | 9-color "Workspace Color" submenu                  |

---

## 6. Browser / Web Panel

| Feature                         | Status | Notes                                                 |
| ------------------------------- | ------ | ----------------------------------------------------- |
| Web browser panel               | HAVE   | Full BrowserPanel with WKWebView                      |
| Omnibar with search suggestions | HAVE   | Omnibar with Google/DuckDuckGo/Bing/Kagi              |
| Back/Forward/Reload             | HAVE   | Full navigation controls                              |
| Browser find (Cmd+F)            | HAVE   | Find overlay with match counter                       |
| Developer tools                 | HAVE   | Cmd+Opt+I                                             |
| Web favorites / bookmarks       | HAVE   | `WebFavoritesStore.swift` + favorites grid in browser |
| Dark mode CSS injection         | HAVE   | Auto-inject dark CSS into all pages                   |
| Google sign-in UA spoofing      | HAVE   | Safari user agent for Google OAuth                    |
| QuickLaunchBar on browser tabs  | DONE   | Three-dot bar overlay added to BrowserPanelView       |
| Web button converts current tab | DONE   | `replaceFocusedTerminalWithBrowser()` in Workspace    |

---

## 7. Quick Terminal (Pop-Up)

| Feature                                       | Status | Notes                                               |
| --------------------------------------------- | ------ | --------------------------------------------------- |
| Global hotkey to show/hide quick terminal     | DONE   | Ctrl+` via menu item in Fadicode menu               |
| Configurable position (Top/Bottom/Left/Right) | DONE   | `@AppStorage("QuickTerminalPosition")` in settings  |
| Animated in/out                               | DONE   | easeOut/easeIn slide animation from configured edge |
| Floating NSPanel behavior                     | DONE   | `.floating` level, `.canJoinAllSpaces`, HUD style   |
| Size setting                                  | DONE   | 20-90% slider in settings                           |

---

## 8. Command Palette

| Feature                    | Status | Notes                               |
| -------------------------- | ------ | ----------------------------------- |
| Fuzzy search over commands | HAVE   | `ContentView.swift` command palette |
| Keyboard shortcut to open  | HAVE   | Wired in existing shortcuts         |

---

## 9. App Intents (Siri Shortcuts)

| Feature              | Status | Notes                                        |
| -------------------- | ------ | -------------------------------------------- |
| NewTerminalIntent    | DONE   | Creates new terminal tab via Shortcuts       |
| CloseTerminalIntent  | DONE   | Closes focused terminal via Shortcuts        |
| FocusTerminalIntent  | DONE   | Brings app to foreground via Shortcuts       |
| QuickTerminalIntent  | DONE   | Toggles quick terminal via Shortcuts         |
| InputTextIntent      | DONE   | Sends text to focused terminal via Shortcuts |
| AppShortcutsProvider | DONE   | 3 Siri phrases registered                    |

---

## 10. Overlay System

| Feature                           | Status | Notes                                                    |
| --------------------------------- | ------ | -------------------------------------------------------- |
| Shader overlay (59 Metal shaders) | HAVE   | Compiled and wired, funcName mapping fixed               |
| Border glow                       | HAVE   | Gated by `@AppStorage("FadicodeBorderGlowEnabled")`      |
| Activity badge                    | HAVE   | Top-right badge with timer                               |
| Task flash                        | HAVE   | Completion flash animation                               |
| Completion popup                  | HAVE   | Bottom-right summary card                                |
| Question detection pill           | HAVE   | Bottom-center question buttons                           |
| Pixel pet                         | HAVE   | 96pt animated sprite, bottom-right                       |
| Pixel pet tap interaction         | DONE   | `.petted` state with grooming animation                  |
| Debug overlay (Cmd+Shift+D)       | HAVE   | Full debug HUD with shader picker                        |
| Recall button                     | HAVE   | Recalls dismissed completion                             |
| Completion sound                  | HAVE   | Gated by `@AppStorage("FadicodeCompletionSoundEnabled")` |
| Content polling (100ms)           | HAVE   | Terminal content analysis                                |
| LLM summary polling (5s)          | HAVE   | Claude Haiku activity summaries                          |
| OSC 7777 task completion          | HAVE   | Signal routing wired                                     |
| OSC 7778 working state            | HAVE   | Signal routing wired                                     |
| Surface tint (workspace color)    | DONE   | 4% opacity full-surface tint + 2px top strip             |

---

## 11. Settings / Preferences

| Feature                                | Status | Notes                                                       |
| -------------------------------------- | ------ | ----------------------------------------------------------- |
| General settings                       | HAVE   | CMUX has settings window                                    |
| Appearance settings                    | HAVE   | Theme, sidebar style                                        |
| Keyboard shortcuts settings            | HAVE   | Full shortcut customization                                 |
| Terminal settings                      | HAVE   | Ghostty config                                              |
| Browser settings                       | HAVE   | Search engine, theme                                        |
| Notification settings                  | HAVE   | Sound, behavior                                             |
| Sidebar settings                       | HAVE   | Layout, indicators                                          |
| Quick Terminal settings                | DONE   | Position picker + size slider in Fadicode section           |
| Fadicode overlay settings              | DONE   | Shaders, pet, auto-color, badge, glow, sound, visual preset |
| Overlay settings in preferences window | DONE   | Full Fadicode section in settings panel                     |

---

## 12. Window Management

| Feature                | Status | Notes                          |
| ---------------------- | ------ | ------------------------------ |
| Multiple window styles | HAVE   | Glass effect, titlebar options |
| Tab groups             | HAVE   | Sidebar workspaces             |
| Fullscreen             | HAVE   | Standard macOS fullscreen      |
| Window restoration     | HAVE   | Session persistence            |
| Window decorations     | HAVE   | Custom toolbar, drag handle    |
| Float on top           | HAVE   | Fadicode menu → Float on Top   |

---

## 13. Ghostty Accent Color Push

| Feature                              | Status | Notes                                                                    |
| ------------------------------------ | ------ | ------------------------------------------------------------------------ |
| `ghostty_surface_set_accent_color`   | DONE   | Added to Ghostty fork: HSL hue remap of Claude orange to workspace color |
| `ghostty_surface_clear_accent_color` | DONE   | Clears accent color override on Ghostty surface                          |

---

## 14. Terminal Inspector + Read-Only

| Feature                  | Status | Notes                                                        |
| ------------------------ | ------ | ------------------------------------------------------------ |
| Terminal Inspector panel | DONE   | Slide-out panel with shell, cwd, size, cell size, R/O toggle |
| Read-Only mode           | DONE   | Blocks keyboard input, lock icon badge, right-click toggle   |

---

## Implementation Sessions Summary

| Session | Status   | Features                                                              |
| ------- | -------- | --------------------------------------------------------------------- |
| 1       | COMPLETE | Project picker fix, QuickLaunchBar on browser, web tab conversion     |
| 2       | COMPLETE | Verified 14 existing features                                         |
| 3       | COMPLETE | Settings expansion, terminal color theming (bonsplit tab color, tint) |
| 4       | COMPLETE | Quick Terminal drop-down (NSPanel, slide animation, settings)         |
| 5       | COMPLETE | Terminal Inspector + Read-Only mode                                   |
| 6       | COMPLETE | Pixel Pet tap interaction (petted state + grooming animation)         |
| 7       | COMPLETE | App Intents (5 intents + AppShortcutsProvider), feature spec update   |
