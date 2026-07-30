defmodule Nixstasis.CommandCatalog.PackageMapping do
  @moduledoc """
  OS-aware package and executable path mapping for a curated catalog command.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "command_catalog_package_mappings"
    repo Nixstasis.Repo

    references do
      reference :catalog_command, on_delete: :delete
    end

    custom_indexes do
      index [:catalog_command_id]
      index [:os_family]
      index [:package_name]
    end

    identity_index_names unique_command_os_family_path: "command_catalog_mapping_command_os_path_idx"
  end

  json_api do
    type "command_catalog_package_mapping"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :catalog_command_id,
        :os_family,
        :package_manager,
        :package_name,
        :command_path,
        :install_hint,
        :supported
      ]
    end

    update :update do
      require_atomic? false

      accept [:os_family, :package_manager, :package_name, :command_path, :install_hint, :supported]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :os_family, :string do
      allow_nil? false
      constraints match: ~r/^(debian|fedora|nixos)$/
      public? true
    end

    attribute :package_manager, :string do
      allow_nil? false
      constraints match: ~r/^[a-z0-9_.-]+$/
      public? true
    end

    attribute :package_name, :string do
      allow_nil? false
      constraints match: ~r/^[A-Za-z0-9_.+:-]+$/
      public? true
    end

    attribute :command_path, :string do
      allow_nil? false
      constraints match: ~r/^\/[^\s;&|`$<>(){}\[\]*?!'"]+$/
      public? true
    end

    attribute :install_hint, :string do
      default ""
      public? true
    end

    attribute :supported, :boolean do
      allow_nil? false
      default true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :catalog_command, Nixstasis.CommandCatalog.CatalogCommand do
      allow_nil? false
      public? true
      attribute_public? true
      attribute_writable? true
    end
  end

  identities do
    identity :unique_command_os_family_path, [:catalog_command_id, :os_family, :command_path]
  end
end
