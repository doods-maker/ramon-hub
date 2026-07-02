/* @ds-bundle: {"format":3,"namespace":"DesignSystem_f6e542","components":[{"name":"Badge","sourcePath":"components/core/Badge.jsx"},{"name":"Button","sourcePath":"components/core/Button.jsx"},{"name":"Card","sourcePath":"components/core/Card.jsx"},{"name":"Divider","sourcePath":"components/core/Divider.jsx"},{"name":"Eyebrow","sourcePath":"components/core/Eyebrow.jsx"},{"name":"Input","sourcePath":"components/core/Input.jsx"},{"name":"Stat","sourcePath":"components/core/Stat.jsx"}],"sourceHashes":{"components/core/Badge.jsx":"9b4f6854bb61","components/core/Button.jsx":"6109ec563b2e","components/core/Card.jsx":"d8c64702c142","components/core/Divider.jsx":"20a2713bbb6e","components/core/Eyebrow.jsx":"1ada1ebb4dac","components/core/Input.jsx":"fc7c2f55b07f","components/core/Stat.jsx":"7e288963cc4e","ui_kits/website/Areas.jsx":"a149984723bb","ui_kits/website/ContactFooter.jsx":"306f301a1503","ui_kits/website/Header.jsx":"0060be438aea","ui_kits/website/Hero.jsx":"0096898ded6e","ui_kits/website/Process.jsx":"a8e907a627c6","ui_kits/website/Shared.jsx":"f06582df423a"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.DesignSystem_f6e542 = window.DesignSystem_f6e542 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/core/Badge.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Pill badge / selo. Translucent dark by default (the brand's signature seal).
 */
