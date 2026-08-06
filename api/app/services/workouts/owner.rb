module Workouts
  # Quem é dono de um plano: um usuário, ou uma instalação que ainda não tem
  # conta. Existe para que a geração e a serialização parem de perguntar
  # "current_user" e passem a perguntar "dono" — a única diferença real entre os
  # dois fluxos.
  #
  # NÃO é uma abstração para o app inteiro. Só cobre o que o caminho anônimo
  # precisa: plano ativo, sessões, favoritos, histórico e perfil. Tudo o mais
  # (comunidade, streak, PRs, coach) continua exigindo usuário, porque tudo o
  # mais realmente exige.
  module Owner
    module_function

    def for(user: nil, installation: nil)
      return UserOwner.new(user) if user
      return InstallationOwner.new(installation) if installation

      raise ArgumentError, "owner requires a user or an app_installation"
    end
  end
end
