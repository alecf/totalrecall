/**
 * Theme constants derived from the app's OKLCH color system.
 * Translated to CSS custom properties in global.css,
 * and available as JS constants for dynamic use in components.
 */

export const colors = {
  // Backgrounds (from app's bgVoid/bgSurface)
  bgVoid: 'rgb(13, 14, 18)',
  bgSurface: 'rgb(18, 19, 24)',
  bgHover: 'rgb(25, 27, 33)',
  bgCard: 'rgb(22, 24, 30)',
  bgCardHover: 'rgb(28, 30, 38)',

  // Text
  textPrimary: 'rgb(235, 232, 227)',
  textSecondary: 'rgb(120, 122, 133)',
  textMuted: 'rgb(102, 105, 112)',

  // Accents (all at OKLCH L=0.72, C=0.15)
  accentChrome: 'rgb(86, 126, 211)',
  accentElectron: 'rgb(129, 102, 208)',
  accentClaude: 'rgb(75, 160, 130)',
  accentSystem: 'rgb(209, 107, 56)',
  accentGeneric: 'rgb(115, 117, 128)',

  // Signals
  pressureOk: 'rgb(52, 199, 89)',
  pressureWarn: 'rgb(255, 214, 10)',
  pressureCrit: 'rgb(255, 69, 58)',
} as const;

/** Classifier accent color by name */
export const classifierColor: Record<string, string> = {
  Chrome: colors.accentChrome,
  Electron: colors.accentElectron,
  'Claude Code': colors.accentClaude,
  System: colors.accentSystem,
  Generic: colors.accentGeneric,
};
