class PersonalAccessPolicy
  def initialize(personal, client)
    @personal = personal
    @client = client
    @relationship = find_active_relationship
    @permissions = @relationship&.client_permission
  end

  def authorized?
    @relationship.present?
  end

  def can_view?(permission_key)
    return false unless authorized?
    @permissions&.allowed?(permission_key) || false
  end

  def relationship
    @relationship
  end

  private

  def find_active_relationship
    PersonalClientRelationship.find_by(
      personal: @personal,
      client: @client,
      status: "active"
    )
  end
end
