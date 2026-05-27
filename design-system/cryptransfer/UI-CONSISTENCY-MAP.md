# UI Consistency Mapping Matrix

## Current State vs. Desired State

### 1. COLOR PALETTE MAPPING

#### Dark Mode (Current Actual vs. Desired)

| Component | Current | Actual Hex | Desired | Desired Hex | Issue |
|-----------|---------|----------|---------|----------|-------|
| Background | darkBg | #0F172A | darkBg | #0F172A | ✓ Correct |
| Surface | darkSurface | #1E293B | darkSurface | #1E293B | ✓ Correct |
| Primary (enabled button) | cs.primary (from gold seed) | #CA8A04 | cs.primary | #CA8A04 | ✓ Correct |
| Secondary (step done) | Colors.green | #4ADE80 | cs.secondary | #FBBF24 | ✗ WRONG |
| Status pending | Colors.amber | #FBBF24 | cs.primary | #CA8A04 | ✗ WRONG |
| Status success | Colors.green | #4ADE80 | cs.secondary | #FBBF24 | ✗ Different |
| Status error | cs.error | #FF5252 | cs.error | #FF5252 | ✓ Correct |
| Status locked | Colors.amber.shade700 | #B45309 | cs.tertiary | #8B5CF6 | ✗ WRONG |
| Text main | darkTextMain | #F8FAFC | darkTextMain | #F8FAFC | ✓ Correct |
| Text secondary | darkTextSecondary | #94A3B8 | #CBD5E1 (better contrast) | #CBD5E1 | ⚠ Needs adjustment |
| Border | darkBorder | #334155 | darkBorder | #334155 | ✓ Correct |
| Glass bg | white @ 5% | rgba(255,255,255,0.05) | white @ 8% | rgba(255,255,255,0.08) | ⚠ Needs adjustment |
| Glass border | white @ 20% | rgba(255,255,255,0.2) | white @ 20% | rgba(255,255,255,0.2) | ✓ Correct |

#### Light Mode (Current Actual vs. Desired)

| Component | Current | Actual Hex | Desired | Desired Hex | Issue |
|-----------|---------|----------|---------|----------|-------|
| Background | lightBg | #F8FAFC | lightBg | #F8FAFC | ✓ Correct |
| Surface | lightSurface | #FFFFFF | lightSurface | #FFFFFF | ✓ Correct |
| Primary | cs.primary (from blue seed) | #3B82F6 | cs.primary | #3B82F6 | ✓ Correct |
| Secondary (step done) | Colors.green | #4ADE80 | cs.secondary | #60A5FA | ✗ WRONG |
| Status success | Colors.green | #4ADE80 | cs.secondary | #60A5FA | ✗ Different |
| Text main | lightTextMain | #0F172A | lightTextMain | #0F172A | ✓ Correct |
| Text secondary | lightTextSecondary | #64748B | #475569 (better) | #475569 | ⚠ Needs adjustment |
| Glass bg | white @ 50% | rgba(255,255,255,0.5) | white @ 20% | rgba(255,255,255,0.2) | ✗ TOO OPAQUE |
| Glass border | white @ 30% | rgba(255,255,255,0.3) | white @ 30% | rgba(255,255,255,0.3) | ✓ Correct |

---

### 2. BUTTON SYSTEM MAPPING

#### Current Dual System

```
CrypButton (3D depth system)
├─ SenderScreen Step 2: "Encrypt File"
├─ SenderScreen Step 3: "Send to receiver"
├─ SenderScreen Step 4: "Upload to Cloud"
├─ ReceiverScreen Step 0: (future)
├─ ReceiverScreen Step 2: "Open Mailbox"
├─ TransferProgressScreen: "Uploading..." status
├─ DecryptScreen: "Save & Wipe"
└─ EndSessionScreen: "Back to Home"

GlassButton (flat glassmorphic)
├─ HomeScreen: "Accept" on connections
├─ HomeScreen: "Cancel" on pending proposals
├─ HomeScreen: "Send Request" in friend search
├─ FindFriendsScreen: various actions
├─ SidebarDrawer: navigation buttons (maybe)
└─ Other modals/sheets: "Close", "Confirm", etc.
```

#### Desired Unified System

