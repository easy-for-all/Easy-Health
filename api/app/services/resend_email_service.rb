require "net/http"
require "json"

class ResendEmailService
  RESEND_API_URL = "https://api.resend.com/emails"
  FROM_ADDRESS   = "EasyHealth <noreply@easyhealth.art>"

  def self.send_password_reset(to:, reset_link:)
    payload = {
      from:    FROM_ADDRESS,
      to:      [ to ],
      subject: "Redefinição de senha - EasyHealth",
      html:    html_body(reset_link),
      text:    text_body(reset_link)
    }

    uri     = URI(RESEND_API_URL)
    http    = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
    req["Authorization"] = "Bearer #{ENV.fetch("RESEND_API_KEY")}"
    req.body = payload.to_json

    response = http.request(req)
    response.is_a?(Net::HTTPSuccess)
  rescue => e
    Rails.logger.error("[ResendEmailService] Failed to send email: #{e.class}")
    false
  end

  private

  def self.html_body(reset_link)
    <<~HTML
      <!DOCTYPE html>
      <html lang="pt-BR">
      <head><meta charset="UTF-8"></head>
      <body style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;color:#1f2937;">
        <h2 style="margin-bottom:8px;">Easy Health</h2>
        <p>Olá,</p>
        <p>Recebemos uma solicitação para redefinir sua senha no EasyHealth.</p>
        <p>Clique no botão abaixo para criar uma nova senha:</p>
        <a href="#{reset_link}"
           style="display:inline-block;margin:16px 0;padding:12px 24px;background:#4f7cff;color:#fff;
                  text-decoration:none;border-radius:8px;font-weight:600;">
          Redefinir minha senha
        </a>
        <p style="color:#6b7280;font-size:13px;">Este link é válido por 30 minutos.</p>
        <p style="color:#6b7280;font-size:13px;">Se você não solicitou esta alteração, ignore este e-mail.</p>
        <p>Equipe EasyHealth</p>
      </body>
      </html>
    HTML
  end

  def self.text_body(reset_link)
    <<~TEXT
      Olá,

      Recebemos uma solicitação para redefinir sua senha no EasyHealth.

      Acesse o link abaixo para criar uma nova senha:
      #{reset_link}

      Este link é válido por 30 minutos.

      Se você não solicitou esta alteração, ignore este e-mail.

      Equipe EasyHealth
    TEXT
  end
end
