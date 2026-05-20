import Link from "next/link";

export function FeatureCard({
  icon,
  title,
  description,
  href,
}: {
  icon: string;
  title: string;
  description: string;
  href: string;
}) {
  return (
    <Link
      href={href}
      className="group block rounded-2xl border border-gray-100 bg-white p-6 transition hover:border-primary-200 hover:shadow-sm"
    >
      <p className="text-3xl">{icon}</p>
      <h3 className="mt-4 font-semibold text-gray-900">{title}</h3>
      <p className="mt-2 text-sm leading-relaxed text-gray-500">{description}</p>
      <p className="mt-4 text-sm font-medium text-primary-600 group-hover:underline">
        Saiba mais →
      </p>
    </Link>
  );
}
