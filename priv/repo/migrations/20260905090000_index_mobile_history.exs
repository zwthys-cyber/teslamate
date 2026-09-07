defmodule TeslaMate.Repo.Migrations.IndexMobileHistory do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:drives, [:car_id, :start_date, :id], concurrently: true)
    create index(:charging_processes, [:car_id, :start_date, :id], concurrently: true)
  end
end