**Option A: CrypButton for Primary, GlassButton for Secondary**
```
PRIMARY ACTIONS (CrypButton 3D)
├─ Main file operation: "Encrypt & Send"
├─ Session control: "Open Mailbox", "Close Mailbox"
├─ Navigation action: "Start Transfer"
└─ Critical action: "Save & Wipe"

SECONDARY ACTIONS (GlassButton flat)
├─ Connections: "Accept", "Reject"
├─ Modals: "Close", "Cancel"
├─ Tertiary: "Learn More", "Details"
└─ Non-blocking: "View Logs", "Settings"
```

**Option B: Remove GlassButton entirely, extend CrypButton**
```
CrypButton variants:
├─ style: .primary (default, 3D, shadow)
├─ style: .secondary (glassmorphic, no shadow)
├─ style: .tertiary (outline only)
└─ size: .large (52px), .normal (48px), .small (40px)
```

---

### 3. COMPONENT CONSISTENCY MAP

#### StepCard States

**Current Implementation (INCONSISTENT):**
```dart
// Done state
borderColor: Colors.green.withValues(alpha: 0.4)  // Always green
color: Colors.green.withValues(alpha: isDark ? 0.05 : 0.02)
stepTitle: Text(title, color: Colors.green)  // Always green
circle: Colors.green  // Always green

// Pending state
borderColor: null  // Default
color: null  // Default
stepTitle: Text(title, color: cs.onSurface)  // Uses theme
circle: cs.primary  // Uses theme

// PROBLEM: Colors don't match in light mode. Green doesn't exist in light colorScheme
```

**Desired Implementation (CONSISTENT):**
```dart
// Done state — use cs.secondary (consistent across light/dark)
borderColor: cs.secondary.withValues(alpha: 0.3)
color: cs.secondary.withValues(alpha: isDark ? 0.08 : 0.04)
stepTitle: Text(title, color: cs.secondary)
circle: cs.secondary

// Pending state — use cs.primary
borderColor: null
color: null
stepTitle: Text(title, color: cs.onSurface)
circle: cs.primary

// Current state (in progress) — use cs.tertiary (if available)
circle: cs.tertiary
```

#### Button Styling Consistency

**Current:**
```
CrypButton:
├─ Height: 52px
├─ Padding: Vert 14, Horiz 16
├─ Border radius: 16px
├─ Font: Poppins 15 w600
├─ Depth: 4px shadow
└─ State feedback: Press 0.98 scale

GlassButton:
├─ Height: ~48px (derived from padding)
├─ Padding: Vert 14, Horiz 16
├─ Border radius: 14px (different!)
├─ Font: Poppins 15 w600
├─ Depth: 0px (flat)
└─ State feedback: Press 0.98 scale

INCONSISTENCIES:
├─ Different border radius (16 vs 14)
├─ Different height (52 vs 48)
├─ Different visual depth (shadow vs none)
└─ Different container (GlassContainer vs DecoratedBox)
```

**Desired (Unified):**
```
CrypButton (primary):
├─ Height: 52px
├─ Padding: Vert 14, Horiz 16
├─ Border radius: 16px
├─ Font: bodyMedium w600 (from theme)
├─ Depth: 4px shadow
└─ State feedback: Press 0.98 scale

SecondaryButton (new, based on CrypButton):
├─ Height: 48px
├─ Padding: Vert 12, Horiz 14
├─ Border radius: 12px
├─ Font: bodySmall w600 (from theme)
├─ Depth: 2px shadow
└─ State feedback: Press 0.98 scale

GlassButton (tertiary):
├─ Height: 44px
├─ Padding: Vert 10, Horiz 12
├─ Border radius: 10px
├─ Font: labelSmall w600 (from theme)
├─ Depth: 0px (pure glass)
└─ State feedback: Opacity 0.8
```

---

### 4. TYPOGRAPHY CONSISTENCY MAP

**Current (SCATTERED):**
```
SenderScreen:
├─ Title: Custom TextStyle (repeated)
├─ Label: Custom TextStyle (repeated)
├─ Error: Custom TextStyle (repeated)
└─ Button text: Poppins 15 w600 (hardcoded in CrypButton)

ReceiverScreen:
├─ Stepper title: GoogleFonts.poppins w700 15 (different!)
├─ Content: Custom TextStyle (different!)
└─ Button text: Poppins 15 w600

HomeScreen:
├─ Title: Theme.textTheme.titleMedium (correct!)
├─ Subtitle: Theme.textTheme.bodyMedium (correct!)
└─ Button text: Poppins 15 w600 (hardcoded, inconsistent!)

PROBLEM: Button text is never taken from theme.textTheme
```

