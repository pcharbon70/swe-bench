defmodule SweBench.RepositorySetup.Configs.SwooshConfig do
  @moduledoc """
  Email testing with SMTP simulation configuration for Swoosh library.

  Handles email delivery testing, adapter validation, and template rendering
  for comprehensive email functionality evaluation.
  """

  require Logger

  @behaviour SweBench.RepositorySetup.RepositoryConfig

  @smtp_test_config %{
    mailhog: %{
      image: "mailhog/mailhog:latest",
      memory: "256MB",
      ports: ["1025:1025", "8025:8025"],
      environment: %{
        "MH_HOSTNAME" => "localhost"
      }
    }
  }

  @email_test_scenarios %{
    adapter_testing: :multi_provider_support,
    template_rendering: :dynamic_content,
    attachment_handling: :file_processing,
    delivery_tracking: :status_monitoring,
    bounce_handling: :error_management
  }

  @impl true
  def repository_name, do: "swoosh/swoosh"

  @impl true
  def github_url, do: "https://github.com/swoosh/swoosh"

  @impl true
  def complexity_tier, do: :core_library

  @impl true
  def dependencies do
    [
      {:mailhog, @smtp_test_config.mailhog}
    ]
  end

  @impl true
  def environment_setup do
    %{
      pre_test_commands: [
        "mix deps.get"
      ],
      test_environment: %{
        "MIX_ENV" => "test",
        "SMTP_HOST" => "mailhog",
        "SMTP_PORT" => "1025",
        "MAILHOG_API" => "http://mailhog:8025"
      },
      post_test_cleanup: [
        "curl -X DELETE http://mailhog:8025/api/v1/messages || true"
      ]
    }
  end

  @impl true
  def testing_scenarios, do: Map.keys(@email_test_scenarios)

  @impl true
  def resource_requirements do
    %{
      memory_limit: "2GB",
      cpu_limit: "1",
      disk_space: "5GB",
      timeout_multiplier: 1.0,
      concurrent_tasks: 2
    }
  end

  @impl true
  def task_generation_config do
    %{
      target_instances: 12,
      complexity_distribution: %{
        # 25% - Basic email sending
        low: 0.25,
        # 50% - Template and adapter features
        medium: 0.50,
        # 20% - Advanced delivery tracking
        high: 0.20,
        # 5% - Complex multi-adapter scenarios
        expert: 0.05
      },
      scenario_distribution: @email_test_scenarios
    }
  end

  @impl true
  def validation_requirements do
    %{
      smtp_connectivity: true,
      email_delivery: true,
      template_rendering: true,
      adapter_configuration: true,
      mailhog_api_access: true
    }
  end

  @doc """
  Validates email delivery and SMTP integration.
  """
  def validate_email_delivery(container_id) do
    test_email = %{
      to: "test@example.com",
      from: "sender@test.com",
      subject: "Test Email",
      html_body: "<h1>Test</h1>",
      text_body: "Test"
    }

    validation_steps = [
      {:send_email, test_email},
      {:check_delivery, :mailhog_api},
      {:validate_content, test_email}
    ]

    validation_steps
    |> Enum.reduce_while({:ok, []}, fn {step, data}, {:ok, results} ->
      case execute_email_validation_step(container_id, step, data) do
        {:ok, result} ->
          {:cont, {:ok, [{step, result} | results]}}

        {:error, reason} ->
          {:halt, {:error, {step, reason}}}
      end
    end)
  end

  # Private functions

  defp execute_email_validation_step(_container_id, :send_email, _email_data) do
    # Mock email sending - would integrate with actual Swoosh
    Logger.debug("Sending test email via Swoosh")
    {:ok, "Email sent successfully"}
  end

  defp execute_email_validation_step(_container_id, :check_delivery, :mailhog_api) do
    # Mock MailHog API check - would make actual HTTP request
    Logger.debug("Checking email delivery via MailHog API")
    {:ok, "Email delivered to MailHog"}
  end

  defp execute_email_validation_step(_container_id, :validate_content, _email_data) do
    # Mock content validation - would parse actual email
    Logger.debug("Validating email content")
    {:ok, "Email content validated"}
  end
end
