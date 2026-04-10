# Changelog

All notable changes to Y2Notes are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] — 2026-04-04

### Added

- **PencilKit Canvas**: Full Apple Pencil support with pressure, tilt, barrel-roll
  (Pencil Pro), and hover preview (M2+ iPad Pro)
- **Ink Effects**: Fire 🔥, sparkle ✨, glitch 🌀, ripple 💧 — real-time particle
  overlays with per-device performance budgets (basic/standard/pro/ultra tiers)
- **Multi-Page Notes**: Book-like experience with add/remove/navigate pages within
  a single note. Backward-compatible dual encoding for legacy single-page notes
- **Notebooks & Sections**: Organise notes into notebooks with collapsible sections,
  drag-to-reorder, rename, and delete
- **Study System**: SM-2 spaced-repetition flashcards with mastery tracking
  (new → learning → reviewing → mastered), bulk import, review history, and stats
- **PDF Annotation**: Import PDFs, annotate pages with PencilKit, save per-page drawings
- **Google Drive Sync**: Cloud backup with offline queue and conflict resolution
- **6 Themes**: System, Light, Dark, Sepia, Midnight, Ocean — per-note or per-notebook overrides
- **12 Notebook Covers**: Ocean, Forest, Sunset, Lavender, Slate, Sand, Ruby, Midnight,
  Jade, Coral, Copper, Nebula — plus custom photo covers
- **6 Page Templates**: Blank, Lined, Grid, Dotted, Cornell, Music Staff
- **20 Ink Presets**: Across 7 families (Standard, Metallic, Neon, Watercolour, Fire,
  Glitch, Phantom) with user-creatable custom presets
- **Full-Text Search**: Across note titles, typed text, and handwriting OCR
- **Onboarding**: 4-step welcome flow introducing Pencil support, themes, and getting started
- **Accessibility**: Reduced motion, high contrast, VoiceOver labels, configurable autosave
- **Diagnostics View**: Storage stats, data integrity checks, orphan detection, force save
- **Localisation**: English (141+ keys), Spanish scaffolding
- **CI/CD**: Codemagic pipeline → TestFlight distribution

### Infrastructure

- GitHub Actions CI workflow for PR build checks and SwiftLint
- SwiftLint configuration with project-specific rules
- EditorConfig for cross-editor formatting consistency
- Makefile with build, test, lint, clean, and validation targets
- Comprehensive project documentation (Architecture, Ink Effects, Multi-Page Design,
  Data Model Reference, Testing Strategy, Roadmap)
- GitHub issue and PR templates
- Privacy manifest (PrivacyInfo.xcprivacy)
- Security policy (SECURITY.md)
- Contributing guide (CONTRIBUTING.md)
