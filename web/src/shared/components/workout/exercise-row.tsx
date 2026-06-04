"use client";

import Image from "next/image";
import "./workout-ui.css";

type ExerciseRowProps = {
  name: string;
  sub?: string;
  imageUrl?: string | null;
  favorited?: boolean;
  onFavorite?: () => void;
  children?: React.ReactNode;
};

export function ExerciseRow({ name, sub, imageUrl, favorited, onFavorite, children }: ExerciseRowProps) {
  return (
    <div className="exercise-row">
      <div className="er-thumb">
        {imageUrl ? (
          <Image src={imageUrl} alt={name} fill sizes="54px" style={{ objectFit: "cover" }} />
        ) : (
          <div className="media-ph" style={{ width: "100%", height: "100%" }}>
            <span className="mph-label">foto</span>
          </div>
        )}
      </div>
      <div className="er-info">
        <b>{name}</b>
        {sub && <div className="er-sub">{sub}</div>}
      </div>
      {onFavorite && (
        <button
          className={`er-fav ${favorited ? "on" : ""}`}
          onClick={onFavorite}
          aria-label={favorited ? "Remover dos favoritos" : "Adicionar aos favoritos"}
        >
          <svg viewBox="0 0 24 24">
            <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
          </svg>
        </button>
      )}
      {children}
    </div>
  );
}
