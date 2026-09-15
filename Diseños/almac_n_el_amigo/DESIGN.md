---
name: Almacén El Amigo
colors:
  surface: '#f7f9fb'
  surface-dim: '#d8dadc'
  surface-bright: '#f7f9fb'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f4f6'
  surface-container: '#eceef0'
  surface-container-high: '#e6e8ea'
  surface-container-highest: '#e0e3e5'
  on-surface: '#191c1e'
  on-surface-variant: '#43474d'
  inverse-surface: '#2d3133'
  inverse-on-surface: '#eff1f3'
  outline: '#74777e'
  outline-variant: '#c3c6ce'
  surface-tint: '#49607c'
  primary: '#001428'
  on-primary: '#ffffff'
  primary-container: '#0f2942'
  on-primary-container: '#7991af'
  inverse-primary: '#b0c9e8'
  secondary: '#006c4e'
  on-secondary: '#ffffff'
  secondary-container: '#86f5c6'
  on-secondary-container: '#007151'
  tertiary: '#220e00'
  on-tertiary: '#ffffff'
  tertiary-container: '#401f00'
  on-tertiary-container: '#d77503'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d1e4ff'
  primary-fixed-dim: '#b0c9e8'
  on-primary-fixed: '#011d35'
  on-primary-fixed-variant: '#314863'
  secondary-fixed: '#89f7c9'
  secondary-fixed-dim: '#6cdbae'
  on-secondary-fixed: '#002115'
  on-secondary-fixed-variant: '#00513a'
  tertiary-fixed: '#ffdcc3'
  tertiary-fixed-dim: '#ffb77d'
  on-tertiary-fixed: '#2f1500'
  on-tertiary-fixed-variant: '#6e3900'
  background: '#f7f9fb'
  on-background: '#191c1e'
  surface-variant: '#e0e3e5'
typography:
  display-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 40px
    fontWeight: '700'
    lineHeight: 48px
    letterSpacing: -0.02em
  display-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 30px
    fontWeight: '700'
    lineHeight: 38px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  headline-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  title-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  title-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '600'
    lineHeight: 22px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  label-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.01em
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.02em
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '700'
    lineHeight: 14px
    letterSpacing: 0.04em
  numeric-pos:
    fontFamily: Plus Jakarta Sans
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.02em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-tablet: 1.25rem
  gutter-desktop: 1.5rem
  margin: 1rem
  margin-tablet: 1.5rem
  margin-desktop: 2rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

The brand personality balances established commercial credibility with active retail warmth. Geared specifically for Guatemalan men's apparel and accessories retail operations, the visual identity pairs the structure of classic mercantile trading with the speed, responsiveness, and touch ergonomics of a modern Progressive Web App (PWA).

The target audience includes retail sales staff, shop owners, and floor managers operating in fast-paced retail floor environments, outdoor stalls, and back-room storage. Visual interactions must prioritize immediate legible hierarchy, instant state recognition, and friction-free operational efficiency under challenging retail conditions (glare, single-hand terminal use, intermittent connectivity).

The design style fuses **Commercial / Modern Precision** with a vibrant, region-inspired color cadence:
- **High legibility and stark surface separation:** Deep indigo and crisp white containers structure dense operational data cleanly against light neutral backdrops.
- **Vibrant regional accents:** Rich Guatemalan Jade signifies active transactions, positive confirmations, and primary commercial momentum, anchoring the design in local pride without becoming decorative or cluttered.
- **Ergonomic tactile scale:** Generous touch targets, high contrast borders, and instant feedback states ensure zero input ambiguity on mobile screens.

## Colors

The palette leverages a focused set of purpose-driven functional tones tailored for high-volume retail transactions and stock tracking:

- **Primary (`#0F2942` - Deep Indigo / Navy):** The structural anchor. Used for primary navigation rails, top app bars, primary transactional buttons, and critical heading typography. It conveys institutional durability and formal menswear authority.
- **Secondary (`#008F68` - Guatemalan Jade):** The positive action and inventory driver. Applied to "Cobrar" (Checkout) actions, stock availability indicators ("Disponible"), profit metrics, and completed sync markers.
- **Tertiary (`#D97706` - Warm Amber):** The alert and attention anchor. Strictly allocated to low-stock thresholds ("Bajo stock"), pending cloud sync buffers, and critical price override notices.
- **Neutral (`#F8FAFC` - Clean Slate Background):** Provides a crisp, glare-resistant floor base that allows pure white cards (`#FFFFFF`) to project clear functional boundaries without heavy visual weight.

### Semantic Status Palette
- **Success / In Stock (`#008F68`):** Stock count sufficient, online status, sale completed.
- **Warning / Low Stock (`#D97706`):** Critical reorder point, offline sync queued.
- **Error / Depleted (`#DC2626`):** Agotado (Out of stock), transaction void, network drop.
- **Information / System (`#2563EB`):** Customer profile info, SKU lookup help, filter states.

Maintain a strict minimum 4.5:1 contrast ratio against `#F8FAFC` and `#FFFFFF` across all typographic weights and interactive chips.

## Typography

Typography pairs **Plus Jakarta Sans** for structural headers, brand headers, and major currency values with **Inter** for operational body text, dense line-item receipts, and POS data tables.

- **Currency & Totals:** Numeric totals in the register checkout flow use the custom `numeric-pos` scale, leveraging tabular numbers (`font-variant-numeric: tabular-nums`) to ensure vertical decimal alignment across Quetzales amounts (`Q 150.00`).
- **Inventory Badges & Status:** Use `label-sm` set to uppercase with tight letter spacing for unambiguous readability at glance distances.
- **Form Controls & Cart Quantities:** Use `label-lg` to keep dynamic counter numbers readable on lower-tier mobile screens under sunlight.

