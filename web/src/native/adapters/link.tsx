"use client";

// Adapter de next/link. Mantém os 49 call sites existentes intactos.
//
// Um <a href> de verdade dentro do WebView faria o shell tentar carregar o
// documento a partir de capacitor://localhost/<rota> — que não existe como
// arquivo no IPA — e a tela ficaria branca. Então o href continua sendo
// renderizado (acessibilidade, menu de contexto, aparência), mas a navegação
// é interceptada e entregue ao roteador client-side.

import { forwardRef, type AnchorHTMLAttributes, type MouseEvent } from "react";
import { useNativeRouter } from "../router/router-context";

type LinkProps = AnchorHTMLAttributes<HTMLAnchorElement> & {
  href: string;
  replace?: boolean;
  // Props do Next que não têm significado sem servidor. Aceitas e descartadas
  // para que nenhum call site precise mudar.
  prefetch?: boolean | null;
  scroll?: boolean;
  shallow?: boolean;
  passHref?: boolean;
  legacyBehavior?: boolean;
};

function isExternal(href: string): boolean {
  return /^(https?:)?\/\//i.test(href) || /^[a-z][a-z0-9+.-]*:/i.test(href);
}

export const Link = forwardRef<HTMLAnchorElement, LinkProps>(function Link(
  { href, replace, prefetch, scroll, shallow, passHref, legacyBehavior, onClick, target, children, ...rest },
  ref
) {
  const router = useNativeRouter();

  function handleClick(event: MouseEvent<HTMLAnchorElement>) {
    onClick?.(event);
    if (event.defaultPrevented) return;

    // Deixa passar o que o usuário pediu explicitamente para abrir de outro
    // jeito: nova aba, modificadores, botão do meio, link externo.
    if (target && target !== "_self") return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    if (event.button !== 0) return;
    if (isExternal(href)) return;

    event.preventDefault();
    if (replace) router.replace(href);
    else router.push(href);
  }

  return (
    <a ref={ref} href={href} target={target} onClick={handleClick} {...rest}>
      {children}
    </a>
  );
});

export default Link;
