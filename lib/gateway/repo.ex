defmodule Gateway.Repo do
  use Ecto.Repo, otp_app: :gateway
end

defmodule Gateway.User do
  use Ecto.Schema

  schema "users" do
    # field :id, :string
    field :username, :string
    field :discriminator, :string
    field :avatar, :string

    field :bot, :boolean
    field :mfa_enabled, :boolean
    field :flags, :integer
    field :verified, :boolean
    field :email, :string
    field :phone, :string

    field :password_hash, :string
    field :password_salt, :string
    
  end
end
