# Ramon Antonio Advogados — Design System

Design system for **Ramon Antonio Advogados Associados**, a law firm specializing in **Direito Previdenciário (INSS)** — retirement benefits, auxílios, BPC/LOAS, pensão por morte and revisões.

- **Sede:** Tubarão/SC · atuação em todo o estado de Santa Catarina
- **Posicionamento:** +23 anos de experiência · +10.000 benefícios previdenciários conquistados
- **Instagram:** [@ramonantonioadvogados](https://instagram.com/ramonantonioadvogados)

### Sources provided
- `uploads/logo.jpeg` — official wordmark + monogram on bronze (copied to `assets/logo-full.jpeg`; monogram cropped to `assets/monogram.png`).
- Written brand brief (palette, typography, voice, visual motifs) supplied directly by the client.

No codebase or Figma file was provided — components and the website UI kit are an original interpretation of the written brand brief, not a recreation of an existing build.

---

## CONTENT FUNDAMENTALS — how copy is written

**Language:** Português do Brasil, always.

**Tone:** Corporativo e confiável; técnico mas humano e próximo. The firm sells *trust and clarity* in a stressful, bureaucratic domain (INSS). Copy is reassuring and plain-spoken, never cold or jargon-heavy ("sem juridiquês").

**Person:** Speaks to the reader as **"você"** ("você acompanha cada etapa", "o seu direito", "conte o seu caso"). The firm refers to itself as **"nós" / "a equipe"**, rarely "eu".

**Transparency is the core promise.** Recurring line: *"você acompanha cada etapa"*. Lead with the client's outcome (their benefit, their right), then the firm's role.

**Casing:** Sentence case for headlines and body. Eyebrows/labels are UPPERCASE with wide tracking. Title case is not used for headings.

**Proof points:** Credibility figures appear often and are formatted with a leading `+`: `+23 anos`, `+10.000 benefícios`. Use the serif for the number (see `Stat`).

**No emoji** in institutional communication. No exclamatory hype, no berrante marketing language.

**Example copy:**
- Eyebrow: `DIREITO PREVIDENCIÁRIO · INSS`
- Headline: "O benefício que é seu, conquistado ao seu lado."
- Lead: "Especialistas em aposentadorias, auxílios, BPC/LOAS e revisões. Você acompanha cada etapa do seu processo, com transparência."
- Closing (informativo): "Em resumo" · "Onde pedir: Meu INSS ou 135" · "Salve e compartilhe"

> **⚠️ COMPLIANCE OAB (Provimento 205/2021):** este é um escritório de advocacia. Todo conteúdo deve ser **informativo**, nunca captação ou promessa de resultado. **Proibido**: "fale com um especialista", "análise gratuita", "WhatsApp/agende", "+10.000 benefícios conquistados", valores de honorários, sensacionalismo. **Permitido**: conteúdo educativo, identificação do escritório (@handle, cidade), canais oficiais (Meu INSS, 135), "salve/compartilhe", e o disclaimer de fechamento "Conteúdo informativo. Não substitui a orientação jurídica individual de um(a) advogado(a)." Regra completa em `CLAUDE.md`. Confira fatos previdenciários em fonte oficial (gov.br/INSS); valores de benefício geralmente **dependem** do salário de benefício de cada segurado.

---

## VISUAL FOUNDATIONS

**Color** — a single warm **bronze** family over **cream** and near-black. Primary `#754d2a` (bronze-600) for buttons, icons and links. `#3b2010` (bronze-900) for headings and brand panels. Creams (`#faf3e8` page base, `#f5e6cc` sunken) for light surfaces; `#191310` (dark-900) for dark/video sections with `#ede0c8` ink text on top. No second hue — never introduce blue, purple or cool greys. See `tokens/colors.css`.

**Type** — display in **Cormorant Garamond** (serif, 500–700, tracking −0.01em, line-height ~1.05): elegant, sober, used for all headings, hero copy and stat numbers. UI/body in **Inter** (400–700, line-height 1.6). Eyebrows: Inter, UPPERCASE, letter-spacing 0.24em, preceded by a short bronze tick.

**Spacing** — 4px base grid (`--space-1`…`--space-9`). Generous vertical rhythm: sections use `--space-9` (96px) top/bottom. Container max 1200px.

**Backgrounds** — flat warm fills, never gaudy gradients. The only gradient permitted is the **short bronze divider** (`#754d2a → #c4a882`, the `--gradient-bronze` token) used as a rule under titles, and a subtle photographic grain on dark imagery. No repeating patterns or textures beyond fine grain.

**Imagery** — warm, sober, professional **black-and-white portraits that gain color**. People-focused. Placeholders in the kit use a dark bronze gradient + dot grain; replace with real photos.

**Corner radii** — soft and warm: 8/12/16/20px (`--radius-*`), pills (999px) for buttons and badges. Cards use 16px.

**Cards** — white surface, 16px radius, hairline `--border-soft` (bronze at 16% alpha), discreet **warm** shadow (`--shadow-md`, bronze-tinted, never grey/blue). Interactive cards lift 3px and deepen to `--shadow-lg` on hover.

**Shadows** — all warm-toned (`rgba(59,32,16,…)`). Three steps: sm / md / lg, plus a deep `--shadow-dark` for elements on near-black.

**Badges / selos** — pill-shaped. Signature variant is **translucent dark** (`rgba(25,19,16,0.55)` + blur + ink border) laid over photography. Also bronze-tinted, solid bronze, and cream variants.

**Borders** — hairlines only, expressed as bronze at low alpha (`--border-soft` 16%, `--border-strong` 32%); on dark, ink at 16% (`--border-on-dark`). No heavy outlines.

**Animation** — restrained. Standard ease `cubic-bezier(0.4,0,0.2,1)`; fast 140ms, base 220ms. Buttons darken on hover and shrink to 0.97 on press; cards lift on hover. No bounces, no infinite/decorative loops.

**Hover states** — primary buttons → `--color-primary-hover` (bronze-700, darker); outline/ghost → faint bronze wash; links → bronze-600. **Press** → `scale(0.97)`.

**Focus** — warm ring: `0 0 0 3px` bronze at 35% (`--ring-focus`).

**Transparency & blur** — used sparingly: the sticky header (cream at 86% + 10px blur) and the dark seal badges (blur over photos). Not used decoratively elsewhere.

**Layout rules** — sticky translucent header; two-column hero (copy + portrait); section bands alternate light → white → dark → bronze for rhythm. Max two background colors per long page beyond the structural dark/bronze bands.

---

## ICONOGRAPHY

The brand brief specifies **no icon library**. Iconography here is **line icons** drawn as inline SVG at **1.6 stroke weight**, round caps/joins, on a 24px grid — matching the **Lucide** visual style. When you need a broader set, use **Lucide** ([lucide.dev](https://lucide.dev), CDN: `https://unpkg.com/lucide@latest`) for a consistent match; flag any other source.

- Icons are tinted `--color-primary` (bronze-600), often inside a 46px rounded tile filled with bronze at 10% alpha (see `Areas` cards).
- **No emoji**, ever, in institutional contexts. No unicode-glyph icons.
- The brand's own mark — the intertwined **R/A monogram** with hourglass accents — is in `assets/monogram.png` (cropped from the logo) and `assets/logo-full.jpeg`. Use the monogram as a compact lockup (header/footer) and the full wordmark on bronze panels.

> **Substitution flagged:** the cropped `monogram.png` is lifted from the supplied JPEG (bronze background baked in). For crisp use on arbitrary backgrounds, please supply a **vector (SVG) logo + monogram with transparent background**.

---

## Index / manifest

**Root**
- `styles.css` — entry point; `@import`s all token files (consumers link this one file).
- `tokens/` — `fonts.css`, `colors.css`, `typography.css`, `spacing.css`, `effects.css`.
- `assets/` — `logo-full.jpeg`, `monogram.png`.
- `readme.md` — this file. `SKILL.md` — Agent-Skills wrapper.

**Foundation cards** (`guidelines/*.card.html`) — Colors (bronze, neutrals, surfaces), Type (display, body, eyebrow), Spacing (scale, radii, shadows), Brand (logo, divider).

**Components** (`components/core/`) — `Button`, `Badge`, `Card`, `Input`, `Eyebrow`, `Divider`, `Stat`. Each has `.jsx` + `.d.ts` + `.prompt.md`; demo in `core.card.html`. Namespace: `window.DesignSystem_f6e542`.

**UI kit** (`ui_kits/website/`) — single-page marketing site: Header, Hero, Areas, Process, ContactFooter. Entry `index.html`.

> Webfonts load via the Google Fonts API (`tokens/fonts.css`). For offline/self-hosted use, swap for local `@font-face` + woff2 — flagged as a follow-up.
