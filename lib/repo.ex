defmodule Gateway.Repo do
  use Ecto.Repo, otp_app: :gateway
end

defmodule Gateway.User do
  use Ecto.Schema

  # @primary_key {:id, :string}
  @primary_key false

  schema "users" do
    field :id, :string
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

defmodule Gateway.Guild do
  use Ecto.Schema

  # @primary_key {:id, :string}
  @primary_key false

  schema "guilds" do
    field :id, :string
    field :name, :string
    field :icon, :string
    field :splash, :string
    field :owner_id, :string

    field :region, :string
    field :afk_channel_id, :string
    field :afk_timeout, :integer

    field :verification_level, :integer
    field :default_message_notifications, :integer
    field :explicit_content_filter, :integer
    field :mfa_level, :integer

    field :features, :string
  end
end
