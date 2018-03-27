defmodule UserSettings do
  def get(user_id) do
    %{
      timezone_offset: 0,
      theme: "dark",
      status: "online",
      show_current_game: false,
      restricted_guilds: [],
      render_reactions: true,
      render_embeds: true,
      message_display_compact: true,
      locale: "en-US",
      inline_embed_media: true,
      inline_attachment_media: true,
      guild_positions: [],
      friend_source_flags: %{
        all: true,
      },
      explicit_content_filter: 1,
      enable_tts_command: false,
      developer_mode: true,
      detect_platform_accounts: false,
      default_guilds_restricted: false,
      convert_emoticons: true,
      afk_timeout: 600,
    }
  end
end

defmodule GuildSettings do
end

defmodule UserGuildSettings do
end
