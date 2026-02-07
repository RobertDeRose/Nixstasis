defmodule Nixstasis.Monitoring.AlertRule do
  @moduledoc """
  Resource for telemetry alert rules.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "alert_rules"
    repo Nixstasis.Repo

    custom_indexes do
      index [:product_name]
    end
  end

  json_api do
    type "alert_rule"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:product_name, :condition_field, :operator, :threshold_value]
    end

    update :update do
      accept [:product_name, :condition_field, :operator, :threshold_value]
    end
  end

  attributes do
    integer_primary_key :id

    attribute :product_name, :string do
      allow_nil? false
    end

    attribute :condition_field, :string do
      allow_nil? false
    end

    attribute :operator, Nixstasis.Types.RuleOperator do
      allow_nil? false
    end

    attribute :threshold_value, :string do
      allow_nil? false
    end

    timestamps()
  end
end
