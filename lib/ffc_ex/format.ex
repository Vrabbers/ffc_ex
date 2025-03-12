defmodule FfcEx.Format do
  def uname(uid) when is_integer(uid) do
    {:ok, user} = Nostrum.Api.User.get(uid)
    uname(user)
  end

  def uname(user) do
    case user.discriminator do
      "0" -> user.username
      x -> "#{user.username}\##{x}"
    end
  end
end
