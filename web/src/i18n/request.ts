import { getRequestConfig } from "next-intl/server";
import { cookies } from "next/headers";
import ptBR from "../../messages/pt-BR.json";
import enUS from "../../messages/en-US.json";

const messages = { "pt-BR": ptBR, "en-US": enUS };

export default getRequestConfig(async () => {
  const locale = (await cookies()).get("locale")?.value ?? "pt-BR";
  const isSupported = locale === "pt-BR" || locale === "en-US";
  const safeLocale = isSupported ? locale : "pt-BR";

  return {
    locale: safeLocale,
    messages: messages[safeLocale as keyof typeof messages],
  };
});
