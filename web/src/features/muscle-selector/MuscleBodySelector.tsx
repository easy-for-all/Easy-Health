"use client";

import { createElement } from "react";
import {
  BODY_HEAD,
  BODY_SHAPES,
  MUSCLE_GROUPS,
  type BodyView,
  type MuscleGroupId,
} from "./muscle-data";
import "./muscle-selector.css";

export function MuscleBodySelector({
  view,
  isSelected,
  onToggle,
}: {
  view: BodyView;
  isSelected: (id: MuscleGroupId) => boolean;
  onToggle: (id: MuscleGroupId) => void;
}) {
  const head = BODY_HEAD[view];
  const shapes = BODY_SHAPES[view];

  return (
    <div className="ms-body-wrap">
      <svg
        className="ms-body-svg"
        viewBox="0 0 120 280"
        xmlns="http://www.w3.org/2000/svg"
        role="group"
        aria-label={`Corpo, vista ${view === "front" ? "frontal" : "traseira"}`}
      >
        <circle className="ms-head" cx={head.cx} cy={head.cy} r={head.r} aria-hidden />
        {shapes.map((shape, index) => {
          const on = isSelected(shape.group);
          const name = MUSCLE_GROUPS[shape.group].name_pt;
          return createElement(shape.tag, {
            key: `${shape.group}-${index}`,
            className: `ms-region${on ? " sel" : ""}`,
            role: "button",
            tabIndex: 0,
            "aria-pressed": on,
            "aria-label": `${name}, ${on ? "selecionado" : "não selecionado"}`,
            onClick: () => onToggle(shape.group),
            onKeyDown: (e: React.KeyboardEvent) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault();
                onToggle(shape.group);
              }
            },
            ...shape.attrs,
          });
        })}
      </svg>
    </div>
  );
}