function Badge({
  children,
  variant = 'dark',
  icon,
  style,
  ...rest
}) {
  const variants = {
    dark: {
      background: 'rgba(25, 19, 16, 0.55)',
      color: 'var(--ink-100)',
      border: '1px solid var(--border-on-dark)',
      backdropFilter: 'blur(6px)'
    },
    bronze: {
      background: 'color-mix(in srgb, var(--bronze-600) 12%, transparent)',
      color: 'var(--bronze-700)',
      border: '1px solid var(--border-soft)'
    },
    solid: {
      background: 'var(--color-primary)',
      color: 'var(--text-on-primary)',
      border: '1px solid transparent'
    },
    cream: {
      background: 'var(--cream-200)',
      color: 'var(--bronze-700)',
      border: '1px solid transparent'
    }
  };
  return /*#__PURE__*/React.createElement("span", _extends({
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: '8px',
      fontFamily: 'var(--font-sans)',
      fontSize: 'var(--text-xs)',
      fontWeight: 600,
      letterSpacing: '0.04em',
      padding: '6px 14px',
      borderRadius: 'var(--radius-pill)',
      lineHeight: 1.1,
      ...variants[variant],
      ...style
    }
  }, rest), icon, children);
}
Object.assign(__ds_scope, { Badge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Badge.jsx", error: String((e && e.message) || e) }); }

// components/core/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Primary action button for Ramon Antonio Advogados.
 * Bronze-filled by default; serif-free, warm and confident.
 */
function Button({
  children,
  variant = 'primary',
  size = 'md',
  href,
  iconLeft,
  iconRight,
  disabled = false,
  onClick,
  type = 'button',
  style,
  ...rest
}) {
  const sizes = {
    sm: {
      padding: '8px 16px',
      fontSize: '0.8125rem'
    },
    md: {
      padding: '12px 24px',
      fontSize: '0.9375rem'
    },
    lg: {
      padding: '16px 32px',
      fontSize: '1.0625rem'
    }
  };
  const variants = {
    primary: {
      background: 'var(--color-primary)',
      color: 'var(--text-on-primary)',
      border: '1px solid transparent'
    },
    secondary: {
      background: 'transparent',
      color: 'var(--color-primary)',
      border: '1px solid var(--border-strong)'
    },
    ghost: {
      background: 'transparent',
      color: 'var(--color-primary)',
      border: '1px solid transparent'
    },
    onDark: {
      background: 'var(--cream-100)',
      color: 'var(--bronze-900)',
      border: '1px solid transparent'
    }
  };
  const base = {
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '0.5em',
    fontFamily: 'var(--font-sans)',
    fontWeight: 600,
    letterSpacing: '0.01em',
    lineHeight: 1,
    borderRadius: 'var(--radius-pill)',
    cursor: disabled ? 'not-allowed' : 'pointer',
    opacity: disabled ? 0.5 : 1,
    textDecoration: 'none',
    transition: 'background var(--transition-fast), color var(--transition-fast), transform var(--transition-fast), box-shadow var(--transition-fast)',
    whiteSpace: 'nowrap',
    ...sizes[size],
    ...variants[variant],
    ...style
  };
  const onEnter = e => {
    if (disabled) return;
    if (variant === 'primary') e.currentTarget.style.background = 'var(--color-primary-hover)';
    if (variant === 'secondary' || variant === 'ghost') e.currentTarget.style.background = 'color-mix(in srgb, var(--color-primary) 8%, transparent)';
    if (variant === 'onDark') e.currentTarget.style.background = 'var(--cream-200)';
  };
  const onLeave = e => {
    if (disabled) return;
    e.currentTarget.style.background = variants[variant].background;
    e.currentTarget.style.transform = 'none';
  };
  const onDown = e => {
    if (!disabled) e.currentTarget.style.transform = 'scale(0.97)';
  };
  const onUp = e => {
    if (!disabled) e.currentTarget.style.transform = 'none';
  };
  const Tag = href ? 'a' : 'button';
  const tagProps = href ? {
    href
  } : {
    type,
    disabled
  };
  return /*#__PURE__*/React.createElement(Tag, _extends({}, tagProps, {
    onClick: onClick,
    onMouseEnter: onEnter,
    onMouseLeave: onLeave,
    onMouseDown: onDown,
    onMouseUp: onUp,
    style: base
  }, rest), iconLeft, children, iconRight);
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Button.jsx", error: String((e && e.message) || e) }); }

// components/core/Card.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Warm content card. White surface, soft radius, discreet warm shadow.
 */
function Card({
  children,
  tone = 'light',
  interactive = false,
  padding = 'var(--space-6)',
  style,
  ...rest
}) {
  const tones = {
    light: {
      background: 'var(--surface-card)',
      color: 'var(--text-primary)',
      border: '1px solid var(--border-soft)'
    },
    cream: {
      background: 'var(--surface-sunken)',
      color: 'var(--text-primary)',
      border: '1px solid transparent'
    },
    dark: {
      background: 'var(--surface-dark)',
      color: 'var(--text-on-dark)',
      border: '1px solid var(--border-on-dark)'
    },
    brand: {
      background: 'var(--surface-brand)',
      color: 'var(--text-on-brand)',
      border: '1px solid transparent'
    }
  };
  const [hover, setHover] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", _extends({
    onMouseEnter: () => interactive && setHover(true),
    onMouseLeave: () => interactive && setHover(false),
    style: {
      borderRadius: 'var(--radius-lg)',
      padding,
      boxShadow: hover ? 'var(--shadow-lg)' : 'var(--shadow-md)',
      transform: hover ? 'translateY(-3px)' : 'none',
      transition: 'transform var(--transition-base), box-shadow var(--transition-base)',
      ...tones[tone],
      ...style
    }
  }, rest), children);
}
Object.assign(__ds_scope, { Card });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Card.jsx", error: String((e && e.message) || e) }); }

// components/core/Divider.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Short bronze gradient divider. Decorative rule beneath titles/eyebrows.
 */
function Divider({
  width = 48,
  align = 'left',
  ornament = false,
  style,
  ...rest
}) {
  if (ornament) {
    return /*#__PURE__*/React.createElement("div", _extends({
      style: {
        display: 'flex',
        alignItems: 'center',
        gap: '12px',
        color: 'var(--bronze-300)',
        ...style
      }
    }, rest), /*#__PURE__*/React.createElement("span", {
      style: {
        flex: 1,
        height: '1px',
        background: 'var(--gradient-bronze)',
        opacity: 0.6
      }
    }), /*#__PURE__*/React.createElement("span", {
      style: {
        width: '6px',
        height: '6px',
        borderRadius: '50%',
        background: 'var(--bronze-400)',
        flex: 'none'
      }
    }), /*#__PURE__*/React.createElement("span", {
      style: {
        flex: 1,
        height: '1px',
        background: 'var(--gradient-bronze)',
        opacity: 0.6
      }
    }));
  }
  return /*#__PURE__*/React.createElement("div", _extends({
    style: {
      width: typeof width === 'number' ? `${width}px` : width,
      height: '2px',
      borderRadius: '2px',
      background: 'var(--gradient-bronze)',
      marginLeft: align === 'center' ? 'auto' : undefined,
      marginRight: align === 'center' ? 'auto' : undefined,
      ...style
    }
  }, rest));
}
Object.assign(__ds_scope, { Divider });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Divider.jsx", error: String((e && e.message) || e) }); }

