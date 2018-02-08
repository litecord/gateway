defmodule Member do
  import Ecto.Query, only: [from: 2]
  alias Gateway.Repo

  @spec get_member_data(String.t) :: [String.t]
  def get_member_data(guild_id) do
    query = from m in Gateway.Member,
      where: m.guild_id == ^guild_id

    Repo.all(query)
  end

  @spec get_roles(String.t, String.t) :: [String.t]
  def get_roles(guild_id, user_id) do
    query = from mr in Gateway.MemberRole,
      where: mr.guild_id == ^guild_id and mr.user_id == ^user_id,
      select: mr.role_id

    Repo.all(query)
  end
end
