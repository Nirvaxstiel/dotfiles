// cyber-brutalism Tailwind extension
// Paste into tailwind.config.js -> theme.extend
// Works with Tailwind CSS v3+

const cyberTheme = {
  colors: {
    'cyber': {
      'black':       '#000000',
      'elevated':    '#0a0a0a',
      'surface':     '#111111',
      'foreground':  '#ededed',
      'muted':       '#666666',
      'subtle':      '#444444',
      'accent':      '#a3e635',
      'accent-dim':  '#7ec22b',
      'border':      'rgba(255,255,255,0.08)',
      'border-strong': 'rgba(255,255,255,0.15)',
      'danger':      '#e5484d',
      'warning':     '#f5a623',
      'info':        '#0070f3',
    },
  },
  fontFamily: {
    mono: ["'JetBrains Mono'", "'Fira Code'", "'Cascadia Code'", 'ui-monospace', 'monospace'],
    // also set sans to mono for full terminal vibe
    sans: ["'JetBrains Mono'", "'Fira Code'", "'Cascadia Code'", 'ui-monospace', 'monospace'],
  },
  borderRadius: {
    DEFAULT: '0',
    none: '0',
  },
  boxShadow: {
    'cyber': 'none',
  },
  borderWidth: {
    DEFAULT: '1px',
  },
}

module.exports = cyberTheme