// components/core/Eyebrow.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Uppercase eyebrow / section label with the signature bronze tick.
 */
function Eyebrow({
  children,
  onDark = false,
  align = 'left',
  style,
  ...rest
}) {
  return /*#__PURE__*/React.createElement("span", _extends({
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: '10px',
      fontFamily: 'var(--font-sans)',
      fontSize: 'var(--text-eyebrow)',
      fontWeight: 600,
      textTransform: 'uppercase',
      letterSpacing: 'var(--tracking-eyebrow)',
      color: onDark ? 'var(--bronze-300)' : 'var(--color-primary)',
      justifyContent: align === 'center' ? 'center' : 'flex-start',
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("span", {
    "aria-hidden": "true",
    style: {
      width: '24px',
      height: '2px',
      borderRadius: '2px',
      background: 'var(--gradient-bronze)',
      flex: 'none'
    }
  }), children);
}
Object.assign(__ds_scope, { Eyebrow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Eyebrow.jsx", error: String((e && e.message) || e) }); }

// components/core/Input.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Text input / field with optional label. Warm focus ring.
 */
function Input({
  label,
  type = 'text',
  placeholder,
  value,
  onChange,
  name,
  required,
  as = 'input',
  rows = 4,
  style,
  ...rest
}) {
  const [focus, setFocus] = React.useState(false);
  const fieldStyle = {
    fontFamily: 'var(--font-sans)',
    fontSize: 'var(--text-base)',
    color: 'var(--text-primary)',
    background: 'var(--surface-card)',
    border: `1px solid ${focus ? 'var(--color-primary)' : 'var(--border-strong)'}`,
    borderRadius: 'var(--radius-md)',
    padding: '12px 14px',
    width: '100%',
    boxSizing: 'border-box',
    outline: 'none',
    boxShadow: focus ? 'var(--ring-focus)' : 'none',
    transition: 'border-color var(--transition-fast), box-shadow var(--transition-fast)',
    resize: as === 'textarea' ? 'vertical' : undefined,
    ...style
  };
  const Field = as;
  return /*#__PURE__*/React.createElement("label", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: '6px',
      width: '100%'
    }
  }, label && /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sans)',
      fontSize: 'var(--text-sm)',
      fontWeight: 600,
      color: 'var(--text-secondary)'
    }
  }, label, required && /*#__PURE__*/React.createElement("span", {
    style: {
      color: 'var(--color-primary)'
    }
  }, " *")), /*#__PURE__*/React.createElement(Field, _extends({
    type: as === 'input' ? type : undefined,
    name: name,
    placeholder: placeholder,
    value: value,
    onChange: onChange,
    required: required,
    rows: as === 'textarea' ? rows : undefined,
    onFocus: () => setFocus(true),
    onBlur: () => setFocus(false),
    style: fieldStyle
  }, rest)));
}
Object.assign(__ds_scope, { Input });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Input.jsx", error: String((e && e.message) || e) }); }

// components/core/Stat.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Stat / proof point — large serif number over a label.
 * Used for "+23 anos", "+10.000 benefícios".
 */
function Stat({
  value,
  label,
  onDark = false,
  align = 'left',
  style,
  ...rest
}) {
  return /*#__PURE__*/React.createElement("div", _extends({
    style: {
      textAlign: align,
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-serif)',
      fontSize: 'clamp(2.5rem, 4vw, 3.5rem)',
      fontWeight: 600,
      lineHeight: 1,
      letterSpacing: '-0.01em',
      color: onDark ? 'var(--bronze-300)' : 'var(--color-primary)'
    }
  }, value), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-sans)',
      fontSize: 'var(--text-sm)',
      fontWeight: 500,
      marginTop: '8px',
      color: onDark ? 'var(--ink-100)' : 'var(--text-secondary)'
    }
  }, label));
}
Object.assign(__ds_scope, { Stat });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Stat.jsx", error: String((e && e.message) || e) }); }