**Desired (CENTRALIZED):**
```
// In app_theme.dart, extend textTheme:
textTheme: GoogleFonts.poppinsTextTheme(
  base.textTheme.copyWith(
    // Semantic labels
    labelSmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurfaceVariant,
    ),
    labelMedium: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface,
    ),
    // Body
    bodySmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: textSecondary,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: colorScheme.onSurface,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: colorScheme.onSurface,
    ),
    // Titles
    titleSmall: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: colorScheme.onSurface,
    ),
    // Headlines
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: colorScheme.onSurface,
    ),
  ),
),
```

**Then use everywhere:**
```dart
// Before
Text('Step 1', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700))

// After
Text('Step 1', style: Theme.of(context).textTheme.titleSmall)
```

---

### 5. STATUS INDICATOR MAPPING

**Current (HARDCODED COLORS):**
```
Step done: Colors.green (always)
Step pending: cs.primary (follows theme)
Session locked: Colors.amber.shade700 (always)
Session decrypting: cs.primary (follows theme)
Session terminated: cs.error (follows theme)
Transfer success: Colors.green (always)
Transfer error: Colors.red (always)
```

**Desired (THEME-BASED):**
```
Step done: cs.secondary (Theme-driven)
Step pending: cs.primary (Consistent)
Session locked: cs.tertiary or custom sessionLockedColor
Session decrypting: cs.primary (Consistent)
Session terminated: cs.error (Consistent)
Transfer success: cs.secondary (Consistent)
Transfer error: cs.error (Consistent)
```

---

## 6. SCREEN-BY-SCREEN MAPPING

### HomeScreen
```
Current Issues:
├─ StatusBanner: hardcoded Colors.deepPurple
├─ Pending row: hardcoded green/red colors
├─ Connection badge: hardcoded green
├─ Text styles: mixed (some theme, some hardcoded)
└─ Button styles: using GlassButton (should be CrypButton or consistent)

Required Changes:
├─ Replace Colors.deepPurple → cs.tertiary
├─ Replace Colors.green → cs.secondary
├─ Replace Colors.red → cs.error
├─ Replace custom TextStyles → Theme.of(context).textTheme.*
└─ Decide button style globally
```

### SenderScreen
```
Current Issues:
├─ Step card titles: colored green when done (hardcoded)
├─ CrypButton used correctly ✓
├─ File size display: uses custom TextStyle
├─ Progress indicator: no clear status indication
└─ Status messages: custom colors

Required Changes:
├─ StepCard: replace Colors.green with cs.secondary
├─ Centralize TextStyles
└─ Standardize status messages
```

### ReceiverScreen
```
Current Issues:
├─ Stepper: inconsistent color logic (custom colors per step)
├─ Toggle switch: activeColor hardcoded (deprecated in Material 3)
├─ Step cards: inconsistent styling vs SenderScreen
├─ Session banner: custom colors
└─ CrypButton: used correctly ✓

Required Changes:
├─ Unify StepCard across both screens
├─ Replace Switch.activeColor → activeThumbColor (Material 3)
├─ Centralize colors
└─ Match SenderScreen visual style
```

---

## IMPLEMENTATION ROADMAP

### Week 1: Foundation (Critical)
1. **Audit all hardcoded colors** (grep for `Colors\.|Color(0xFF`)
2. **Consolidate color definitions** in `app_theme.dart`
3. **Extend ColorScheme** with semantic colors
4. **Replace hardcoded colors** in all screens

### Week 2: Components (High Priority)
1. **Unify button system** (decide: CrypButton or dual system)
2. **Fix StepCard** across all screens
3. **Standardize GlassContainer**
4. **Fix typography** (extract to textTheme)

### Week 3: Polish (Medium Priority)
1. **Dark/light mode transitions**
2. **Contrast ratio verification**
3. **Focus states and keyboard nav**
4. **Touch target verification**

---

## VALIDATION CHECKLIST

After each phase:
- [ ] Run `flutter analyze` — no warnings
- [ ] Test light mode on device
- [ ] Test dark mode on device
- [ ] Check contrast with WebAIM contrast checker
- [ ] Verify buttons work on 375px width (mobile)
- [ ] Compare visual consistency across all screens
- [ ] User test with actual users

---

**Generated:** 2026-05-27  
**Next Review:** After Phase 1 implementation