## Layout & Spacing

This PWA layout relies on a mobile-first, single-column fluid structure that transitions into an ergonomic two-pane split on tablets and POS docking stations.

### Grid & Breakpoints
- **Mobile (Base: 360px - 767px):** Single-column fluid stack. Bottom-pinned action bar for POS charging and cart actions. Canvas margin is fixed at `margin` (`1rem`). Card padding utilizes `space-md` (`1rem`).
- **Tablet / POS Countertop (768px - 1023px):** 8-column layout. 5 columns dedicated to catalog navigation/search, 3 columns locked for the live sale ticket/cart panel. Gutter expands to `gutter-tablet` (`1.25rem`).
- **Desktop / Backoffice (1024px+):** 12-column fixed-fluid mix with maximum content width of 1440px. Margin scales to `margin-desktop` (`2rem`).

### Rhythm Rules
- **Touch Target Threshold:** All tap boundaries on mobile must meet or exceed 48px by 48px to accommodate one-handed operation during customer interactions.
- **Bottom Navigation Clearance:** Always append an empty visual offset of `4.5rem` (`72px`) at the base of scrolling product lists to avoid floating action bar clipping.

## Elevation & Depth

Visual hierarchy uses low-contrast crisp borders reinforced by subtle, tinted ambient drop shadows. This ensures clean element separation on standard PWA mobile screens without muddy gradients.

### Tiers of Depth
- **Level 0 (Canvas Base):** Surface color `#F8FAFC`. Zero elevation, zero shadows.
- **Level 1 (Cards, Stock Row Items, Catalog Tiles):** Pure white `#FFFFFF` surface, contained by a 1px solid border of `#E2E8F0`. Shadow: `0 1px 3px 0 rgba(15, 41, 66, 0.05), 0 1px 2px -1px rgba(15, 41, 66, 0.05)`.
- **Level 2 (Interactive Floating Actions, Quick Pay Bar, Search Sheet):** White `#FFFFFF` surface with border `#CBD5E1`. Shadow: `0 4px 6px -1px rgba(15, 41, 66, 0.08), 0 2px 4px -2px rgba(15, 41, 66, 0.08)`.
- **Level 3 (Modal Modifiers, Receipt Preview, Cash Tender Pop-over):** Shadow: `0 20px 25px -5px rgba(15, 41, 66, 0.12), 0 8px 10px -6px rgba(15, 41, 66, 0.08)`. Tinting shadows with `#0F2942` preserves chromatic cohesion compared to dull gray shadows.

## Shapes

The design system employs **Level 1 (Soft)** shape geometry. Rounded corners remain disciplined and professional, maintaining a solid merchant architecture while eliminating sharp, harsh corners:

- **Standard Elements (Buttons, Inputs, Table Cells):** `0.25rem` (4px). Preserves maximum internal data capacity and crisp touch boundaries.
- **Cards & Modals (`rounded-lg`):** `0.5rem` (8px). Delivers subtle, structured softening of major product containers and transaction modules.
- **Pills & Status Badges (`rounded-xl`):** `0.75rem` (12px) to full pill (`9999px`) reserved specifically for stock chips (`Disponible`, `Agotado`) and quick cash tender bubbles (e.g., `Q50`, `Q100`, `Q200`).

## Components

### Buttons
- **Primary Transactional ("Cobrar / Pagar"):** Full-width, minimum height 52px. Background `#008F68` (Guatemalan Jade), text `#FFFFFF`, font weight 600. Active state darkens to `#007354`.
- **Secondary Action ("Aplicar Descuento", "Nuevo Cliente"):** Background `#FFFFFF`, 1.5px border `#0F2942`, text `#0F2942`.
- **Destructive Action ("Cancelar Venta", "Eliminar Item"):** Background `#FEF2F2`, border 1px solid `#FCA5A5`, text `#DC2626`.

### Inventory Status Badges (Chips)
- **Disponible (In Stock):** Background `#ECFDF5`, border `#A7F3D0`, text `#065F46`. Includes a filled 6px circle indicator in `#008F68`.
- **Bajo Stock (Low Stock):** Background `#FFFBEB`, border `#FDE68A`, text `#92400E`.
- **Agotado (Out of Stock):** Background `#FEF2F2`, border `#FECACA`, text `#991B1B`.
- **Sincronización (Offline/Pending):** Background `#EFF6FF`, border `#BFDBFE`, text `#1E40AF`. Features an animated sync dot indicator.

### Input Fields & Keypad Displays
- **Standard Inputs:** Height 48px, background `#FFFFFF`, border 1px solid `#CBD5E1`, text `#0F2942`. Focused state transitions border to `#0F2942` with a 2px outline glow of `#0F2942` at 15% opacity.
- **POS Currency Input:** Prominent centered total in `#0F2942`, leading symbol "Q" anchored in bold `#008F68`. Background `#F1F5F9` with large tabular numeric entry.

### Cards & Catalog Grid
- **Garment Card (Catalog View):** White `#FFFFFF` card, 1px border `#E2E8F0`, image aspect ratio 4:5 with top corner stock chip. Details panel lists product title (Inter 14px bold), SKU (Inter 12px muted), and price in Quetzales highlighted in primary navy.
- **Cart Line Item:** High-density horizontal card. Size/Color badges rendered in neutral pills (`#F1F5F9`). Integrated increment/decrement stepper with a minimum 40px hit area per touch button.

### Checkboxes & Radio Buttons
- Selection controls use a 20px base square/circle with a 1.5px border in `#64748B`. Active state fills with `#008F68` showing a crisp white interior icon checkmark.

### Offline & Sync Banner
- PWA network status header pinned to the top viewport: 32px height, background `#D97706` for offline mode with clear, simple copy: *"Modo sin conexión - Las ventas se guardarán localmente"*.