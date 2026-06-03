class PersonalInviteService
  def initialize(personal)
    @personal = personal
  end

  def call
    code = generate_unique_code

    PersonalClientRelationship.create!(
      personal: @personal,
      status: "invited",
      invitation_code: code,
      invitation_expires_at: PersonalClientRelationship::INVITATION_TTL.from_now,
      invitation_sent_at: Time.current
    )

    code
  rescue ActiveRecord::RecordInvalid => e
    raise e
  end

  private

  def generate_unique_code
    loop do
      code = SecureRandom.alphanumeric(16).upcase
      break code unless PersonalClientRelationship.exists?(invitation_code: code)
    end
  end
end
