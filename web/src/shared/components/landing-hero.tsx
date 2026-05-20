import Link from "next/link";

export function LandingHero({
  title,
  subtitle,
  ctaText,
  ctaHref,
  secondaryText,
  secondaryHref,
}: {
  title: string;
  subtitle: string;
  ctaText: string;
  ctaHref: string;
  secondaryText?: string;
  secondaryHref?: string;
}) {
  return (
    <section className="mx-auto max-w-5xl px-6 py-20 text-center">
      <h1 className="text-4xl font-bold leading-tight text-gray-900 sm:text-5xl">{title}</h1>
      <p className="mx-auto mt-6 max-w-xl text-lg text-gray-500">{subtitle}</p>
      <div className="mt-8 flex flex-col items-center gap-3 sm:flex-row sm:justify-center">
        <Link
          href={ctaHref}
          className="w-full rounded-xl bg-primary-500 px-8 py-4 text-base font-semibold text-white hover:bg-primary-600 sm:w-auto"
        >
          {ctaText}
        </Link>
        {secondaryText && secondaryHref && (
          <Link
            href={secondaryHref}
            className="w-full rounded-xl border border-gray-200 px-8 py-4 text-base font-semibold text-gray-700 hover:bg-gray-50 sm:w-auto"
          >
            {secondaryText}
          </Link>
        )}
      </div>
    </section>
  );
}
