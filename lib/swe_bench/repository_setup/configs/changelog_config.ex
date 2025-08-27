defmodule SweBench.RepositorySetup.Configs.ChangelogConfig do
  @moduledoc """
  Media processing and CMS functionality configuration for Changelog.com.

  Handles podcast generation, file uploads, content management, and CDN
  integration for realistic media-rich application testing.
  """

  require Logger

  @behaviour SweBench.RepositorySetup.RepositoryConfig

  @media_processing_config %{
    ffmpeg: %{
      image: "jrottenberg/ffmpeg:alpine",
      memory: "2GB",
      volumes: ["media_processing:/tmp/media"]
    },
    imagemagick: %{
      packages: ["imagemagick", "imagemagick-dev"],
      memory_limit: "1GB"
    }
  }

  @cms_test_scenarios %{
    file_upload: :multipart_handling,
    audio_processing: :podcast_generation,
    image_optimization: :responsive_images,
    feed_generation: :rss_validation,
    content_delivery: :cdn_integration
  }

  @impl true
  def repository_name, do: "thechangelog/changelog.com"

  @impl true
  def github_url, do: "https://github.com/thechangelog/changelog.com"

  @impl true
  def complexity_tier, do: :production

  @impl true
  def dependencies do
    [
      {:postgresql, standard_postgres_config()},
      {:redis, standard_redis_config()},
      {:media_processor, @media_processing_config.ffmpeg},
      {:imagemagick, @media_processing_config.imagemagick}
    ]
  end

  @impl true
  def environment_setup do
    %{
      pre_test_commands: [
        "mix deps.get",
        "mix ecto.create",
        "mix ecto.migrate",
        "mkdir -p /tmp/media && chmod 777 /tmp/media"
      ],
      test_environment: %{
        "MIX_ENV" => "test",
        "DATABASE_URL" => "postgres://postgres:postgres@postgres:5432/changelog_test",
        "AWS_ACCESS_KEY_ID" => "test_access_key",
        "AWS_SECRET_ACCESS_KEY" => "test_secret_key",
        "CDN_HOST" => "localhost:4000",
        "MEDIA_PATH" => "/tmp/media"
      },
      post_test_cleanup: [
        "mix ecto.drop",
        "rm -rf /tmp/media/*"
      ]
    }
  end

  @impl true
  def testing_scenarios, do: Map.keys(@cms_test_scenarios)

  @impl true
  def resource_requirements do
    %{
      memory_limit: "6GB",
      cpu_limit: "3",
      disk_space: "15GB",
      timeout_multiplier: 2.5,
      concurrent_tasks: 6
    }
  end

  @impl true
  def task_generation_config do
    %{
      target_instances: 15,
      complexity_distribution: %{
        low: 0.20,     # 20% - Basic CMS operations
        medium: 0.40,  # 40% - File processing
        high: 0.30,    # 30% - Media pipeline
        expert: 0.10   # 10% - Advanced CDN integration
      },
      scenario_distribution: @cms_test_scenarios
    }
  end

  @impl true
  def validation_requirements do
    %{
      database_connectivity: true,
      media_processing_capability: true,
      file_upload_handling: true,
      podcast_feed_generation: true,
      cdn_integration: true
    }
  end

  @doc """
  Generates test media files for realistic evaluation scenarios.
  """
  def generate_test_media_files do
    %{
      audio_files: [
        %{name: "test_podcast.mp3", size_mb: 50, duration_seconds: 3600},
        %{name: "intro_audio.wav", size_mb: 10, duration_seconds: 30}
      ],
      image_files: [
        %{name: "podcast_cover.png", size_kb: 500, dimensions: "1400x1400"},
        %{name: "episode_banner.jpg", size_kb: 200, dimensions: "1200x630"}
      ],
      video_files: [
        %{name: "episode_preview.mp4", size_mb: 100, duration_seconds: 300}
      ]
    }
  end

  @doc """
  Validates media processing pipeline functionality.
  """
  def validate_media_processing(container_id) do
    validation_tasks = [
      {:audio_conversion, "ffmpeg -i input.wav output.mp3"},
      {:image_resize, "convert input.png -resize 800x600 output.png"},
      {:podcast_feed, "mix changelog.feed.generate"}
    ]
    
    validation_tasks
    |> Enum.reduce_while({:ok, []}, fn {task_type, command}, {:ok, results} ->
        case execute_media_command(container_id, command) do
          {:ok, result} -> 
            {:cont, {:ok, [{task_type, result} | results]}}
          {:error, reason} -> 
            {:halt, {:error, {task_type, reason}}}
        end
    end)
  end

  # Private functions

  defp standard_postgres_config do
    %{
      image: "postgres:13",
      memory: "1GB",
      environment: %{
        "POSTGRES_DB" => "changelog_test",
        "POSTGRES_USER" => "postgres",
        "POSTGRES_PASSWORD" => "postgres"
      }
    }
  end

  defp standard_redis_config do
    %{
      image: "redis:6-alpine",
      memory: "512MB"
    }
  end

  defp execute_media_command(_container_id, command) do
    # Mock media command execution - would integrate with actual container
    Logger.debug("Executing media command: #{command}")
    
    cond do
      String.contains?(command, "ffmpeg") ->
        {:ok, "Audio conversion successful"}
      
      String.contains?(command, "convert") ->
        {:ok, "Image processing successful"}
      
      String.contains?(command, "feed.generate") ->
        {:ok, "Podcast feed generated successfully"}
      
      true ->
        {:ok, "Command executed"}
    end
  end
end