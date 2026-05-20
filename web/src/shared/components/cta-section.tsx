import Link from "next/link";

export function CTASection({
  title,
  subtitle,
  ctaText,
  ctaHref,
}: {
  title: string;
  subtitle: string;
  ctaText: string;
  ctaHref: string;
}) {
  return (
    <section className="bg-primary-500 py-20">
      <div className="mx-auto max-w-5xl px-6 text-center">
        <h2 className="text-3xl font-bold text-white">{title}</h2>
        <p className="mx-auto mt-4 max-w-xl text-lg text-primary-100">{subtitle}</p>
        <Link
          href={ctaHref}
          className="mt-8 inline-block rounded-xl bg-white px-8 py-4 text-base font-semibold text-primary-600 hover:bg-primary-50"
        >
          {ctaText}
        </Link>
      </div>
    </section>
  );
}