// ui_kits/website/Areas.jsx
try { (() => {
function Areas() {
  const {
    Card,
    Eyebrow,
    Divider
  } = window.DesignSystem_f6e542;
  const {
    Container
  } = window;
  const icons = {
    elderly: /*#__PURE__*/React.createElement("path", {
      d: "M12 6a2 2 0 100-4 2 2 0 000 4zm-1 2l-3 2 1 7m5-9l3 2-1 4m-4-6v6l-2 7m4-13v6l2 7"
    }),
    shield: /*#__PURE__*/React.createElement("path", {
      d: "M12 2l8 3v6c0 5-3.5 8.5-8 11-4.5-2.5-8-6-8-11V5l8-3z"
    }),
    doc: /*#__PURE__*/React.createElement("path", {
      d: "M7 3h7l4 4v14H7zM14 3v4h4M9 12h6M9 16h6"
    }),
    heart: /*#__PURE__*/React.createElement("path", {
      d: "M12 20s-7-4.5-7-10a4 4 0 017-2.6A4 4 0 0119 10c0 5.5-7 10-7 10z"
    }),
    refresh: /*#__PURE__*/React.createElement("path", {
      d: "M4 12a8 8 0 0114-5l2-2M20 12a8 8 0 01-14 5l-2 2M17 5h3V2M7 19H4v3"
    }),
    family: /*#__PURE__*/React.createElement("path", {
      d: "M7 10a2 2 0 100-4 2 2 0 000 4zm10 0a2 2 0 100-4 2 2 0 000 4zM3 20c0-3 1.8-5 4-5s4 2 4 5m2 0c0-3 1.8-5 4-5s4 2 4 5"
    })
  };
  const items = [{
    i: 'elderly',
    t: 'Aposentadorias',
    d: 'Por idade, tempo de contribuição, especial e rural.'
  }, {
    i: 'shield',
    t: 'Auxílios',
    d: 'Auxílio-doença, auxílio-acidente e benefícios por incapacidade.'
  }, {
    i: 'heart',
    t: 'BPC / LOAS',
    d: 'Benefício assistencial ao idoso e à pessoa com deficiência.'
  }, {
    i: 'family',
    t: 'Pensão por morte',
    d: 'Garantia de renda aos dependentes do segurado.'
  }, {
    i: 'refresh',
    t: 'Revisões',
    d: 'Revisão de benefícios concedidos com valor incorreto.'
  }, {
    i: 'doc',
    t: 'Planejamento',
    d: 'Análise do melhor momento e da melhor regra para você.'
  }];
  return /*#__PURE__*/React.createElement("section", {
    style: {
      background: 'var(--surface-card)',
      padding: 'var(--space-9) 0'
    }
  }, /*#__PURE__*/React.createElement(Container, null, /*#__PURE__*/React.createElement("div", {
    style: {
      maxWidth: '600px'
    }
  }, /*#__PURE__*/React.createElement(Eyebrow, null, "\xC1reas de atua\xE7\xE3o"), /*#__PURE__*/React.createElement("h2", {
    style: {
      fontFamily: 'var(--font-serif)',
      fontWeight: 600,
      fontSize: 'var(--text-h2)',
      color: 'var(--bronze-900)',
      margin: '16px 0 0',
      lineHeight: 1.1
    }
  }, "Especialistas no que mais importa para a sua vida"), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: '18px'
    }
  }, /*#__PURE__*/React.createElement(Divider, {
    width: 64
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: 'repeat(3, 1fr)',
      gap: '20px',
      marginTop: 'var(--space-7)'
    }
  }, items.map(it => /*#__PURE__*/React.createElement(Card, {
    key: it.t,
    interactive: true
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: '46px',
      height: '46px',
      borderRadius: '12px',
      background: 'color-mix(in srgb, var(--bronze-600) 10%, transparent)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      marginBottom: '16px'
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: "24",
    height: "24",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "var(--color-primary)",
    strokeWidth: "1.6",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }, icons[it.i])), /*#__PURE__*/React.createElement("h3", {
    style: {
      fontFamily: 'var(--font-serif)',
      fontWeight: 600,
      fontSize: '22px',
      color: 'var(--bronze-900)',
      margin: '0 0 8px'
    }
  }, it.t), /*#__PURE__*/React.createElement("p", {
    style: {
      fontFamily: 'var(--font-sans)',
      fontSize: '14px',
      lineHeight: 1.6,
      color: 'var(--text-secondary)',
      margin: 0
    }
  }, it.d))))));
}
Object.assign(window, {
  Areas
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/website/Areas.jsx", error: String((e && e.message) || e) }); }

// ui_kits/website/ContactFooter.jsx
try { (() => {
function ContactFooter() {
  const {
    Eyebrow,
    Input,
    Button,
    Divider
  } = window.DesignSystem_f6e542;
  const {
    Container
  } = window;
  const [sent, setSent] = React.useState(false);
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("section", {
    style: {
      background: 'var(--surface-brand)',
      padding: 'var(--space-9) 0',
      color: 'var(--text-on-brand)'
    }
  }, /*#__PURE__*/React.createElement(Container, {
    style: {
      display: 'grid',
      gridTemplateColumns: '1fr 1fr',
      gap: 'var(--space-8)',
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(Eyebrow, {
    onDark: true
  }, "Fale conosco"), /*#__PURE__*/React.createElement("h2", {
    style: {
      fontFamily: 'var(--font-serif)',
      fontWeight: 600,
      fontSize: 'var(--text-h2)',
      color: 'var(--cream-100)',
      margin: '16px 0 16px',
      lineHeight: 1.1
    }
  }, "Descubra, sem compromisso, o seu direito"), /*#__PURE__*/React.createElement("p", {
    style: {
      fontFamily: 'var(--font-sans)',
      fontSize: 'var(--text-lead)',
      lineHeight: 1.55,
      color: 'var(--ink-100)',
      opacity: 0.85,
      margin: '0 0 28px',
      maxWidth: '38ch'
    }
  }, "Conte o seu caso. Um especialista entra em contato para uma an\xE1lise gratuita."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gap: '14px'
    }
  }, [['Telefone / WhatsApp', '(48) 9 0000-0000'], ['E-mail', 'contato@ramonantonio.adv.br'], ['Endereço', 'Tubarão · Santa Catarina']].map(([k, v]) => /*#__PURE__*/React.createElement("div", {
    key: k,
    style: {
      display: 'flex',
      gap: '12px',
      alignItems: 'baseline'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sans)',
      fontSize: '11px',
      letterSpacing: '0.18em',
      textTransform: 'uppercase',
      color: 'var(--bronze-300)',
      minWidth: '150px'
    }
  }, k), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sans)',
      fontSize: '15px',
      color: 'var(--cream-100)'
    }
  }, v))))), /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--surface-card)',
      borderRadius: 'var(--radius-lg)',
      padding: 'var(--space-6)',
      boxShadow: 'var(--shadow-lg)'
    }
  }, sent ? /*#__PURE__*/React.createElement("div", {
    style: {
      textAlign: 'center',
      padding: '40px 20px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: '56px',
      height: '56px',
      borderRadius: '50%',
      margin: '0 auto 18px',
      background: 'color-mix(in srgb, var(--bronze-600) 12%, transparent)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center'
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: "28",
    height: "28",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "var(--color-primary)",
    strokeWidth: "2",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M20 6L9 17l-5-5"
  }))), /*#__PURE__*/React.createElement("h3", {
    style: {
      fontFamily: 'var(--font-serif)',
      fontWeight: 600,
      fontSize: '24px',
      color: 'var(--bronze-900)',
      margin: '0 0 8px'
    }
  }, "Recebemos o seu contato"), /*#__PURE__*/React.createElement("p", {
    style: {
      fontFamily: 'var(--font-sans)',
      fontSize: '14px',
      color: 'var(--text-secondary)',
      margin: 0
    }
  }, "Em breve um especialista falar\xE1 com voc\xEA.")) : /*#__PURE__*/React.createElement("form", {
    onSubmit: e => {
      e.preventDefault();
      setSent(true);
    },
    style: {
      display: 'grid',
      gap: '16px'
    }
  }, /*#__PURE__*/React.createElement(Input, {
    label: "Nome completo",
    placeholder: "Seu nome",
    required: true
  }), /*#__PURE__*/React.createElement(Input, {
    label: "Telefone / WhatsApp",
    placeholder: "(48) 9 0000-0000",
    required: true
  }), /*#__PURE__*/React.createElement(Input, {
    label: "Como podemos ajudar?",
    as: "textarea",
    rows: 3,
    placeholder: "Conte brevemente o seu caso"
  }), /*#__PURE__*/React.createElement(Button, {
    type: "submit",
    variant: "primary",
    size: "lg",
    style: {
      width: '100%'
    }
  }, "Solicitar an\xE1lise gratuita"))))), /*#__PURE__*/React.createElement("footer", {
    style: {
      background: 'var(--dark-900)',
      padding: 'var(--space-7) 0',
      color: 'var(--ink-100)'
    }
  }, /*#__PURE__*/React.createElement(Container, {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      flexWrap: 'wrap',
      gap: '20px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '12px'
    }
  }, /*#__PURE__*/React.createElement("img", {
    src: "../../assets/monogram.png",
    alt: "",
    style: {
      height: '36px',
      width: '36px',
      objectFit: 'cover',
      borderRadius: '8px'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      lineHeight: 1.1
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-serif)',
      fontWeight: 600,
      fontSize: '16px',
      color: 'var(--cream-100)'
    }
  }, "Ramon Antonio Advogados"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-sans)',
      fontSize: '12px',
      color: 'var(--bronze-300)'
    }
  }, "Direito Previdenci\xE1rio \xB7 @ramonantonioadvogados"))), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sans)',
      fontSize: '12px',
      color: 'var(--text-secondary)'
    }
  }, "\xA9 2026 \xB7 Tubar\xE3o/SC \xB7 OAB/SC"))));
}
Object.assign(window, {
  ContactFooter
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/website/ContactFooter.jsx", error: String((e && e.message) || e) }); }

// ui_kits/website/Header.jsx
try { (() => {
function Header() {
  const {
    Button
  } = window.DesignSystem_f6e542;
  const {
    Container
  } = window;
  const [open, setOpen] = React.useState(false);
  const links = ['Áreas de atuação', 'Sobre nós', 'Como funciona', 'Conteúdo', 'Contato'];
  return /*#__PURE__*/React.createElement("header", {
    style: {
      position: 'sticky',
      top: 0,
      zIndex: 50,
      background: 'rgba(250,243,232,0.86)',
      backdropFilter: 'blur(10px)',
      borderBottom: '1px solid var(--border-soft)'
    }
  }, /*#__PURE__*/React.createElement(Container, {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      height: '76px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '12px'
    }
  }, /*#__PURE__*/React.createElement("img", {
    src: "../../assets/monogram.png",
    alt: "",
    style: {
      height: '40px',
      width: '40px',
      objectFit: 'cover',
      borderRadius: '8px'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      lineHeight: 1.05
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-serif)',
      fontWeight: 600,
      fontSize: '20px',
      color: 'var(--bronze-900)'
    }
  }, "Ramon Antonio"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-sans)',
      fontSize: '9px',
      letterSpacing: '0.28em',
      textTransform: 'uppercase',
      color: 'var(--bronze-400)'
    }
  }, "Advogados"))), /*#__PURE__*/React.createElement("nav", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '28px'
    },
    className: "ra-desktop-nav"
  }, links.map(l => /*#__PURE__*/React.createElement("a", {
    key: l,
    href: "#",
    style: {
      fontFamily: 'var(--font-sans)',
      fontSize: '14px',
      fontWeight: 500,
      color: 'var(--text-secondary)',
      textDecoration: 'none'
    },
    onMouseEnter: e => e.currentTarget.style.color = 'var(--color-primary)',
    onMouseLeave: e => e.currentTarget.style.color = 'var(--text-secondary)'
  }, l))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: '12px'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "sm",
    iconLeft: /*#__PURE__*/React.createElement("svg", {
      width: "15",
      height: "15",
      viewBox: "0 0 24 24",
      fill: "currentColor"
    }, /*#__PURE__*/React.createElement("path", {
      d: "M.057 24l1.687-6.163a11.867 11.867 0 01-1.587-5.946C.16 5.335 5.495 0 12.05 0a11.82 11.82 0 018.413 3.488 11.82 11.82 0 013.48 8.414c-.003 6.557-5.338 11.892-11.893 11.892a11.9 11.9 0 01-5.688-1.448L.057 24z"
    }))
  }, "WhatsApp"))));
}
Object.assign(window, {
  Header
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/website/Header.jsx", error: String((e && e.message) || e) }); }

// ui_kits/website/Hero.jsx
try { (() => {
function Hero() {
  const {
    Button,
    Eyebrow,
    Badge,
    Stat,
    Divider
  } = window.DesignSystem_f6e542;
  const {
    Container,
    Photo
  } = window;
  return /*#__PURE__*/React.createElement("section", {
    style: {
      background: 'var(--surface-page)',
      paddingTop: 'var(--space-9)',
      paddingBottom: 'var(--space-9)'
    }
  }, /*#__PURE__*/React.createElement(Container, {
    style: {
      display: 'grid',
      gridTemplateColumns: '1.1fr 0.9fr',
      gap: 'var(--space-8)',
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(Eyebrow, null, "Direito Previdenci\xE1rio \xB7 INSS"), /*#__PURE__*/React.createElement("h1", {
    style: {
      fontFamily: 'var(--font-serif)',
      fontWeight: 600,
      fontSize: 'var(--text-display)',
      lineHeight: 1.04,
      letterSpacing: '-0.01em',
      color: 'var(--bronze-900)',
      margin: '20px 0 0'
    }
  }, "O benef\xEDcio que \xE9 seu,", /*#__PURE__*/React.createElement("br", null), "conquistado ao seu lado."), /*#__PURE__*/React.createElement("p", {
    style: {
      fontFamily: 'var(--font-sans)',
      fontSize: 'var(--text-lead)',
      lineHeight: 1.55,
      color: 'var(--text-secondary)',
      maxWidth: '34ch',
      margin: '20px 0 0'
    }
  }, "Especialistas em aposentadorias, aux\xEDlios, BPC/LOAS e revis\xF5es. Voc\xEA acompanha cada etapa do seu processo, com transpar\xEAncia."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: '14px',
      marginTop: 'var(--space-6)',
      flexWrap: 'wrap'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "lg"
  }, "Fale com um especialista"), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    size: "lg"
  }, "Conhe\xE7a as \xE1reas")), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--space-7)',
      marginTop: 'var(--space-8)'
    }
  }, /*#__PURE__*/React.createElement(Stat, {
    value: "+23",
    label: "anos de experi\xEAncia"
  }), /*#__PURE__*/React.createElement(Stat, {
    value: "+10.000",
    label: "benef\xEDcios conquistados"
  }), /*#__PURE__*/React.createElement(Stat, {
    value: "SC",
    label: "atua\xE7\xE3o em todo o estado"
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement(Photo, {
    ratio: "4 / 5"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      bottom: '18px',
      left: '18px'
    }
  }, /*#__PURE__*/React.createElement(Badge, null, "Tubar\xE3o \xB7 Santa Catarina")))));
}
Object.assign(window, {
  Hero
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/website/Hero.jsx", error: String((e && e.message) || e) }); }

// ui_kits/website/Process.jsx
try { (() => {
function Process() {
  const {
    Eyebrow,
    Badge
  } = window.DesignSystem_f6e542;
  const {
    Container,
    Photo
  } = window;
  const steps = [{
    n: '01',
    t: 'Análise gratuita',
    d: 'Avaliamos o seu caso e explicamos, sem juridiquês, o seu direito.'
  }, {
    n: '02',
    t: 'Estratégia',
    d: 'Definimos a melhor regra e o melhor momento para o seu benefício.'
  }, {
    n: '03',
    t: 'Protocolo',
    d: 'Damos entrada no pedido e cuidamos de toda a documentação.'
  }, {
    n: '04',
    t: 'Acompanhamento',
    d: 'Você acompanha cada etapa, com atualizações transparentes.'
  }];
  return /*#__PURE__*/React.createElement("section", {
    style: {
      background: 'var(--surface-dark)',
      padding: 'var(--space-9) 0',
      color: 'var(--text-on-dark)'
    }
  }, /*#__PURE__*/React.createElement(Container, {
    style: {
      display: 'grid',
      gridTemplateColumns: '0.85fr 1.15fr',
      gap: 'var(--space-8)',
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement(Photo, {
    ratio: "4 / 5",
    label: "Atendimento humano \xB7 v\xEDdeo"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      top: '18px',
      right: '18px'
    }
  }, /*#__PURE__*/React.createElement(Badge, null, "Transpar\xEAncia total"))), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(Eyebrow, {
    onDark: true
  }, "Como funciona"), /*#__PURE__*/React.createElement("h2", {
    style: {
      fontFamily: 'var(--font-serif)',
      fontWeight: 600,
      fontSize: 'var(--text-h2)',
      color: 'var(--cream-100)',
      margin: '16px 0 28px',
      lineHeight: 1.1
    }
  }, "Voc\xEA acompanha cada etapa, do in\xEDcio ao benef\xEDcio"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gap: '4px'
    }
  }, steps.map((s, idx) => /*#__PURE__*/React.createElement("div", {
    key: s.n,
    style: {
      display: 'flex',
      gap: '20px',
      padding: '18px 0',
      borderTop: idx === 0 ? 'none' : '1px solid var(--border-on-dark)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-serif)',
      fontSize: '28px',
      fontWeight: 600,
      color: 'var(--bronze-300)',
      lineHeight: 1,
      minWidth: '44px'
    }
  }, s.n), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("h3", {
    style: {
      fontFamily: 'var(--font-sans)',
      fontWeight: 600,
      fontSize: '17px',
      color: 'var(--cream-100)',
      margin: '0 0 4px'
    }
  }, s.t), /*#__PURE__*/React.createElement("p", {
    style: {
      fontFamily: 'var(--font-sans)',
      fontSize: '14px',
      lineHeight: 1.6,
      color: 'var(--ink-100)',
      opacity: 0.78,
      margin: 0
    }
  }, s.d))))))));
}
Object.assign(window, {
  Process
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/website/Process.jsx", error: String((e && e.message) || e) }); }

// ui_kits/website/Shared.jsx
try { (() => {
/* Shared photo-placeholder + section helpers for the website UI kit.
   Real brand imagery: warm B&W portraits that gain color. These stand in. */
const NS = window.DesignSystem_f6e542;
function Photo({
  label = 'Retrato profissional · P&B',
  ratio = '3 / 4',
  rounded = 'var(--radius-lg)',
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      aspectRatio: ratio,
      borderRadius: rounded,
      overflow: 'hidden',
      background: 'linear-gradient(150deg, #2a1d12 0%, #5c3c22 55%, #754d2a 100%)',
      boxShadow: 'var(--shadow-lg)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      opacity: 0.16,
      backgroundImage: 'radial-gradient(rgba(245,230,204,0.5) 1px, transparent 1px)',
      backgroundSize: '4px 4px'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      gap: '10px',
      color: 'var(--bronze-300)'
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: "40",
    height: "40",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "1.4",
    opacity: "0.7"
  }, /*#__PURE__*/React.createElement("circle", {
    cx: "12",
    cy: "8",
    r: "4"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M4 21c0-4 3.6-7 8-7s8 3 8 7"
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sans)',
      fontSize: '11px',
      letterSpacing: '0.12em',
      textTransform: 'uppercase',
      opacity: 0.85
    }
  }, label)));
}
function Container({
  children,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      maxWidth: 'var(--container-max)',
      margin: '0 auto',
      padding: '0 var(--container-pad)',
      ...style
    }
  }, children);
}
Object.assign(window, {
  Photo,
  Container,
  NS
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/website/Shared.jsx", error: String((e && e.message) || e) }); }

__ds_ns.Badge = __ds_scope.Badge;

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Card = __ds_scope.Card;

__ds_ns.Divider = __ds_scope.Divider;

__ds_ns.Eyebrow = __ds_scope.Eyebrow;

__ds_ns.Input = __ds_scope.Input;

__ds_ns.Stat = __ds_scope.Stat;

})();
