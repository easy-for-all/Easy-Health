"use client";

// Adapter de next/image.
//
// O otimizador de imagem do Next é um serviço em runtime; num bundle local não
// existe servidor para servi-lo. Os assets já são estáticos e servidos de
// dentro do IPA, então <img> é o comportamento correto aqui — não um
// downgrade. As props exclusivas do Next são absorvidas para que os 6 call
// sites existentes não precisem mudar.

import type { CSSProperties, ImgHTMLAttributes } from "react";

type ImageProps = Omit<ImgHTMLAttributes<HTMLImageElement>, "src" | "width" | "height"> & {
  src: string | { src: string };
  alt: string;
  width?: number | string;
  height?: number | string;
  fill?: boolean;
  priority?: boolean;
  quality?: number;
  placeholder?: string;
  blurDataURL?: string;
  unoptimized?: boolean;
  sizes?: string;
  loader?: unknown;
};

export function Image({
  src,
  alt,
  width,
  height,
  fill,
  priority,
  quality,
  placeholder,
  blurDataURL,
  unoptimized,
  sizes,
  loader,
  style,
  ...rest
}: ImageProps) {
  const resolved = typeof src === "string" ? src : src?.src;

  // fill posiciona a imagem para preencher o ancestral relativo, que é o que o
  // next/image faz. Reproduzido para não quebrar o layout de quem usa.
  const fillStyle: CSSProperties = fill
    ? { position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }
    : {};

  return (
    <img
      src={resolved}
      alt={alt}
      width={fill ? undefined : width}
      height={fill ? undefined : height}
      sizes={sizes}
      loading={priority ? "eager" : "lazy"}
      decoding="async"
      style={{ ...fillStyle, ...style }}
      {...rest}
    />
  );
}

export default Image;
