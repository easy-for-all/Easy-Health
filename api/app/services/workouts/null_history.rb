module Workouts
  # Um histórico que responde "nunca aconteceu" a tudo.
  #
  # Preferido a espalhar `owner.anonymous? ? nil : history.x` por cada campo do
  # serializer: ali uma omissão vira NoMethodError em produção, aqui o campo
  # novo que ninguém adicionou vira NoMethodError no primeiro teste.
  class NullHistory
    def last_execution_label = nil
    def last_completed_at = nil
    def last_used_weight = nil
    def suggested_starting_weight = nil
    def progression_reason = nil
  end
end
